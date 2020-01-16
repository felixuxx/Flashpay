/*
  This file is part of TALER
  (C) 2016-2020 Taler Systems SA

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
#include "taler_testing_lib.h"


/**
 * Helper structure to keep exchange configuration values.
 */
static struct TALER_TESTING_ExchangeConfiguration ec;

/**
 * Bank configuration data.
 */
static struct TALER_TESTING_BankConfiguration bc;

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
 * Private key we use for fake coins.
 */
static struct GNUNET_CRYPTO_RsaPrivateKey *coin_pk;

/**
 * Public key we use for fake coins.
 */
static struct GNUNET_CRYPTO_RsaPublicKey *coin_pub;

/**
 * Setup (fake) information about a coin used in deposit.
 *
 * @param[out] issue information to initialize with "valid" data
 */
static void
fake_issue (struct TALER_EXCHANGEDB_DenominationKeyInformationP *issue)
{
  memset (issue, 0, sizeof (struct
                            TALER_EXCHANGEDB_DenominationKeyInformationP));
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

  GNUNET_CRYPTO_rsa_public_key_hash (coin_pub,
                                     &coin->denom_pub_hash);
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
                     (unsigned long
                      long) cmd->details.deposit.merchant_account);
    deposit.receiver_wire_account
      = json_pack ("{s:s, s:s}",
                   "salt", "this-is-a-salt-value",
                   "url", str);
    GNUNET_free (str);
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_merchant_wire_signature_hash (
                   deposit.receiver_wire_account,
                   &deposit.h_wire));
  deposit.timestamp = GNUNET_TIME_absolute_get ();
  GNUNET_TIME_round_abs (&deposit.timestamp);
  deposit.wire_deadline = GNUNET_TIME_relative_to_absolute (
    cmd->details.deposit.wire_deadline);
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
 * Interprets the commands from the test program.
 *
 * @param cls the `struct State` of the interpreter
 */
#if 0
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
            TALER_FAKEBANK_check_debit (fb,
                                        &want_amount,
                                        cmd->details.expect_transaction.
                                        debit_account,
                                        cmd->details.expect_transaction.
                                        credit_account,
                                        cmd->details.expect_transaction.
                                        exchange_base_url,
                                        &cmd->details.expect_transaction.wtid))
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
#endif

/**
 * Contains the test program. Here each step of the testcase
 * is defined.
 */
#if 0
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
      .details.expect_transaction.exchange_base_url =
        "https://exchange.taler.net/",
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
      .details.expect_transaction.exchange_base_url =
        "https://exchange.taler.net/",
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
      .details.expect_transaction.exchange_base_url =
        "https://exchange.taler.net/",
      .details.expect_transaction.amount = "EUR:0.89"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTION,
      .label = "expect-deposit-3b",
      .details.expect_transaction.debit_account = 3,
      .details.expect_transaction.credit_account = 4,
      .details.expect_transaction.exchange_base_url =
        "https://exchange.taler.net/",
      .details.expect_transaction.amount = "EUR:0.89"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSACTION,
      .label = "expect-deposit-3c",
      .details.expect_transaction.debit_account = 3,
      .details.expect_transaction.credit_account = 5,
      .details.expect_transaction.exchange_base_url =
        "https://exchange.taler.net/",
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
      .details.expect_transaction.exchange_base_url =
        "https://exchange.taler.net/",
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
      .details.expect_transaction.exchange_base_url =
        "https://exchange.taler.net/",
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
      .details.expect_transaction.exchange_base_url =
        "https://exchange.taler.net/",
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
      .details.expect_transaction.exchange_base_url =
        "https://exchange.taler.net/",
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
      .details.expect_transaction.exchange_base_url =
        "https://exchange.taler.net/",
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
      .details.expect_transaction.exchange_base_url =
        "https://exchange.taler.net/",
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
      .details.expect_transaction.exchange_base_url =
        "https://exchange.taler.net/",
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
#endif

/**
 * @return GNUNET_NO if database could not be prepared,
 * otherwise GNUNET_OK
 */
static int
prepare_database (const struct GNUNET_CONFIGURATION_Handle *cfg)
{

  // connect to the database.
  plugin = TALER_EXCHANGEDB_plugin_load (cfg);
  if (NULL == plugin)
  {
    GNUNET_break (0);
    result = 77;
    return GNUNET_NO;
  }

  if (GNUNET_OK !=
      plugin->create_tables (plugin->cls))
  {
    GNUNET_break (0);
    TALER_EXCHANGEDB_plugin_unload (plugin);
    plugin = NULL;
    result = 77;
    return GNUNET_NO;
  }

  session = plugin->get_session (plugin->cls);
  GNUNET_assert (NULL != session);

  return GNUNET_OK;
}


static void
run (void *cls,
     struct TALER_TESTING_Interpreter *is)
{
  if (GNUNET_OK != prepare_database (is->cfg))
    return;

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


  /* these might get in the way */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");

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

  GNUNET_log_setup ("test_taler_exchange_aggregator",
                    "DEBUG",
                    NULL);



  TALER_TESTING_cleanup_files (config_filename);
  if (GNUNET_OK != TALER_TESTING_prepare_exchange (config_filename,
			                           &ec))
  {
    TALER_LOG_WARNING ("Could not prepare the exchange (keyup, ..)\n");
    return 77;
  }

  if (GNUNET_OK != TALER_TESTING_prepare_fakebank (config_filename,
			                           "account-1",
			                           &bc))
  {
    TALER_LOG_WARNING ("Could not prepare the fakebank\n");
    return 77;
  }

  coin_pk = GNUNET_CRYPTO_rsa_private_key_create (1024);
  coin_pub = GNUNET_CRYPTO_rsa_private_key_get_public (coin_pk);


  result = TALER_TESTING_setup (&run,
	                        NULL,
		                config_filename,
		                NULL, // no exchange process handle.
		                GNUNET_NO); // do not try to connect to the exchange

  GNUNET_CRYPTO_rsa_private_key_free (coin_pk);
  GNUNET_CRYPTO_rsa_public_key_free (coin_pub);
  GNUNET_free (config_filename);
  GNUNET_free (testname);
  return GNUNET_OK == result ? 0 : 1;
}


/* end of test_taler_exchange_aggregator.c */
