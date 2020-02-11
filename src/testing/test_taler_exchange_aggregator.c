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
 * Helper structure to keep exchange configuration values.
 */
static struct TALER_TESTING_ExchangeConfiguration ec;

/**
 * Bank configuration data.
 */
static struct TALER_TESTING_BankConfiguration bc;

/**
 * Contains plugin and session.
 */
static struct TALER_TESTING_DatabaseConnection dbc;

/**
 * Return value from main().
 */
static int result;

/**
 * Name of the configuration file to use.
 */
static char *config_filename;

#define USER42_ACCOUNT "42"


/**
 * Collects all the tests.
 */
static void
run (void *cls,
     struct TALER_TESTING_Interpreter *is)
{
  struct TALER_TESTING_Command all[] = {

    // check no aggregation happens on a empty database
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-on-empty-db",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_empty ("expect-empty-transactions-on-start"),

    /* check aggregation happens on the simplest case:
       one deposit into the database. */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-1",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:1",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-on-deposit-1",
                                       config_filename),

    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-1",
                                           ec.exchange_url,
                                           "EUR:0.89",
                                           bc.exchange_payto,
                                           bc.user42_payto),
    TALER_TESTING_cmd_check_bank_empty ("expect-empty-transactions-after-1"),

    /* check aggregation accumulates well. */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-2a",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:1",
                                      "EUR:0.1"),

    TALER_TESTING_cmd_insert_deposit ("do-deposit-2b",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:1",
                                      "EUR:0.1"),

    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-2",
                                       config_filename),

    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-2",
                                           ec.exchange_url,
                                           "EUR:1.79",
                                           bc.exchange_payto,
                                           bc.user42_payto),
    TALER_TESTING_cmd_check_bank_empty ("expect-empty-transactions-after-2"),

    /* check that different merchants stem different aggregations. */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-3a",
                                      &dbc,
                                      "bob",
                                      "4",
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:1",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-3b",
                                      &dbc,
                                      "bob",
                                      "5",
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:1",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-3c",
                                      &dbc,
                                      "alice",
                                      "4",
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:1",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-3",
                                       config_filename),

    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-3a",
                                           ec.exchange_url,
                                           "EUR:0.89",
                                           bc.exchange_payto,
                                           "payto://x-taler-bank/localhost/4"),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-3b",
                                           ec.exchange_url,
                                           "EUR:0.89",
                                           bc.exchange_payto,
                                           "payto://x-taler-bank/localhost/4"),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-3c",
                                           ec.exchange_url,
                                           "EUR:0.89",
                                           bc.exchange_payto,
                                           "payto://x-taler-bank/localhost/5"),
    TALER_TESTING_cmd_check_bank_empty ("expect-empty-transactions-after-3"),

    /* checking that aggregator waits for the deadline. */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-4a",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_relative_multiply
                                        (GNUNET_TIME_UNIT_SECONDS,
                                        5),
                                      "EUR:0.2",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-4b",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_relative_multiply
                                        (GNUNET_TIME_UNIT_SECONDS,
                                        5),
                                      "EUR:0.2",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-4-early",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-4-fast"),

    TALER_TESTING_cmd_sleep ("wait (5s)", 5),

    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-4-delayed",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-4",
                                           ec.exchange_url,
                                           "EUR:0.19",
                                           bc.exchange_payto,
                                           bc.user42_payto),

    // test picking all deposits at earliest deadline
    TALER_TESTING_cmd_insert_deposit ("do-deposit-5a",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_relative_multiply
                                        (GNUNET_TIME_UNIT_SECONDS,
                                        10),
                                      "EUR:0.2",
                                      "EUR:0.1"),

    TALER_TESTING_cmd_insert_deposit ("do-deposit-5b",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_relative_multiply
                                        (GNUNET_TIME_UNIT_SECONDS,
                                        5),
                                      "EUR:0.2",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-5-early",
                                       config_filename),

    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-5-early"),
    TALER_TESTING_cmd_sleep ("wait (5s)", 5),

    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-5-delayed",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-5",
                                           ec.exchange_url,
                                           "EUR:0.19",
                                           bc.exchange_payto,
                                           bc.user42_payto),
    /* Test NEVER running 'tiny' unless they make up minimum unit */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-6a",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.102",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-6a-tiny",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-6a-tiny"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-6b",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.102",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-6c",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.102",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-6c-tiny",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-6c-tiny"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-6d",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.102",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-6d-tiny",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-6d-tiny"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-6e",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.112",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-6e",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-6",
                                           ec.exchange_url,
                                           "EUR:0.01",
                                           bc.exchange_payto,
                                           bc.user42_payto),

    /* Test profiteering if wire deadline is short */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-7a",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.109",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-7a-tiny",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-7a-tiny"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-7b",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.119",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-7-profit",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-7",
                                           ec.exchange_url,
                                           "EUR:0.01",
                                           bc.exchange_payto,
                                           bc.user42_payto),

    /* Now check profit was actually taken */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-7c",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.122",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-7-loss",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-7",
                                           ec.exchange_url,
                                           "EUR:0.01",
                                           bc.exchange_payto,
                                           bc.user42_payto),

    /* Test that aggregation would happen fully if wire deadline is long */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-8a",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_relative_multiply
                                        (GNUNET_TIME_UNIT_SECONDS,
                                        5),
                                      "EUR:0.109",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-8a-tiny",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-8a-tiny"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-8b",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_relative_multiply
                                        (GNUNET_TIME_UNIT_SECONDS,
                                        5),
                                      "EUR:0.109",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-8b-tiny",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-8b-tiny"),

    /* now trigger aggregate with large transaction and short deadline */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-8c",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.122",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-8",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-8",
                                           ec.exchange_url,
                                           "EUR:0.03",
                                           bc.exchange_payto,
                                           bc.user42_payto),

    /* Test aggregation with fees and rounding profits. */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-9a",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_relative_multiply
                                        (GNUNET_TIME_UNIT_SECONDS,
                                        5),
                                      "EUR:0.104",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-9a-tiny",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-9a-tiny"),
    TALER_TESTING_cmd_insert_deposit ("do-deposit-9b",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_relative_multiply
                                        (GNUNET_TIME_UNIT_SECONDS,
                                        5),
                                      "EUR:0.105",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-9b-tiny",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_empty (
      "expect-empty-transactions-after-9b-tiny"),

    /* now trigger aggregate with large transaction and short deadline */
    TALER_TESTING_cmd_insert_deposit ("do-deposit-9c",
                                      &dbc,
                                      "bob",
                                      USER42_ACCOUNT,
                                      GNUNET_TIME_UNIT_ZERO,
                                      "EUR:0.112",
                                      "EUR:0.1"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-deposit-9",
                                       config_filename),
    /* 0.009 + 0.009 + 0.022 - 0.001 - 0.002 - 0.008 = 0.029 => 0.02 */
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-9",
                                           ec.exchange_url,
                                           "EUR:0.01",
                                           bc.exchange_payto,
                                           bc.user42_payto),
    TALER_TESTING_cmd_end ()
  };

  TALER_TESTING_run_with_fakebank (is,
                                   all,
                                   bc.exchange_auth.wire_gateway_url);
}


