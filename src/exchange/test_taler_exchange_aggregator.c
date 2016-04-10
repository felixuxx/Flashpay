/*
  This file is part of TALER
  (C) 2016 Inria and GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file exchange/test_taler_exchange_aggregator.c
 * @brief Tests for taler-exchange-aggregator logic
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
#include <microhttpd.h>


/**
 * Maximum POST request size (for /admin/add/incoming)
 */
#define REQUEST_BUFFER_MAX (4*1024)

/**
 * Details about a transcation we (as the simulated bank) received.
 */
struct Transaction
{

  /**
   * We store transactions in a DLL.
   */
  struct Transaction *next;

  /**
   * We store transactions in a DLL.
   */
  struct Transaction *prev;

  /**
   * Amount to be transferred.
   */
  struct TALER_Amount amount;

  /**
   * Account to debit.
   */
  uint64_t debit_account;

  /**
   * Account to credit.
   */
  uint64_t credit_account;

  /**
   * Subject of the transfer.
   */
  struct TALER_WireTransferIdentifierRawP wtid;
};


/**
 * Commands for the interpreter.
 */
enum OpCode {

  /**
   * Terminate testcase with 'skipped' result.
   */
  OPCODE_TERMINATE_SKIP,

  /**
   * Run taler-exchange-aggregator.
   */
  OPCODE_RUN_AGGREGATOR,

  /**
   * Expect that we have exhaustively gone over all transactions.
   */
  OPCODE_EXPECT_TRANSACTIONS_EMPTY,

  /**
   * Execute deposit operation against database.
   */
  OPCODE_DATABASE_DEPOSIT,

  /**
   * Wait a certain amount of time.
   */
  OPCODE_WAIT,

  /**
   * Expect that we have received the specified transaction.
   */
  OPCODE_EXPECT_TRANSACTION,

  /**
   * Finish testcase with success.
   */
  OPCODE_TERMINATE_SUCCESS
};

/**
 * Command state for the interpreter.
 */
struct Command
{

  /**
   * What instruction should we run?
   */
  enum OpCode opcode;

  /**
   * Human-readable label for the command.
   */
  const char *label;

  union {

    /**
     * If @e opcode is #OPCODE_EXPECT_TRANSACTION, this
     * specifies which transaction we expected.  Note that
     * the WTID will be set, not checked!
     */
    struct {

      /**
       * Amount to be transferred.
       */
      const char *amount;

      /**
       * Account to debit.
       */
      uint64_t debit_account;

      /**
       * Account to credit.
       */
      uint64_t credit_account;

      /**
       * Subject of the transfer, set by the command.
       */
      struct TALER_WireTransferIdentifierRawP wtid;

    } expect_transaction;

    /**
     * If @e opcode is #OPCODE_DATABASE_DEPOST, this
     * specifies which deposit operation we should fake.
     */
    struct {

      /**
       * Each merchant name is automatically mapped to a unique
       * merchant public key.
       */
      const char *merchant_name;

      /**
       * Merchant account number, is mapped to wire details.
       */
      uint64_t merchant_account;

      /**
       * Merchant's transaction ID.
       */
      uint64_t transaction_id;

      /**
       * By when does the merchant request the funds to be wired.
       */
      struct GNUNET_TIME_Relative wire_deadline;

      /**
       * What is the total amount (including exchange fees).
       */
      const char *amount_with_fee;

      /**
       * How high are the exchange fees? Must be smaller than @e amount_with_fee.
       */
      const char *deposit_fee;

    } deposit;

    /**
     * How long should we wait if the opcode is #OPCODE_WAIT.
     */
    struct GNUNET_TIME_Relative wait_delay;

  } details;

};


/**
 * State of the interpreter.
 */
struct State
{
  /**
   * Array of commands to run.
   */
  struct Command* commands;

  /**
   * Offset of the next command to be run.
   */
  unsigned int ioff;
};


/**
 * Pipe used to communicate child death via signal.
 */
static struct GNUNET_DISK_PipeHandle *sigpipe;

/**
 * ID of task called whenever we get a SIGCHILD.
 */
static struct GNUNET_SCHEDULER_Task *child_death_task;

/**
 * ID of task called whenever are shutting down.
 */
static struct GNUNET_SCHEDULER_Task *shutdown_task;

/**
 * Return value from main().
 */
static int result;

/**
 * Name of the configuration file to use.
 */
static char *config_filename;

/**
 * Database plugin.
 */
