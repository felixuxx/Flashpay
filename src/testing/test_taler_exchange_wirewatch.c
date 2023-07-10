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
 * @file testing/test_taler_exchange_wirewatch.c
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
 * Our credentials.
 */
static struct TALER_TESTING_Credentials cred;

/**
 * Name of the configuration file to use.
 */
static char *config_filename;


/**
 * Execute the taler-exchange-aggregator, closer and transfer commands with
 * our configuration file.
 *
 * @param label label to use for the command.
 */
#define CMD_EXEC_AGGREGATOR(label) \
  TALER_TESTING_cmd_exec_aggregator (label "-aggregator", config_filename), \
  TALER_TESTING_cmd_exec_transfer (label "-transfer", config_filename)


static struct TALER_TESTING_Command
transfer_to_exchange (const char *label,
                      const char *amount)
{
  return TALER_TESTING_cmd_admin_add_incoming (label,
                                               amount,
                                               &cred.ba,
                                               cred.user42_payto);
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
    TALER_TESTING_cmd_run_fakebank ("run-fakebank",
                                    cred.cfg,
                                    "exchange-account-1"),
    TALER_TESTING_cmd_system_start ("start-taler",
                                    config_filename,
                                    "-e",
                                    "-u", "exchange-account-1",
                                    NULL),
    TALER_TESTING_cmd_get_exchange ("get-exchange",
                                    cred.cfg,
                                    NULL,
                                    true,
                                    true),
    TALER_TESTING_cmd_check_bank_empty ("expect-empty-transactions-on-start"),
    CMD_EXEC_AGGREGATOR ("run-aggregator-on-empty"),
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
      cred.user42_payto,                                            // debit
      cred.exchange_payto,                                            // credit
      "run-transfer-good-to-exchange"),

    TALER_TESTING_cmd_exec_closer ("run-closer-non-expired-reserve",
                                   config_filename,
                                   NULL,
                                   NULL,
                                   NULL),
    TALER_TESTING_cmd_exec_transfer ("do-idle-transfer", config_filename),

    TALER_TESTING_cmd_check_bank_empty ("expect-empty-transactions-1"),
    TALER_TESTING_cmd_sleep ("wait (5s)",
                             5),
    TALER_TESTING_cmd_exec_closer ("run-closer-expired-reserve",
                                   config_filename,
                                   "EUR:4.99",
                                   "EUR:0.01",
                                   "run-transfer-good-to-exchange"),
    TALER_TESTING_cmd_exec_transfer ("do-closing-transfer",
                                     config_filename),

    CMD_EXEC_AGGREGATOR ("run-closer-on-expired-reserve"),
    TALER_TESTING_cmd_check_bank_transfer ("expect-deposit-1",
                                           cred.exchange_url,
                                           "EUR:4.99",
                                           cred.exchange_payto,
                                           cred.user42_payto),
    TALER_TESTING_cmd_check_bank_empty ("expect-empty-transactions-2"),
    TALER_TESTING_cmd_end ()
  };

  (void) cls;
  TALER_TESTING_run (is,
                     all);
}


int
main (int argc,
      char *const argv[])
{
  (void) argc;
  {
    const char *plugin_name;

    plugin_name = strrchr (argv[0], (int) '-');
    if (NULL == plugin_name)
    {
      GNUNET_break (0);
      return -1;
    }
    plugin_name++;
    GNUNET_asprintf (&config_filename,
                     "test-taler-exchange-wirewatch-%s.conf",
                     plugin_name);
  }
  return TALER_TESTING_main (argv,
                             "INFO",
                             config_filename,
                             "exchange-account-1",
                             TALER_TESTING_BS_FAKEBANK,
                             &cred,
                             &run,
                             NULL);
}


/* end of test_taler_exchange_wirewatch.c */