/**
 * Prepare database an launch the test.
 *
 * @param cls unused
 * @param cfg our configuration
 * @return #GNUNET_NO if database could not be prepared,
 * otherwise #GNUNET_OK
 */
static int
prepare_database (void *cls,
                  const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  dbc.plugin = TALER_EXCHANGEDB_plugin_load (cfg);
  if (NULL == dbc.plugin)
  {
    GNUNET_break (0);
    result = 77;
    return GNUNET_NO;
  }
  if (GNUNET_OK !=
      dbc.plugin->create_tables (dbc.plugin->cls))
  {
    GNUNET_break (0);
    TALER_EXCHANGEDB_plugin_unload (dbc.plugin);
    dbc.plugin = NULL;
    result = 77;
    return GNUNET_NO;
  }
  dbc.session = dbc.plugin->get_session (dbc.plugin->cls);
  GNUNET_assert (NULL != dbc.session);

  result = TALER_TESTING_setup (&run,
                                NULL,
                                cfg,
                                NULL, // no exchange process handle.
                                GNUNET_NO); // do not try to connect to the exchange


  return GNUNET_OK;
}


int
main (int argc,
      char *const argv[])
{
  const char *plugin_name;
  char *testname;

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

  /* these might get in the way */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");

  TALER_TESTING_cleanup_files (config_filename);

  if (GNUNET_OK != TALER_TESTING_prepare_exchange (config_filename,
                                                   &ec))
  {
    TALER_LOG_WARNING ("Could not prepare the exchange.\n");
    return 77;
  }

  if (GNUNET_OK != TALER_TESTING_prepare_fakebank (config_filename,
                                                   "exchange-account-1",
                                                   &bc))
  {
    TALER_LOG_WARNING ("Could not prepare the fakebank\n");
    return 77;
  }

  if (GNUNET_OK != GNUNET_CONFIGURATION_parse_and_run (config_filename,
                                                       &prepare_database,
                                                       NULL))
  {
    TALER_LOG_WARNING ("Could not prepare database for tests.\n");
    return result;
  }

  GNUNET_free (config_filename);
  GNUNET_free (testname);
  dbc.plugin->drop_tables (dbc.plugin->cls);
  TALER_EXCHANGEDB_plugin_unload (dbc.plugin);
  return GNUNET_OK == result ? 0 : 1;
}


/* end of test_taler_exchange_aggregator.c */