static struct TALER_EXCHANGEDB_Plugin *plugin;

/**
 * Our session with the database.
 */
static struct TALER_EXCHANGEDB_Session *session;

/**
 * The handle for the aggregator process that we are testing.
 */
static struct GNUNET_OS_Process *aggregator_proc;

/**
 * State of our interpreter while we are running the aggregator
 * process.
 */
static struct State *aggregator_state;

/**
 * HTTP server we run to pretend to be the "test" bank.
 */
static struct MHD_Daemon *mhd_bank;

/**
 * Task running HTTP server for the "test" bank.
 */
static struct GNUNET_SCHEDULER_Task *mhd_task;

/**
 * Task running the interpreter().
 */
static struct GNUNET_SCHEDULER_Task *int_task;

/**
 * We store transactions in a DLL.
 */
static struct Transaction *transactions_head;

/**
 * We store transactions in a DLL.
 */
static struct Transaction *transactions_tail;

/**
 * Private key we use for fake coins.
 */
static struct GNUNET_CRYPTO_RsaPrivateKey *coin_pk;

/**
 * Public key we use for fake coins.
 */
static struct GNUNET_CRYPTO_RsaPublicKey *coin_pub;


/**
 * Interprets the commands from the test program.
 *
 * @param cls the `struct State` of the interpreter
 */
static void
interpreter (void *cls);


/**
 * Task triggered whenever we are to shutdown.
 *
 * @param cls closure, NULL if we need to self-restart
 */
static void
shutdown_action (void *cls)
{
  shutdown_task = NULL;
  if (NULL != mhd_task)
  {
    GNUNET_SCHEDULER_cancel (mhd_task);
    mhd_task = NULL;
  }
  if (NULL != int_task)
  {
    GNUNET_SCHEDULER_cancel (int_task);
    int_task = NULL;
  }
  if (NULL != mhd_bank)
  {
    MHD_stop_daemon (mhd_bank);
    mhd_bank = NULL;
  }
  if (NULL == aggregator_proc)
  {
    GNUNET_SCHEDULER_cancel (child_death_task);
    child_death_task = NULL;
  }
  else
  {
    GNUNET_break (0 == GNUNET_OS_process_kill (aggregator_proc,
                                               SIGKILL));
  }
  plugin->drop_temporary (plugin->cls,
                          session);
  TALER_EXCHANGEDB_plugin_unload (plugin);
  plugin = NULL;
}


/**
 * Task triggered whenever we receive a SIGCHLD (child
 * process died).
 *
 * @param cls closure, NULL if we need to self-restart
 */
static void
maint_child_death (void *cls)
{
  const struct GNUNET_DISK_FileHandle *pr;
  char c[16];
  struct State *state;
  const struct GNUNET_SCHEDULER_TaskContext *tc;

  child_death_task = NULL;
  pr = GNUNET_DISK_pipe_handle (sigpipe, GNUNET_DISK_PIPE_END_READ);
  tc = GNUNET_SCHEDULER_get_task_context ();
  if (0 == (tc->reason & GNUNET_SCHEDULER_REASON_READ_READY))
  {
    /* shutdown scheduled us, ignore! */
    child_death_task =
      GNUNET_SCHEDULER_add_read_file (GNUNET_TIME_UNIT_FOREVER_REL,
                                      pr,
                                      &maint_child_death,
                                      NULL);
    return;
  }
  GNUNET_break (0 < GNUNET_DISK_file_read (pr, &c, sizeof (c)));
  GNUNET_OS_process_wait (aggregator_proc);
  GNUNET_OS_process_destroy (aggregator_proc);
  aggregator_proc = NULL;
  aggregator_state->ioff++;
  state = aggregator_state;
  aggregator_state = NULL;
  interpreter (state);
  if (NULL == shutdown_task)
    return;
  child_death_task = GNUNET_SCHEDULER_add_read_file (GNUNET_TIME_UNIT_FOREVER_REL,
                                                     pr,
                                                     &maint_child_death, NULL);

}

/**
 * Setup (fake) information about a coin used in deposit.
 *
 * @param[out] issue information to initialize with "valid" data
 */
static void
fake_issue (struct TALER_EXCHANGEDB_DenominationKeyInformationP *issue)
{
  memset (issue, 0, sizeof (struct TALER_EXCHANGEDB_DenominationKeyInformationP));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount_nbo ("EUR:1",
                                             &issue->properties.value));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount_nbo ("EUR:0.1",
                                             &issue->properties.fee_withdraw));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount_nbo ("EUR:0.1",
                                             &issue->properties.fee_deposit));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount_nbo ("EUR:0.1",
                                             &issue->properties.fee_refresh));
}


