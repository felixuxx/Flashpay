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
 * @file lib/test_taler_exchange_wirewatch.c
 * @brief Tests for taler-exchange-wirewatch and taler-exchange-aggregator logic;
 *        Performs an invalid wire transfer to the exchange, and then checks that
 *        wirewatch immediately sends the money back.
 *        Then performs a valid wire transfer, waits for the reserve to expire,
 *        and then checks that the aggregator sends the money back.
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_pq_lib.h>
#include "taler_json_lib.h"
#include <microhttpd.h>
#include "taler_fakebank_lib.h"
#include "taler_testing_lib.h"


/**
 * Bank configuration data.
 */
static struct TALER_TESTING_BankConfiguration bc;

/**
 * Helper structure to keep exchange configuration values.
 */
static struct TALER_TESTING_ExchangeConfiguration ec;

/**
 * Name of the configuration file to use.
 */
static char *config_filename;

static struct TALER_TESTING_Command
transfer_to_exchange (const char *label,
                      const char *amount)
{
  return TALER_TESTING_cmd_admin_add_incoming (label,
                                               amount,
                                               bc.exchange_account_url,
                                               &bc.exchange_auth,
                                               bc.user42_payto);
}


/**
 * Main function that will tell the interpreter what commands to
 * run.
 *
 * @param cls closure
 */
static void
run (void *cls,
     struct TALER_TESTING_Interpreter *is)
{
  struct TALER_TESTING_Command all[] = {
    TALER_TESTING_cmd_check_bank_empty ("expect-empty-transactions-on-start"),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-on-empty",
                                       config_filename),
    TALER_TESTING_cmd_exec_wirewatch ("run-wirewatch-on-empty",
                                      config_filename),
    TALER_TESTING_cmd_check_bank_empty ("expect-transfers-empty-after-dry-run"),

    transfer_to_exchange ("run-transfer-good-to-exchange",
                          "EUR:5"),
    TALER_TESTING_cmd_exec_wirewatch ("run-wirewatch-on-good-transfer",
                                      config_filename),

    TALER_TESTING_cmd_check_bank_admin_transfer (
      "clear-good-transfer-to-the-exchange",
      "EUR:5",
      bc.user42_payto,                                            // debit
      bc.exchange_payto,                                            // credit
      "run-transfer-good-to-exchange"),

    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-non-expired-reserve",
                                       config_filename),

    TALER_TESTING_cmd_check_bank_empty ("expect-empty-transactions-1"),
    TALER_TESTING_cmd_sleep ("wait (5s)",
                             5),
    TALER_TESTING_cmd_exec_aggregator ("run-aggregator-on-expired-reserve",
                                       config_filename),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-1",
                                           ec.exchange_url,
                                           "EUR:4.99",
                                           bc.exchange_payto,
                                           bc.user42_payto),
    TALER_TESTING_cmd_check_bank_empty ("expect-empty-transactions-2"),
    TALER_TESTING_cmd_end ()
  };

  TALER_TESTING_run_with_fakebank (is,
                                   all,
                                   bc.bank_url);
}


int
main (int argc,
      char *const argv[])
{
  const char *plugin_name;
  char *testname;

  /* these might get in the way */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test_taler_exchange_wirewatch",
                    "DEBUG",
                    NULL);

  if (NULL == (plugin_name = strrchr (argv[0], (int) '-')))
  {
    GNUNET_break (0);
    return -1;
  }
  plugin_name++;
  (void) GNUNET_asprintf (&testname,
                          "test-taler-exchange-wirewatch-%s",
                          plugin_name);
  (void) GNUNET_asprintf (&config_filename,
                          "%s.conf",
                          testname);

  /* check database is working */
  {
    struct GNUNET_PQ_Context *conn;
    struct GNUNET_PQ_ExecuteStatement es[] = {
      GNUNET_PQ_EXECUTE_STATEMENT_END
    };

    conn = GNUNET_PQ_connect ("postgres:///talercheck",
                              NULL,
                              es,
                              NULL);
    if (NULL == conn)
      return 77;
    GNUNET_PQ_disconnect (conn);
  }

  TALER_TESTING_cleanup_files (config_filename);
  if (GNUNET_OK != TALER_TESTING_prepare_exchange (config_filename,
                                                   &ec))
  {
    TALER_LOG_INFO ("Could not prepare the exchange\n");
    return 77;
  }

  if (GNUNET_OK !=
      TALER_TESTING_prepare_fakebank (config_filename,
                                      "account-1",
                                      &bc))
    return 77;

  return
    (GNUNET_OK == TALER_TESTING_setup_with_exchange (&run,
                                                     NULL,
                                                     config_filename)) ? 0 : 1;
}


/* end of test_taler_exchange_wirewatch.c */
