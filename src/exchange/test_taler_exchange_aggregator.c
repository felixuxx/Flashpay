/*
  This file is part of TALER
  (C) 2016, 2017, 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
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
#include "taler_fakebank_lib.h"



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
       * Base URL of the exchange.
       */
      const char *exchange_base_url;

      /**
       * Subject of the transfer, set by the command.
       */
      char *subject;

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
 * ID of task called whenever we time out.
 */
static struct GNUNET_SCHEDULER_Task *timeout_task;

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
 * Task running the interpreter().
 */
static struct GNUNET_SCHEDULER_Task *int_task;

/**
 * Private key we use for fake coins.
 */
static struct GNUNET_CRYPTO_RsaPrivateKey *coin_pk;

/**
 * Public key we use for fake coins.
 */
static struct GNUNET_CRYPTO_RsaPublicKey *coin_pub;

/**
 * Handle for our fake bank.
 */
static struct TALER_FAKEBANK_Handle *fb;


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
timeout_action (void *cls)
{
  timeout_task = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Test failed: timeout\n");
  result = 2;
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Task triggered whenever we are to shutdown.
 *
 * @param cls closure, NULL if we need to self-restart
 */
static void
shutdown_action (void *cls)
{
  if (NULL != timeout_task)
  {
    GNUNET_SCHEDULER_cancel (timeout_task);
    timeout_task = NULL;
  }
  if (NULL != int_task)
  {
    GNUNET_SCHEDULER_cancel (int_task);
    int_task = NULL;
  }
  if (NULL != fb)
  {
    TALER_FAKEBANK_stop (fb);
    fb = NULL;
  }
  if (NULL != child_death_task)
  {
    GNUNET_SCHEDULER_cancel (child_death_task);
    child_death_task = NULL;
  }
  if (NULL != aggregator_proc)
  {
    GNUNET_break (0 == GNUNET_OS_process_kill (aggregator_proc,
                                               SIGKILL));
    GNUNET_OS_process_wait (aggregator_proc);
    GNUNET_OS_process_destroy (aggregator_proc);
    aggregator_proc = NULL;
  }
  plugin->drop_tables (plugin->cls);
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

  child_death_task = NULL;
  pr = GNUNET_DISK_pipe_handle (sigpipe, GNUNET_DISK_PIPE_END_READ);
  GNUNET_break (0 < GNUNET_DISK_file_read (pr, &c, sizeof (c)));
  GNUNET_OS_process_wait (aggregator_proc);
  GNUNET_OS_process_destroy (aggregator_proc);
  aggregator_proc = NULL;
  aggregator_state->ioff++;
  state = aggregator_state;
  aggregator_state = NULL;
  child_death_task = GNUNET_SCHEDULER_add_read_file (GNUNET_TIME_UNIT_FOREVER_REL,
                                                     pr,
                                                     &maint_child_death, NULL);

  interpreter (state);
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
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount_nbo ("EUR:0.1",
                                             &issue->properties.fee_refund));
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

  memset (&deposit,
          0,
          sizeof (deposit));
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
                                    &deposit.h_contract_terms);
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
  /* Build JSON for wire details */
  {
    char *str;

    GNUNET_asprintf (&str,
                     "payto://x-taler-bank/localhost:8082/%llu",
                     (unsigned long long) cmd->details.deposit.merchant_account);
    deposit.receiver_wire_account
      = json_pack ("{s:s, s:s}",
                   "salt", "this-is-a-salt-value",
                   "url", str);
    GNUNET_free (str);
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_wire_signature_hash (deposit.receiver_wire_account,
                                                 &deposit.h_wire));
  deposit.timestamp = GNUNET_TIME_absolute_get ();
  GNUNET_TIME_round_abs (&deposit.timestamp);
  deposit.wire_deadline = GNUNET_TIME_relative_to_absolute (cmd->details.deposit.wire_deadline);
  GNUNET_TIME_round_abs (&deposit.wire_deadline);

  /* finally, actually perform the DB operation */
  if ( (GNUNET_OK !=
        plugin->start (plugin->cls,
                       session,
                       "aggregator-test-1")) ||
       (0 >
        plugin->ensure_coin_known (plugin->cls,
                                   session,
                                   &deposit.coin)) ||
       (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
        plugin->insert_deposit (plugin->cls,
                                session,
                                &deposit)) ||
       (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
        plugin->commit (plugin->cls,
                        session)) )
  {
    GNUNET_break (0);
    ret = GNUNET_SYSERR;
  }
  else
    ret = GNUNET_OK;
  GNUNET_CRYPTO_rsa_signature_free (deposit.coin.denom_sig.rsa_signature);
  json_decref (deposit.receiver_wire_account);
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
                                   "-c", config_filename,
                                   "-t", /* enable temporary tables */
                                   NULL);
      if (NULL == aggregator_proc)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Failed to start taler-exchange-aggregator. Check $PATH.\n");
        GNUNET_break (0);
        aggregator_state = NULL;
        fail (cmd);
        return;
      }
    return;
    case OPCODE_EXPECT_TRANSACTIONS_EMPTY:
      if (GNUNET_OK != TALER_FAKEBANK_check_empty (fb))
      {
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

        if (GNUNET_OK !=
            TALER_string_to_amount (cmd->details.expect_transaction.amount,
                                    &want_amount))
        {
          GNUNET_break (0);
          fail (cmd);
          return;
        }
        if (GNUNET_OK !=
            TALER_FAKEBANK_check (fb,
                                  &want_amount,
                                  cmd->details.expect_transaction.debit_account,
                                  cmd->details.expect_transaction.credit_account,
                                  cmd->details.expect_transaction.exchange_base_url,
                                  &cmd->details.expect_transaction.subject))
        {
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
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:1",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.expect_transaction.exchange_base_url = "https://exchange.taler.net/",
      .details.expect_transaction.amount = "EUR:0.89"
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
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:1",
      .details.deposit.deposit_fee = "EUR:0.1"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-2b",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:1",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.expect_transaction.exchange_base_url = "https://exchange.taler.net/",
      .details.expect_transaction.amount = "EUR:1.79"
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
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:1",
      .details.deposit.deposit_fee = "EUR:0.1"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-3b",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 5,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:1",
      .details.deposit.deposit_fee = "EUR:0.1"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-3c",
      .details.deposit.merchant_name = "alice",
      .details.deposit.merchant_account = 4,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:1",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.expect_transaction.exchange_base_url = "https://exchange.taler.net/",
      .details.expect_transaction.amount = "EUR:0.89"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTION,
      .label = "expect-deposit-3b",
      .details.expect_transaction.debit_account = 3,
      .details.expect_transaction.credit_account = 4,
      .details.expect_transaction.exchange_base_url = "https://exchange.taler.net/",
      .details.expect_transaction.amount = "EUR:0.89"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTION,
      .label = "expect-deposit-3c",
      .details.expect_transaction.debit_account = 3,
      .details.expect_transaction.credit_account = 5,
      .details.expect_transaction.exchange_base_url = "https://exchange.taler.net/",
      .details.expect_transaction.amount = "EUR:0.89"
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
      .details.deposit.wire_deadline = { 1000LL * 1000 * 5 }, /* 5s */
      .details.deposit.amount_with_fee = "EUR:0.2",
      .details.deposit.deposit_fee = "EUR:0.1"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-4b",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 5 }, /* 5s */
      .details.deposit.amount_with_fee = "EUR:0.2",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.expect_transaction.exchange_base_url = "https://exchange.taler.net/",
      .details.expect_transaction.amount = "EUR:0.19"
    },

    /* test picking all deposits at earliest deadline */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-5a",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 10 }, /* 10s */
      .details.deposit.amount_with_fee = "EUR:0.2",
      .details.deposit.deposit_fee = "EUR:0.1"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-5b",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 5 }, /* 5s */
      .details.deposit.amount_with_fee = "EUR:0.2",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.expect_transaction.exchange_base_url = "https://exchange.taler.net/",
      .details.expect_transaction.amount = "EUR:0.19"
    },

    /* Test NEVER running 'tiny' unless they make up minimum unit */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-6a",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.102",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.102",
      .details.deposit.deposit_fee = "EUR:0.1"
    },
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-6c",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.102",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.102",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.112",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.expect_transaction.exchange_base_url = "https://exchange.taler.net/",
      .details.expect_transaction.amount = "EUR:0.01"
    },

    /* Test profiteering if wire deadline is short */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-7a",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.109",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.119",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.expect_transaction.exchange_base_url = "https://exchange.taler.net/",
      .details.expect_transaction.amount = "EUR:0.01"
    },
    /* Now check profit was actually taken */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-7c",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.122",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.expect_transaction.exchange_base_url = "https://exchange.taler.net/",
      .details.expect_transaction.amount = "EUR:0.01"
    },

    /* Test that aggregation would happen fully if wire deadline is long */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-8a",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 5 }, /* 5s */
      .details.deposit.amount_with_fee = "EUR:0.109",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.deposit.wire_deadline = { 1000LL * 1000 * 5 }, /* 5s */
      .details.deposit.amount_with_fee = "EUR:0.109",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.122",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.expect_transaction.exchange_base_url = "https://exchange.taler.net/",
      .details.expect_transaction.amount = "EUR:0.03"
    },


    /* Test aggregation with fees and rounding profits */
    {
      .opcode = OPCODE_DATABASE_DEPOSIT,
      .label = "do-deposit-9a",
      .details.deposit.merchant_name = "bob",
      .details.deposit.merchant_account = 4,
      .details.deposit.wire_deadline = { 1000LL * 1000 * 5 }, /* 5s */
      .details.deposit.amount_with_fee = "EUR:0.104",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.deposit.wire_deadline = { 1000LL * 1000 * 5 }, /* 5s */
      .details.deposit.amount_with_fee = "EUR:0.105",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.deposit.wire_deadline = { 1000LL * 1000 * 0 }, /* 0s */
      .details.deposit.amount_with_fee = "EUR:0.112",
      .details.deposit.deposit_fee = "EUR:0.1"
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
      .details.expect_transaction.exchange_base_url = "https://exchange.taler.net/",
      .details.expect_transaction.amount = "EUR:0.01"
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
  if (NULL == plugin)
  {
    GNUNET_break (0);
    result = 77;
    return;
  }
  if (GNUNET_OK !=
      plugin->create_tables (plugin->cls))
  {
    GNUNET_break (0);
    TALER_EXCHANGEDB_plugin_unload (plugin);
    plugin = NULL;
    result = 77;
    return;
  }
  session = plugin->get_session (plugin->cls);
  GNUNET_assert (NULL != session);
  fake_issue (&issue);
  dpk.rsa_public_key = coin_pub;
  GNUNET_CRYPTO_rsa_public_key_hash (dpk.rsa_public_key,
				     &issue.properties.denom_hash);
  if ( (GNUNET_OK !=
        plugin->start (plugin->cls,
                       session,
                       "aggregator-test-2")) ||
       (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
        plugin->insert_denomination_info (plugin->cls,
                                          session,
                                          &dpk,
                                          &issue)) ||
       (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
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
				    &maint_child_death,
                                    NULL);
  GNUNET_SCHEDULER_add_shutdown (&shutdown_action,
                                 NULL);
  timeout_task = GNUNET_SCHEDULER_add_delayed (GNUNET_TIME_UNIT_MINUTES,
                                               &timeout_action,
                                               NULL);
  result = 1; /* test failed for undefined reason */
  fb = TALER_FAKEBANK_start (8082);
  if (NULL == fb)
  {
    GNUNET_SCHEDULER_shutdown ();
    result = 77;
    return;
  }
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
  struct GNUNET_OS_Process *proc;
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
                          "test-taler-exchange-aggregator-%s",
                          plugin_name);
  (void) GNUNET_asprintf (&config_filename,
                          "%s.conf",
                          testname);
  /* these might get in the way */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test_taler_exchange_aggregator",
                    "WARNING",
                    NULL);
  proc = GNUNET_OS_start_process (GNUNET_NO,
                                  GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-exchange-keyup",
                                  "taler-exchange-keyup",
                                  "-c", config_filename,
                                  NULL);
  if (NULL == proc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		"Failed to run `taler-exchange-keyup`, is your PATH correct?\n");
    return 77;
  }
  GNUNET_OS_process_wait (proc);
  GNUNET_OS_process_destroy (proc);
  if (GNUNET_OK !=
      GNUNET_NETWORK_test_port_free (IPPROTO_TCP,
				     8082))
  {
    fprintf (stderr,
             "Required port %u not available, skipping.\n",
	     8082);
    return 77;
  }
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
  sigpipe = GNUNET_DISK_pipe (GNUNET_NO, GNUNET_NO,
                              GNUNET_NO, GNUNET_NO);
  GNUNET_assert (NULL != sigpipe);
  shc_chld =
    GNUNET_SIGNAL_handler_install (GNUNET_SIGCHLD,
                                   &sighandler_child_death);
  coin_pk = GNUNET_CRYPTO_rsa_private_key_create (1024);
  coin_pub = GNUNET_CRYPTO_rsa_private_key_get_public (coin_pk);
  GNUNET_SCHEDULER_run (&run,
                        cfg);
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