/**
 * Setup (fake) information about a coin used in deposit.
 *
 * @param[out] coin information to initialize with "valid" data
 */
static void
fake_coin (struct TALER_CoinPublicInfo *coin)
{
  struct GNUNET_HashCode hc;

  coin->denom_pub.rsa_public_key = coin_pub;
  GNUNET_CRYPTO_hash_create_random (GNUNET_CRYPTO_QUALITY_WEAK,
                                    &hc);
  coin->denom_sig.rsa_signature = GNUNET_CRYPTO_rsa_sign_fdh (coin_pk,
                                                              &hc);
}


/**
 * Helper function to fake a deposit operation.
 *
 * @return #GNUNET_OK on success
 */
static int
do_deposit (struct Command *cmd)
{
  struct TALER_EXCHANGEDB_Deposit deposit;
  struct TALER_MerchantPrivateKeyP merchant_priv;
  int ret;

  memset (&deposit, 0, sizeof (deposit));
  /* we derive the merchant's private key from the
     name, to ensure that the same name always
     results in the same key pair. */
  GNUNET_CRYPTO_kdf (&merchant_priv,
                     sizeof (struct TALER_MerchantPrivateKeyP),
                     "merchant-priv",
                     strlen ("merchant-priv"),
                     cmd->details.deposit.merchant_name,
                     strlen (cmd->details.deposit.merchant_name),
                     NULL, 0);
  GNUNET_CRYPTO_eddsa_key_get_public (&merchant_priv.eddsa_priv,
                                      &deposit.merchant_pub.eddsa_pub);
  /* contract is just picked at random;
     note: we may want to write this back to 'cmd' in the future. */
  GNUNET_CRYPTO_hash_create_random (GNUNET_CRYPTO_QUALITY_WEAK,
                                    &deposit.h_contract);
  if ( (GNUNET_OK !=
        TALER_string_to_amount (cmd->details.deposit.amount_with_fee,
                                &deposit.amount_with_fee)) ||
       (GNUNET_OK !=
        TALER_string_to_amount (cmd->details.deposit.deposit_fee,
                                &deposit.deposit_fee)) )
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  fake_coin (&deposit.coin);
  /* Build JSON for wire details;
     note that this simple method may fail in the future if we implement
     and enforce signature checking on test-wire account details */
  deposit.wire = json_pack ("{s:s, s:s, s:I}",
                            "type", "test",
                            "bank_uri", "http://localhost:8082/",
                            "account_number", (json_int_t) cmd->details.deposit.merchant_account);
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_hash (deposit.wire,
                                  &deposit.h_wire));
  deposit.transaction_id = cmd->details.deposit.transaction_id;
  deposit.timestamp = GNUNET_TIME_absolute_get ();
  deposit.wire_deadline = GNUNET_TIME_relative_to_absolute (cmd->details.deposit.wire_deadline);

  /* finally, actually perform the DB operation */
  if ( (GNUNET_OK !=
        plugin->start (plugin->cls,
                       session)) ||
       (GNUNET_OK !=
        plugin->insert_deposit (plugin->cls,
                                session,
                                &deposit)) ||
       (GNUNET_OK !=
        plugin->commit (plugin->cls,
                        session)) )
    ret = GNUNET_SYSERR;
  else
    ret = GNUNET_OK;
  GNUNET_CRYPTO_rsa_signature_free (deposit.coin.denom_sig.rsa_signature);
  json_decref (deposit.wire);
  return ret;
}


/**
 * Fail the testcase at the current command.
 */
