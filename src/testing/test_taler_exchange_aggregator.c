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
 * @file testing/test_taler_exchange_aggregator.c
 * @brief Tests for taler-exchange-aggregator logic
 * @author Christian Grothoff <christian@grothoff.org>
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_util.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler_json_lib.h"
#include "taler_exchangedb_lib.h"
#include <microhttpd.h>
#include "taler_fakebank_lib.h"
#include "taler_testing_lib.h"


/**
 * Our credentials.
 */
struct TALER_TESTING_Credentials cred;

/**
 * Name of the configuration file to use.
 */
static char *config_filename;

#define USER42_ACCOUNT "42"


/**
 * Execute the taler-exchange-aggregator, closer and transfer commands with
 * our configuration file.
 *
 * @param label label to use for the command.
 * @param cfg_fn configuration file to use
 */
#define CMD_EXEC_AGGREGATOR(label, cfg_fn)                                 \
  TALER_TESTING_cmd_exec_aggregator (label "-aggregator", cfg_fn), \
  TALER_TESTING_cmd_exec_transfer (label "-transfer", cfg_fn)


/**
 * Collects all the tests.
 */
static void
run (void *cls,
     struct TALER_TESTING_Interpreter *is)
{
  struct TALER_TESTING_Command all[] = {
    TALER_TESTING_cmd_run_fakebank ("run-fakebank",
                                    cred.cfg,
                                    "exchange-account-1"),
    TALER_TESTING_cmd_system_start ("start-taler",
                                    config_filename,
                                    "-e",
                                    NULL),
    CMD_EXEC_AGGREGATOR ("run-aggregator-on-empty-db",
                         config_filename),
    TALER_TESTING_cmd_check_bank_empty ("expect-empty-transactions-on-start"),

