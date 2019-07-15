/*
  This file is part of TALER
  Copyright (C) 2014--2019 Taler Systems SA

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
 * @file exchange/test_exchange_api_revocation.c
 * @brief testcase to test exchange's HTTP API interface involving payback
 *        of refreshed coin after revocation of a denomination
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 * @author Marcello Stanisci
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
#define CONFIG_FILE "test_exchange_api.conf"

/**
 * URL of the fakebank.  Obtained from CONFIG_FILE's
 * "exchange-wire-test:BANK_URI" option.
 */
static char *fakebank_url;

/**
 * Exchange base URL as it appears in the configuration.  Note
 * that it might differ from the one where the exchange actually
 * listens from.
 */
static char *exchange_url;

/**
 * Auditor base URL as it appears in the configuration.  Note
 * that it might differ from the one where the auditor actually
 * listens from.
 */
static char *auditor_url;

/**
 * Account number of the exchange at the bank.
 */
#define EXCHANGE_ACCOUNT_NO 2

/**
 * Account number of some user.
 */
#define USER_ACCOUNT_NO 42

/**
 * User name. Never checked by fakebank.
 */
#define USER_LOGIN_NAME "user42"

/**
 * User password. Never checked by fakebank.
 */
#define USER_LOGIN_PASS "pass42"

/**
 * Execute the taler-exchange-wirewatch command with
 * our configuration file.
 *
 * @param label label to use for the command.
 */
#define CMD_EXEC_WIREWATCH(label) \
   TALER_TESTING_cmd_exec_wirewatch (label, CONFIG_FILE)

/**
 * Run wire transfer of funds from some user's account to the
 * exchange.
 *
 * @param label label to use for the command.
 * @param amount amount to transfer, i.e. "EUR:1"
 */
#define CMD_TRANSFER_TO_EXCHANGE(label,amount) \
   TALER_TESTING_cmd_fakebank_transfer (label, amount, \
     fakebank_url, USER_ACCOUNT_NO, EXCHANGE_ACCOUNT_NO, \
     USER_LOGIN_NAME, USER_LOGIN_PASS, exchange_url)

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
  struct TALER_TESTING_Command commands[] = {
    /**
     * Fill reserve with EUR:5.01, as withdraw fee is 1 ct per
     * config.
     */
    CMD_TRANSFER_TO_EXCHANGE ("create-reserve-1",
                              "EUR:5.01"),
    /**
     * Run wire-watch to trigger the reserve creation.
     */
    CMD_EXEC_WIREWATCH ("wirewatch-4"),
    /* Withdraw a 5 EUR coin, at fee of 1 ct */
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-1",
                                       "create-reserve-1",
                                       "EUR:5",
                                       MHD_HTTP_OK),
    /**
     * Try to partially spend (deposit) 1 EUR of the 5 EUR coin
     * (in full) (merchant would receive EUR:0.99 due to 1 ct
     * deposit fee)
     */
    TALER_TESTING_cmd_deposit
      ("deposit-partial",
       "withdraw-coin-1", 0,
       TALER_TESTING_make_wire_details (42,
                                        fakebank_url),
       "{\"items\":[{\"name\":\"ice cream\",\
                     \"value\":\"EUR:1\"}]}",
       GNUNET_TIME_UNIT_ZERO, "EUR:1", MHD_HTTP_OK),
    /**
     * Melt the rest of the coin's value
     * (EUR:4.00 = 3x EUR:1.03 + 7x EUR:0.13) */
    TALER_TESTING_cmd_refresh_melt_double
      ("refresh-melt-1", "EUR:4",
       "withdraw-coin-1", MHD_HTTP_OK),
    /**
     * Complete (successful) melt operation, and withdraw the coins
     */
    TALER_TESTING_cmd_refresh_reveal
      ("refresh-reveal-1",
       "refresh-melt-1", MHD_HTTP_OK),
    /* Make refreshed coin invalid */
    TALER_TESTING_cmd_revoke ("revoke-1",
                              MHD_HTTP_OK,
                              "refresh-melt-1",
                              CONFIG_FILE),
    /* Refund coin to original coin */
    TALER_TESTING_cmd_payback ("payback-1",
                               MHD_HTTP_OK,
                               "refresh-melt-1",
                               "EUR:5"),
    /**
     * Melt original coin AGAIN
     * (EUR:4.00 = 3x EUR:1.03 + 7x EUR:0.13) */
    TALER_TESTING_cmd_refresh_melt_double
      ("refresh-melt-2", "EUR:4",
       "withdraw-coin-1", MHD_HTTP_OK),
    /**
     * Complete (successful) melt operation, and withdraw the coins
     */
    TALER_TESTING_cmd_refresh_reveal
      ("refresh-reveal-2",
       "refresh-melt-2", MHD_HTTP_OK),
    /* Make refreshed coin invalid */
    TALER_TESTING_cmd_revoke ("revoke-2",
                              MHD_HTTP_OK,
                              "refresh-melt-2",
                              CONFIG_FILE),
    /* Make also original coin invalid */
    TALER_TESTING_cmd_revoke ("revoke-3",
                              MHD_HTTP_OK,
                              "withdraw-coin-1",
                              CONFIG_FILE),
    /* Refund coin to original coin */
    TALER_TESTING_cmd_payback ("payback-2",
                               MHD_HTTP_OK,
                               "refresh-melt-2",
                               "EUR:5"),
    /* Refund original coin to reserve */
    TALER_TESTING_cmd_payback ("payback-3",
                               MHD_HTTP_OK,
                               "withdraw-coin-1",
                               "EUR:5"),
    /* Check the money is back with the reserve */
    TALER_TESTING_cmd_status ("payback-reserve-status-1",
                              "create-reserve-1",
                              "EUR:4.0",
                              MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };

  TALER_TESTING_run_with_fakebank (is,
                                   commands,
                                   fakebank_url);
}


int
main (int argc,
      char * const *argv)
{
  /* These environment variables get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-exchange-api-revocation",
                    "INFO",
                    NULL);
  if (NULL == (fakebank_url
       /* Check fakebank port is available and config cares
        * about bank url. */
               = TALER_TESTING_prepare_fakebank (CONFIG_FILE,
                                                 "account-2")))
    return 77;
  TALER_TESTING_cleanup_files (CONFIG_FILE);
  /* @helpers.  Run keyup, create tables, ... Note: it
   * fetches the port number from config in order to see
   * if it's available. */
  switch (TALER_TESTING_prepare_exchange (CONFIG_FILE,
                                          &auditor_url,
                                          &exchange_url))
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

/* end of test_exchange_api_revocation.c */