static void
fail (struct Command *cmd)
{
  fprintf (stderr,
           "Testcase failed at command `%s'\n",
           cmd->label);
  result = 2;
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Interprets the commands from the test program.
 *
 * @param cls the `struct State` of the interpreter
 */
static void
interpreter (void *cls)
{
  struct State *state = cls;

  int_task = NULL;
  while (1)
  {
    struct Command *cmd = &state->commands[state->ioff];

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Running command %u (%s)\n",
                state->ioff,
                cmd->label);
    switch (cmd->opcode)
    {
    case OPCODE_TERMINATE_SKIP:
      /* return skip: test not finished, but did not fail either */
      result = 77;
      GNUNET_SCHEDULER_shutdown ();
      return;
    case OPCODE_WAIT:
      state->ioff++;
      int_task = GNUNET_SCHEDULER_add_delayed (cmd->details.wait_delay,
                                               &interpreter,
                                               state);
      return;
    case OPCODE_RUN_AGGREGATOR:
      GNUNET_assert (NULL == aggregator_state);
      aggregator_state = state;
      aggregator_proc
        = GNUNET_OS_start_process (GNUNET_NO,
                                   GNUNET_OS_INHERIT_STD_ALL,
                                   NULL, NULL, NULL,
                                   "taler-exchange-aggregator",
                                   "taler-exchange-aggregator",
                                   "-c", "test_taler_exchange_httpd.conf",
                                   "-t", /* enable temporary tables */
                                   NULL);
    return;
    case OPCODE_EXPECT_TRANSACTIONS_EMPTY:
      if (NULL != transactions_head)
      {
        struct Transaction *t;

        fprintf (stderr,
                 "Expected empty transaction set, but I have:\n");
        for (t = transactions_head; NULL != t; t = t->next)
        {
          char *s;

          s = TALER_amount_to_string (&t->amount);
          fprintf (stderr,
                   "%llu -> %llu (%s)\n",
                   (unsigned long long) t->debit_account,
                   (unsigned long long) t->credit_account,
                   s);
          GNUNET_free (s);
        }
        fail (cmd);
        return;
      }
      state->ioff++;
      break;
    case OPCODE_DATABASE_DEPOSIT:
      if (GNUNET_OK !=
          do_deposit (cmd))
      {
        fail (cmd);
        return;
      }
      state->ioff++;
      break;
    case OPCODE_EXPECT_TRANSACTION:
      {
        struct TALER_Amount want_amount;
        struct Transaction *t;
        int found;

        if (GNUNET_OK !=
            TALER_string_to_amount (cmd->details.expect_transaction.amount,
                                    &want_amount))
        {
          GNUNET_break (0);
          fail (cmd);
          return;
        }
        found = GNUNET_NO;
        for (t = transactions_head; NULL != t; t = t->next)
        {
          if ( (cmd->details.expect_transaction.debit_account == t->debit_account) &&
               (cmd->details.expect_transaction.credit_account == t->credit_account) &&
               (0 == TALER_amount_cmp (&want_amount,
                                       &t->amount)) )
          {
            GNUNET_CONTAINER_DLL_remove (transactions_head,
                                         transactions_tail,
                                         t);
            cmd->details.expect_transaction.wtid = t->wtid;
            GNUNET_free (t);
            found = GNUNET_YES;
            break;
          }
        }
        if (GNUNET_NO == found)
        {
          fprintf (stderr,
                   "Did not find matching transaction!\nI have:\n");
          for (t = transactions_head; NULL != t; t = t->next)
          {
            char *s;

            s = TALER_amount_to_string (&t->amount);
            fprintf (stderr,
                     "%llu -> %llu (%s)\n",
                     (unsigned long long) t->debit_account,
                     (unsigned long long) t->credit_account,
                     s);
            GNUNET_free (s);
          }
          fail (cmd);
          return;
        }
        state->ioff++;
        break;
      }
    case OPCODE_TERMINATE_SUCCESS:
      result = 0;
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
  }
}


/**
 * Contains the test program. Here each step of the testcase
 * is defined.
 */
static void
run_test ()
{
  static struct Command commands[] = {
    /* test running with empty DB */
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-on-empty-db"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTIONS_EMPTY,
      .label = "expect-empty-transactions-on-start"
    },

    /* test simple deposit */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-1",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:1",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-1"
    },

    {
      .opcode = OPCODE_EXPECT_TRANSACTION,
      .label = "expect-deposit-1",
      .details.expect_transaction.debit_account = 3,
      .details.expect_transaction.credit_account = 4,
      .details.expect_transaction.amount = "EUR:1"
    },

    {
      .opcode = OPCODE_EXPECT_TRANSACTIONS_EMPTY,
      .label = "expect-empty-transactions-on-start"
    },

    /* test idempotency: run again on transactions already done */
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-1"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTIONS_EMPTY,
      .label = "expect-empty-transactions-after-1"
    },

    /* test combining deposits */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-2a",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:1",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-2b",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:1",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-2"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTION,
      .label = "expect-deposit-2",
      .details.expect_transaction.debit_account = 3,
      .details.expect_transaction.credit_account = 4,
      .details.expect_transaction.amount = "EUR:2"
    },

    {
      .opcode = OPCODE_EXPECT_TRANSACTIONS_EMPTY,
      .label = "expect-empty-transactions-after-2"
    },

    /* test NOT combining deposits of different accounts or keys */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-3a",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:1",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-3b",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 5,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:1",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-3c",
      .details.deposit.merchant_name = "alice",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:1",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-3"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTION,
      .label = "expect-deposit-3a",
      .details.expect_transaction.debit_account = 3,
      .details.expect_transaction.credit_account = 4,
      .details.expect_transaction.amount = "EUR:1"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTION,
      .label = "expect-deposit-3b",
      .details.expect_transaction.debit_account = 3,
      .details.expect_transaction.credit_account = 4,
      .details.expect_transaction.amount = "EUR:1"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTION,
      .label = "expect-deposit-3c",
      .details.expect_transaction.debit_account = 3,
      .details.expect_transaction.credit_account = 5,
      .details.expect_transaction.amount = "EUR:1"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTIONS_EMPTY,
      .label = "expect-empty-transactions-after-3"
    },

    /* test NOT running deposits instantly, but after delay */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-4a",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 5 }, /* 5s */
      .details.deposit.amount_with_fee = "EUR:0.01",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-4b",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 5 }, /* 5s */
      .details.deposit.amount_with_fee = "EUR:0.01",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-4-early"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTIONS_EMPTY,
      .label = "expect-empty-transactions-after-4-fast"
    },
    {
      .opcode = OPCODE_WAIT,
      .label = "wait (5s)",
      .details.wait_delay = { 1000LL * 1000 * 6 } /* 6s */
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-4-delayed"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTION,
      .label = "expect-deposit-4",
      .details.expect_transaction.debit_account = 3,
      .details.expect_transaction.credit_account = 4,
      .details.expect_transaction.amount = "EUR:0.02"
    },

    /* test picking all deposits at earliest deadline */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-5a",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 10 }, /* 10s */
      .details.deposit.amount_with_fee = "EUR:0.01",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-5b",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 5 }, /* 5s */
      .details.deposit.amount_with_fee = "EUR:0.01",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-5-early"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTIONS_EMPTY,
      .label = "expect-empty-transactions-after-5-early"
    },
    {
      .opcode = OPCODE_WAIT,
      .label = "wait (5s)",
      .details.wait_delay = { 1000LL * 1000 * 6 } /* 6s */
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-5-delayed"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTION,
      .label = "expect-deposit-5",
      .details.expect_transaction.debit_account = 3,
      .details.expect_transaction.credit_account = 4,
      .details.expect_transaction.amount = "EUR:0.02"
    },

    /* Test NEVER running 'tiny' unless they make up minimum unit */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-6a",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.002",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-6a-tiny"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTIONS_EMPTY,
      .label = "expect-empty-transactions-after-6a-tiny"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-6b",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.002",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-6c",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.002",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-6c-tiny"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTIONS_EMPTY,
      .label = "expect-empty-transactions-after-6c-tiny"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-6d",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.002",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-6d-tiny"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTIONS_EMPTY,
      .label = "expect-empty-transactions-after-6d-tiny"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-6e",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.002",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-6e"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTION,
      .label = "expect-deposit-6",
      .details.expect_transaction.debit_account = 3,
      .details.expect_transaction.credit_account = 4,
      .details.expect_transaction.amount = "EUR:0.01"
    },

    /* Test profiteering if wire deadline is short */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-7a",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.009",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-7a-tiny"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTIONS_EMPTY,
      .label = "expect-empty-transactions-after-7a-tiny"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-7b",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.009",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-7-profit"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTION,
      .label = "expect-deposit-7",
      .details.expect_transaction.debit_account = 3,
      .details.expect_transaction.credit_account = 4,
      .details.expect_transaction.amount = "EUR:0.01"
    },
    /* Now check profit was actually taken */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-7c",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.022",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-7c-loss"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTION,
      .label = "expect-deposit-7",
      .details.expect_transaction.debit_account = 3,
      .details.expect_transaction.credit_account = 4,
      .details.expect_transaction.amount = "EUR:0.02"
    },

    /* Test that aggregation would happen fully if wire deadline is long */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-8a",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 5 }, /* 5s */
      .details.deposit.amount_with_fee = "EUR:0.009",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-8a-tiny"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTIONS_EMPTY,
      .label = "expect-empty-transactions-after-8a-tiny"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-8b",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 5 }, /* 5s */
      .details.deposit.amount_with_fee = "EUR:0.009",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-8b-tiny"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTIONS_EMPTY,
      .label = "expect-empty-transactions-after-8b-tiny"
    },
    /* now trigger aggregate with large transaction and short deadline */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-8c",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.022",
      .details.deposit.deposit_fee = "EUR:0"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-8"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTION,
      .label = "expect-deposit-8",
      .details.expect_transaction.debit_account = 3,
      .details.expect_transaction.credit_account = 4,
      .details.expect_transaction.amount = "EUR:0.04"
    },


    /* Test aggregation with fees and rounding profits */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-9a",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 5 }, /* 5s */
      .details.deposit.amount_with_fee = "EUR:0.009",
      .details.deposit.deposit_fee = "EUR:0.001"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-9a-tiny"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTIONS_EMPTY,
      .label = "expect-empty-transactions-after-9a-tiny"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-9b",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 5 }, /* 5s */
      .details.deposit.amount_with_fee = "EUR:0.009",
      .details.deposit.deposit_fee = "EUR:0.002"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-9b-tiny"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTIONS_EMPTY,
      .label = "expect-empty-transactions-after-9b-tiny"
    },
    /* now trigger aggregate with large transaction and short deadline */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-9c",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.transaction_id = 1,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.022",
      .details.deposit.deposit_fee = "EUR:0.008"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-deposit-9"
    },
    /* 0.009 + 0.009 + 0.022 - 0.001 - 0.002 - 0.008 = 0.029 => 0.02 */
    {
      .opcode = OPCODE_EXPECT_TRANSACTION,
      .label = "expect-deposit-9",
      .details.expect_transaction.debit_account = 3,
      .details.expect_transaction.credit_account = 4,
      .details.expect_transaction.amount = "EUR:0.02"
    },

    /* Everything tested, terminate with success */
    {
      .opcode = OPCODE_TERMINATE_SUCCESS,
      .label = "testcase-complete-terminating-with-success"
    },
    /* note: rest not reached, this is just sample code */
    {
      .opcode = OPCODE_TERMINATE_SKIP,
      .label = "testcase-incomplete-terminating-with-skip"
    }
  };
  static struct State state = {
    .commands = commands
  };

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Launching interpreter\n");
  int_task = GNUNET_SCHEDULER_add_now (&interpreter,
                                       &state);
}