    /* check aggregation happens on the simplest case:
       one deposit into the database. */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-1",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:1",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-on-deposit-1",
                         config_filename),

    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-1",
                                           cred.exchange_url,
                                           "EUR:0.89",
                                           cred.exchange_payto,
                                           cred.user42_payto),
    TALER_TESTING_cmd_check_bank_empty ("expect-empty-transactions-after-1"),

    /* check aggregation accumulates well. */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-2a",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:1",
                                      "EUR:0.1"),

    TALER_TESTING_cmd_insert_deposit ("do-deposit-2b",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:1",
                                      "EUR:0.1"),

    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-2",
                         config_filename),

    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-2",
                                           cred.exchange_url,
                                           "EUR:1.79",
                                           cred.exchange_payto,
                                           cred.user42_payto),
    TALER_TESTING_cmd_check_bank_empty ("expect-empty-transactions-after-2"),

    /* check that different merchants stem different aggregations. */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-3a",
                                      cred.cfg,
                                      "bob",
                                      "4",
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:1",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-3b",
                                      cred.cfg,
                                      "bob",
                                      "5",
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:1",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-3c",
                                      cred.cfg,
                                      "alice",
                                      "4",
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:1",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-3",
                         config_filename),

    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-3a",
                                           cred.exchange_url,
                                           "EUR:0.89",
                                           cred.exchange_payto,
                                           "payto://x-taler-bank/localhost/4?receiver-name=4"),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-3b",
                                           cred.exchange_url,
                                           "EUR:0.89",
                                           cred.exchange_payto,
                                           "payto://x-taler-bank/localhost/4?receiver-name=4"),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-3c",
                                           cred.exchange_url,
                                           "EUR:0.89",
                                           cred.exchange_payto,
                                           "payto://x-taler-bank/localhost/5?receiver-name=5"),
    TALER_TESTING_cmd_check_bank_empty ("expect-empty-transactions-after-3"),

    /* checking that aggregator waits for the deadline. */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-4a",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_relative_multiply
                                        (GNUNET_TIME_UNIT_SECONDS,
                                        5),
                                      "EUR:0.2",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-4b",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_relative_multiply
                                        (GNUNET_TIME_UNIT_SECONDS,
                                        5),
                                      "EUR:0.2",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-4-early",
                         config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-4-fast"),

    TALER_TESTING_cmd_sleep ("wait (5s)", 5),

    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-4-delayed",
                         config_filename),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-4",
                                           cred.exchange_url,
                                           "EUR:0.19",
                                           cred.exchange_payto,
                                           cred.user42_payto),

    // test picking all deposits at earliest deadline
    TALER_TESTING_cmd_insert_deposit ("do-deposit-5a",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_relative_multiply
                                        (GNUNET_TIME_UNIT_SECONDS,
                                        10),
                                      "EUR:0.2",
                                      "EUR:0.1"),

    TALER_TESTING_cmd_insert_deposit ("do-deposit-5b",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_relative_multiply
                                        (GNUNET_TIME_UNIT_SECONDS,
                                        5),
                                      "EUR:0.2",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-5-early",
                         config_filename),

    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-5-early"),
    TALER_TESTING_cmd_sleep ("wait (5s)", 5),

    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-5-delayed",
                         config_filename),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-5",
                                           cred.exchange_url,
                                           "EUR:0.19",
                                           cred.exchange_payto,
                                           cred.user42_payto),
    /* Test NEVER running 'tiny' unless they make up minimum unit */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-6a",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.102",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-6a-tiny",
                         config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-6a-tiny"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-6b",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.102",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-6c",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.102",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-6c-tiny",
                         config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-6c-tiny"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-6d",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.102",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-6d-tiny",
                         config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-6d-tiny"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-6e",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.112",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-6e",
                         config_filename),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-6",
                                           cred.exchange_url,
                                           "EUR:0.01",
                                           cred.exchange_payto,
                                           cred.user42_payto),

    /* Test profiteering if wire deadline is short */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-7a",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.109",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-7a-tiny",
                         config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-7a-tiny"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-7b",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.119",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-7-profit",
                         config_filename),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-7",
                                           cred.exchange_url,
                                           "EUR:0.01",
                                           cred.exchange_payto,
                                           cred.user42_payto),

    /* Now check profit was actually taken */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-7c",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.122",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-7-loss",
                         config_filename),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-7",
                                           cred.exchange_url,
                                           "EUR:0.01",
                                           cred.exchange_payto,
                                           cred.user42_payto),

    /* Test that aggregation would happen fully if wire deadline is long */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-8a",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_relative_multiply
                                        (GNUNET_TIME_UNIT_SECONDS,
                                        5),
                                      "EUR:0.109",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-8a-tiny",
                         config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-8a-tiny"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-8b",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_relative_multiply
                                        (GNUNET_TIME_UNIT_SECONDS,
                                        5),
                                      "EUR:0.109",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-8b-tiny",
                         config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-8b-tiny"),

    /* now trigger aggregate with large transaction and short deadline */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-8c",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.122",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-8",
                         config_filename),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-8",
                                           cred.exchange_url,
                                           "EUR:0.03",
                                           cred.exchange_payto,
                                           cred.user42_payto),

    /* Test aggregation with fees and rounding profits. */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-9a",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_relative_multiply
                                        (GNUNET_TIME_UNIT_SECONDS,
                                        5),
                                      "EUR:0.104",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-9a-tiny",
                         config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-9a-tiny"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-9b",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_relative_multiply
                                        (GNUNET_TIME_UNIT_SECONDS,
                                        5),
                                      "EUR:0.105",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-9b-tiny",
                         config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-9b-tiny"),

    /* now trigger aggregate with large transaction and short deadline */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-9c",
                                      cred.cfg,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_timestamp_get (),
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.112",
                                      "EUR:0.1"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-deposit-9",
                         config_filename),
    /* 0.009 + 0.009 + 0.022 - 0.001 - 0.002 - 0.008 = 0.029 => 0.02 */
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-9",
                                           cred.exchange_url,
                                           "EUR:0.01",
                                           cred.exchange_payto,
                                           cred.user42_payto),
    TALER_TESTING_cmd_end ()
  };

  TALER_TESTING_run (is,
                     all);
}


int
main (int argc,
      char *const argv[])
{
  const char *plugin_name;

  if (NULL == (plugin_name = strrchr (argv[0], (int) '-')))
  {
    GNUNET_break (0);
    return -1;
  }
  plugin_name++;
  (void) GNUNET_asprintf (&config_filename,
                          "test-taler-exchange-aggregator-%s.conf",
                          plugin_name);
  return TALER_TESTING_main (argv,
                             "INFO",
                             config_filename,
                             "exchange-account-1",
                             TALER_TESTING_BS_FAKEBANK,
                             &cred,
                             &run,
                             NULL);
}


/* end of test_taler_exchange_aggregator.c */
