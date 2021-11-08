/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3, or
  (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/test_kyc_api.c
 * @brief testcase to test the KYC processes
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler_bank_service.h"
#include "taler_fakebank_lib.h"
#include "taler_testing_lib.h"


/**
 * Configuration file we use.  One (big) configuration is used
 * for the various components for this test.
 */
#define CONFIG_FILE "test_kyc_api.conf"

/**
 * Exchange configuration data.
 */
static struct TALER_TESTING_ExchangeConfiguration ec;

/**
 * Bank configuration data.
 */
static struct TALER_TESTING_BankConfiguration bc;

/**
 * Execute the taler-exchange-wirewatch command with
 * our configuration file.
 *
 * @param label label to use for the command.
 */
#define CMD_EXEC_WIREWATCH(label) \
  TALER_TESTING_cmd_exec_wirewatch (label, CONFIG_FILE)

/**
 * Execute the taler-exchange-aggregator, closer and transfer commands with
 * our configuration file.
 *
 * @param label label to use for the command.
 */
#define CMD_EXEC_AGGREGATOR(label)                        \
  TALER_TESTING_cmd_exec_aggregator /*_with_kyc*/ (label, CONFIG_FILE), \
  TALER_TESTING_cmd_exec_transfer (label, CONFIG_FILE)

/**
 * Run wire transfer of funds from some user's account to the
 * exchange.
 *
 * @param label label to use for the command.
 * @param amount amount to transfer, i.e. "EUR:1"
 */
#define CMD_TRANSFER_TO_EXCHANGE(label,amount) \
  TALER_TESTING_cmd_admin_add_incoming (label, amount,           \
                                        &bc.exchange_auth,       \
                                        bc.user42_payto)

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
  /**
   * Test withdraw.
   */
  struct TALER_TESTING_Command withdraw[] = {
    CMD_TRANSFER_TO_EXCHANGE ("create-reserve-1",
                              "EUR:5.01"),
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "check-create-reserve-1",
      "EUR:5.01", bc.user42_payto, bc.exchange_payto,
      "create-reserve-1"),
    CMD_EXEC_WIREWATCH ("wirewatch-1"),
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-1",
                                       "create-reserve-1",
                                       "EUR:5",
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };
  struct TALER_TESTING_Command spend[] = {
    TALER_TESTING_cmd_deposit (
      "deposit-simple",
      "withdraw-coin-1",
      0,
      bc.user42_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:5",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command track[] = {
    CMD_EXEC_AGGREGATOR ("run-aggregator"),
    TALER_TESTING_cmd_check_bank_transfer (
      "check_bank_transfer-499c",
      ec.exchange_url,
      "EUR:4.98",
      bc.exchange_payto,
      bc.user42_payto),
    TALER_TESTING_cmd_check_bank_empty ("check_bank_empty"),
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command commands[] = {
    TALER_TESTING_cmd_exec_offline_sign_fees ("offline-sign-fees",
                                              CONFIG_FILE,
                                              "EUR:0.01",
                                              "EUR:0.01"),
    TALER_TESTING_cmd_auditor_add ("add-auditor-OK",
                                   MHD_HTTP_NO_CONTENT,
                                   false),
    TALER_TESTING_cmd_wire_add ("add-wire-account",
                                "payto://x-taler-bank/localhost/2",
                                MHD_HTTP_NO_CONTENT,
                                false),
    TALER_TESTING_cmd_exec_offline_sign_keys ("offline-sign-future-keys",
                                              CONFIG_FILE),
    TALER_TESTING_cmd_check_keys_pull_all_keys ("refetch /keys",
                                                2),
    TALER_TESTING_cmd_exchanges_with_url ("check-exchange",
                                          MHD_HTTP_OK,
                                          "http://localhost:8081/"),
    TALER_TESTING_cmd_batch ("withdraw",
                             withdraw),
    TALER_TESTING_cmd_batch ("spend",
                             spend),
    TALER_TESTING_cmd_batch ("track",
                             track),
    TALER_TESTING_cmd_end ()
  };

  TALER_TESTING_run_with_fakebank (is,
                                   commands,
                                   bc.exchange_auth.wire_gateway_url);
}


int
main (int argc,
      char *const *argv)
{
  /* These environment variables get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-kyc-api",
                    "INFO",
                    NULL);
  /* Check fakebank port is available and get configuration data. */
  if (GNUNET_OK !=
      TALER_TESTING_prepare_fakebank (CONFIG_FILE,
                                      "exchange-account-2",
                                      &bc))
    return 77;
  TALER_TESTING_cleanup_files (CONFIG_FILE);
  /* @helpers.  Run keyup, create tables, ... Note: it
   * fetches the port number from config in order to see
   * if it's available. */
  switch (TALER_TESTING_prepare_exchange (CONFIG_FILE,
                                          GNUNET_YES,
                                          &ec))
  {
  case GNUNET_SYSERR:
    GNUNET_break (0);
    return 1;
  case GNUNET_NO:
    return 77;
  case GNUNET_OK:
    if (GNUNET_OK !=
        /* Set up event loop and reschedule context, plus
         * start/stop the exchange.  It calls TALER_TESTING_setup
         * which creates the 'is' object.
         */
        TALER_TESTING_setup_with_exchange (&run,
                                           NULL,
                                           CONFIG_FILE))
      return 1;
    break;
  default:
    GNUNET_break (0);
    return 1;
  }
  return 0;
}


/* end of test_kyc_api.c */