/**
 * Function called whenever MHD is done with a request.  If the
 * request was a POST, we may have stored a `struct Buffer *` in the
 * @a con_cls that might still need to be cleaned up.  Call the
 * respective function to free the memory.
 *
 * @param cls client-defined closure
 * @param connection connection handle
 * @param con_cls value as set by the last call to
 *        the #MHD_AccessHandlerCallback
 * @param toe reason for request termination
 * @see #MHD_OPTION_NOTIFY_COMPLETED
 * @ingroup request
 */
static void
handle_mhd_completion_callback (void *cls,
                                struct MHD_Connection *connection,
                                void **con_cls,
                                enum MHD_RequestTerminationCode toe)
{
  GNUNET_JSON_post_parser_cleanup (*con_cls);
  *con_cls = NULL;
}


/**
 * Handle incoming HTTP request.
 *
 * @param cls closure for MHD daemon (unused)
 * @param connection the connection
 * @param url the requested url
 * @param method the method (POST, GET, ...)
 * @param version HTTP version (ignored)
 * @param upload_data request data
 * @param upload_data_size size of @a upload_data in bytes
 * @param con_cls closure for request (a `struct Buffer *`)
 * @return MHD result code
 */
static int
handle_mhd_request (void *cls,
                    struct MHD_Connection *connection,
                    const char *url,
                    const char *method,
                    const char *version,
                    const char *upload_data,
                    size_t *upload_data_size,
                    void **con_cls)
{
  enum GNUNET_JSON_PostResult pr;
  json_t *json;
  struct Transaction *t;
  struct MHD_Response *resp;
  int ret;

  if (0 != strcasecmp (url,
                       "/admin/add/incoming"))
  {
    /* Unexpected URI path, just close the connection. */
    /* we're rather impolite here, but it's a testcase. */
    GNUNET_break_op (0);
    return MHD_NO;
  }
  pr = GNUNET_JSON_post_parser (REQUEST_BUFFER_MAX,
                                con_cls,
                                upload_data,
                                upload_data_size,
                                &json);
  switch (pr)
  {
  case GNUNET_JSON_PR_OUT_OF_MEMORY:
    GNUNET_break (0);
    return MHD_NO;
  case GNUNET_JSON_PR_CONTINUE:
    return MHD_YES;
  case GNUNET_JSON_PR_REQUEST_TOO_LARGE:
    GNUNET_break (0);
    return MHD_NO;
  case GNUNET_JSON_PR_JSON_INVALID:
    GNUNET_break (0);
    return MHD_NO;
  case GNUNET_JSON_PR_SUCCESS:
    break;
  }
  t = GNUNET_new (struct Transaction);
  {
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto ("wtid", &t->wtid),
      GNUNET_JSON_spec_uint64 ("debit_account", &t->debit_account),
      GNUNET_JSON_spec_uint64 ("credit_account", &t->credit_account),
      TALER_JSON_spec_amount ("amount", &t->amount),
      GNUNET_JSON_spec_end ()
    };
    if (GNUNET_OK !=
        GNUNET_JSON_parse (json,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break (0);
      json_decref (json);
      return MHD_NO;
    }
    GNUNET_CONTAINER_DLL_insert (transactions_head,
                                 transactions_tail,
                                 t);
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Receiving incoming wire transfer: %llu->%llu\n",
              (unsigned long long) t->debit_account,
              (unsigned long long) t->credit_account);
  json_decref (json);
  resp = MHD_create_response_from_buffer (0, "", MHD_RESPMEM_PERSISTENT);
  ret = MHD_queue_response (connection,
                            MHD_HTTP_OK,
                            resp);
  MHD_destroy_response (resp);
  return ret;
}


