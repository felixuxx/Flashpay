/*
  This file is part of TALER
  Copyright (C) 2014--2020 Taler Systems SA

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
 * @file testing/test_exchange_api_revocation.c
 * @brief testcase to test key revocation handling via the exchange's HTTP API interface
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
 * Exchange configuration data.
 */
static struct TALER_TESTING_ExchangeConfiguration ec;

/**
 * Bank configuration data.
 */
static struct TALER_TESTING_BankConfiguration bc;


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
  struct TALER_TESTING_Command revocation[] = {
    /**
     * Fill reserve with EUR:5.01, as withdraw fee is 1 ct per
     * config.
     */
    TALER_TESTING_cmd_admin_add_incoming ("create-reserve-1",
                                          "EUR:5.01",
                                          &bc.exchange_auth,
                                          bc.user42_payto),
    TALER_TESTING_cmd_check_bank_admin_transfer ("check-create-reserve-1",
                                                 "EUR:5.01",
                                                 bc.user42_payto,
                                                 bc.exchange_payto,
                                                 "create-reserve-1"),
    /**
     * Run wire-watch to trigger the reserve creation.
     */
    TALER_TESTING_cmd_exec_wirewatch ("wirewatch-4",
                                      CONFIG_FILE),
    /* Withdraw a 5 EUR coin, at fee of 1 ct */
    TALER_TESTING_cmd_withdraw_amount ("withdraw-revocation-coin-1",
                                       "create-reserve-1",
                                       "EUR:5",
                                       MHD_HTTP_OK),
    /* Try to partially spend (deposit) 1 EUR of the 5 EUR coin (in full)
     * (merchant would receive EUR:0.99 due to 1 ct deposit fee) *///
    TALER_TESTING_cmd_deposit ("deposit-partial",
                               "withdraw-revocation-coin-1",
                               0,
                               bc.user42_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":\"EUR:1\"}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:1",
                               MHD_HTTP_OK),
    /**
     * Melt SOME of the rest of the coin's value
     * (EUR:3.17 = 3x EUR:1.03 + 7x EUR:0.13) */
    TALER_TESTING_cmd_refresh_melt ("refresh-melt-1",
                                    "withdraw-revocation-coin-1",
                                    MHD_HTTP_OK,
                                    NULL),
    /**
     * Complete (successful) melt operation, and withdraw the coins
     */
    TALER_TESTING_cmd_refresh_reveal ("refresh-reveal-1",
                                      "refresh-melt-1",
                                      MHD_HTTP_OK),
    /* Make refreshed coin invalid */
    TALER_TESTING_cmd_revoke ("revoke-2-EUR:5",
                              MHD_HTTP_OK,
                              "refresh-melt-1",
                              CONFIG_FILE),
    /* Refund coin to original coin */
    TALER_TESTING_cmd_recoup ("recoup-1a",
                              MHD_HTTP_OK,
                              "refresh-reveal-1#0",
                              "EUR:1",
                              "refresh-melt-1"),
    TALER_TESTING_cmd_recoup ("recoup-1b",
                              MHD_HTTP_OK,
                              "refresh-reveal-1#1",
                              "EUR:1",
                              "refresh-melt-1"),
    TALER_TESTING_cmd_recoup ("recoup-1c",
                              MHD_HTTP_OK,
                              "refresh-reveal-1#2",
                              "EUR:1",
                              "refresh-melt-1"),
    /* Now we have EUR:3.83 EUR back after 3x EUR:1 in recoups */
    /* Melt original coin AGAIN, but only create one 0.1 EUR coin;
       This costs EUR:0.03 in refresh and EUR:01 in withdraw fees,
       leaving EUR:3.69. */
    TALER_TESTING_cmd_refresh_melt ("refresh-melt-2",
                                    "withdraw-revocation-coin-1",
                                    MHD_HTTP_OK,
                                    "EUR:0.1",
                                    NULL),
    /**
     * Complete (successful) melt operation, and withdraw the coins
     */
    TALER_TESTING_cmd_refresh_reveal ("refresh-reveal-2",
                                      "refresh-melt-2",
                                      MHD_HTTP_OK),
    /* Revokes refreshed EUR:0.1 coin  */
    TALER_TESTING_cmd_revoke ("revoke-3-EUR:0.1",
                              MHD_HTTP_OK,
                              "refresh-reveal-2",
                              CONFIG_FILE),
    /* Revoke also original coin denomination */
    TALER_TESTING_cmd_revoke ("revoke-4-EUR:5",
                              MHD_HTTP_OK,
                              "withdraw-revocation-coin-1",
                              CONFIG_FILE),
    /* Refund coin EUR:0.1 to original coin, creating zombie! */
    TALER_TESTING_cmd_recoup ("recoup-2",
                              MHD_HTTP_OK,
                              "refresh-reveal-2",
                              "EUR:0.1",
                              "refresh-melt-2"),
    /* Due to recoup, original coin is now at EUR:3.79 */
    /* Refund original (now zombie) coin to reserve */
    TALER_TESTING_cmd_recoup ("recoup-3",
                              MHD_HTTP_OK,
                              "withdraw-revocation-coin-1",
                              "EUR:3.79",
                              NULL),
    /* Check the money is back with the reserve */
    TALER_TESTING_cmd_status ("recoup-reserve-status-1",
                              "create-reserve-1",
                              "EUR:3.79",
                              MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };

  TALER_TESTING_run_with_fakebank (is,
                                   revocation,
                                   bc.exchange_auth.wire_gateway_url);
}


int
main (int argc,
      char *const *argv)
{
  /* These environment variables get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-exchange-api-revocation",
                    "INFO",
                    NULL);
  /* Check fakebank port is available and get config */
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


/* end of test_exchange_api_revocation.c */