/**
 * Task run whenever HTTP server operations are pending.
 *
 * @param cls NULL
 */
static void
run_mhd (void *cls);


/**
 * Schedule MHD.  This function should be called initially when an
 * MHD is first getting its client socket, and will then automatically
 * always be called later whenever there is work to be done.
 */
static void
schedule_httpd ()
{
  fd_set rs;
  fd_set ws;
  fd_set es;
  struct GNUNET_NETWORK_FDSet *wrs;
  struct GNUNET_NETWORK_FDSet *wws;
  int max;
  int haveto;
  MHD_UNSIGNED_LONG_LONG timeout;
  struct GNUNET_TIME_Relative tv;

  FD_ZERO (&rs);
  FD_ZERO (&ws);
  FD_ZERO (&es);
  max = -1;
  if (MHD_YES != MHD_get_fdset (mhd_bank, &rs, &ws, &es, &max))
  {
    GNUNET_assert (0);
    return;
  }
  haveto = MHD_get_timeout (mhd_bank, &timeout);
  if (MHD_YES == haveto)
    tv.rel_value_us = (uint64_t) timeout * 1000LL;
  else
    tv = GNUNET_TIME_UNIT_FOREVER_REL;
  if (-1 != max)
  {
    wrs = GNUNET_NETWORK_fdset_create ();
    wws = GNUNET_NETWORK_fdset_create ();
    GNUNET_NETWORK_fdset_copy_native (wrs, &rs, max + 1);
    GNUNET_NETWORK_fdset_copy_native (wws, &ws, max + 1);
  }
  else
  {
    wrs = NULL;
    wws = NULL;
  }
  if (NULL != mhd_task)
    GNUNET_SCHEDULER_cancel (mhd_task);
  mhd_task =
    GNUNET_SCHEDULER_add_select (GNUNET_SCHEDULER_PRIORITY_DEFAULT,
                                 tv,
                                 wrs,
                                 wws,
                                 &run_mhd, NULL);
  if (NULL != wrs)
    GNUNET_NETWORK_fdset_destroy (wrs);
  if (NULL != wws)
    GNUNET_NETWORK_fdset_destroy (wws);
}


/**
 * Task run whenever HTTP server operations are pending.
 *
 * @param cls NULL
 */
static void
run_mhd (void *cls)
{
  mhd_task = NULL;
  MHD_run (mhd_bank);
  schedule_httpd ();
}


/**
 * Main function that will be run by the scheduler.
 *
 * @param cls closure with configuration
 */
static void
run (void *cls)
{
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct TALER_EXCHANGEDB_DenominationKeyInformationP issue;
  struct TALER_DenominationPublicKey dpk;

  plugin = TALER_EXCHANGEDB_plugin_load (cfg);
  if (GNUNET_OK !=
      plugin->create_tables (plugin->cls,
                             GNUNET_YES))
  {
    GNUNET_break (0);
    TALER_EXCHANGEDB_plugin_unload (plugin);
    plugin = NULL;
    result = 77;
    return;
  }
  session = plugin->get_session (plugin->cls,
                                 GNUNET_YES);
  GNUNET_assert (NULL != session);
  fake_issue (&issue);
  dpk.rsa_public_key = coin_pub;
  if ( (GNUNET_OK !=
        plugin->start (plugin->cls,
                       session)) ||
       (GNUNET_OK !=
        plugin->insert_denomination_info (plugin->cls,
                                          session,
                                          &dpk,
                                          &issue)) ||
       (GNUNET_OK !=
        plugin->commit (plugin->cls,
                        session)) )
    {
      GNUNET_break (0);
      TALER_EXCHANGEDB_plugin_unload (plugin);
      plugin = NULL;
      result = 77;
      return;
    }
  child_death_task =
    GNUNET_SCHEDULER_add_read_file (GNUNET_TIME_UNIT_FOREVER_REL,
				    GNUNET_DISK_pipe_handle (sigpipe,
							     GNUNET_DISK_PIPE_END_READ),
				    &maint_child_death, NULL);
  shutdown_task =
    GNUNET_SCHEDULER_add_delayed (GNUNET_TIME_UNIT_FOREVER_REL,
                                  &shutdown_action,
                                  NULL);
  result = 1; /* test failed for undefined reason */
  mhd_bank = MHD_start_daemon (MHD_USE_DEBUG,
                               8082,
                               NULL, NULL,
                               &handle_mhd_request, NULL,
                               MHD_OPTION_NOTIFY_COMPLETED, &handle_mhd_completion_callback, NULL,
                               MHD_OPTION_END);
  if (NULL == mhd_bank)
  {
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  schedule_httpd ();
  run_test ();
}


/**
 * Signal handler called for SIGCHLD.  Triggers the
 * respective handler by writing to the trigger pipe.
 */
static void
sighandler_child_death ()
{
  static char c;
  int old_errno = errno;	/* back-up errno */

  GNUNET_break (1 ==
		GNUNET_DISK_file_write (GNUNET_DISK_pipe_handle
					(sigpipe, GNUNET_DISK_PIPE_END_WRITE),
					&c, sizeof (c)));
  errno = old_errno;		/* restore errno */
}


int
main (int argc,
      char *const argv[])
{
  const char *plugin_name;
  char *testname;
  struct GNUNET_CONFIGURATION_Handle *cfg;
  struct GNUNET_SIGNAL_Context *shc_chld;

  result = -1;
  if (NULL == (plugin_name = strrchr (argv[0], (int) '-')))
  {
    GNUNET_break (0);
    return -1;
  }
  plugin_name++;
  (void) GNUNET_asprintf (&testname,
                          "test-taler-exchange-aggregator-%s", plugin_name);
  (void) GNUNET_asprintf (&config_filename,
                          "%s.conf", testname);
  /* these might get in the way */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test_taler_exchange_aggregator",
                    "WARNING",
                    NULL);
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_parse (cfg,
                                  config_filename))
  {
    GNUNET_break (0);
    GNUNET_free (config_filename);
    GNUNET_free (testname);
    return 2;
  }
  sigpipe = GNUNET_DISK_pipe (GNUNET_NO, GNUNET_NO, GNUNET_NO, GNUNET_NO);
  GNUNET_assert (NULL != sigpipe);
  shc_chld =
    GNUNET_SIGNAL_handler_install (GNUNET_SIGCHLD, &sighandler_child_death);
  coin_pk = GNUNET_CRYPTO_rsa_private_key_create (1024);
  coin_pub = GNUNET_CRYPTO_rsa_private_key_get_public (coin_pk);
  GNUNET_SCHEDULER_run (&run, cfg);
  GNUNET_CRYPTO_rsa_private_key_free (coin_pk);
  GNUNET_CRYPTO_rsa_public_key_free (coin_pub);
  GNUNET_SIGNAL_handler_uninstall (shc_chld);
  shc_chld = NULL;
  GNUNET_DISK_pipe_close (sigpipe);
  GNUNET_CONFIGURATION_destroy (cfg);
  GNUNET_free (config_filename);
  GNUNET_free (testname);
  return result;
}

/* end of test_taler_exchange_aggregator.c */
