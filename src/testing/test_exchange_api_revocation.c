/*
  This file is part of TALER
  Copyright (C) 2014--2023 Taler Systems SA

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
#include <gnunet/gnunet_testing_lib.h>
#include <microhttpd.h>
#include "taler_bank_service.h"
#include "taler_fakebank_lib.h"
#include "taler_testing_lib.h"

/**
 * Configuration file we use.  One (big) configuration is used
 * for the various components for this test.
 */
static char *config_file;

/**
 * Our credentials.
 */
static struct TALER_TESTING_Credentials cred;


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
    TALER_TESTING_cmd_run_fakebank ("run-fakebank",
                                    cred.cfg,
                                    "exchange-account-2"),
    TALER_TESTING_cmd_system_start ("start-taler",
                                    config_file,
                                    "-e",
                                    NULL),
    TALER_TESTING_cmd_get_exchange ("get-exchange",
                                    cred.cfg,
                                    NULL,
                                    true,
                                    true),
    /**
     * Fill reserve with EUR:10.02, as withdraw fee is 1 ct per
     * config.
     */
    TALER_TESTING_cmd_admin_add_incoming ("create-reserve-1",
                                          "EUR:10.02",
                                          &cred.ba,
                                          cred.user42_payto),
    TALER_TESTING_cmd_check_bank_admin_transfer ("check-create-reserve-1",
                                                 "EUR:10.02",
                                                 cred.user42_payto,
                                                 cred.exchange_payto,
                                                 "create-reserve-1"),
    /**
     * Run wire-watch to trigger the reserve creation.
     */
    TALER_TESTING_cmd_exec_wirewatch2 ("wirewatch-4",
                                       config_file,
                                       "exchange-account-2"),
    /* Withdraw a 5 EUR coin, at fee of 1 ct */
    TALER_TESTING_cmd_withdraw_amount ("withdraw-revocation-coin-1",
                                       "create-reserve-1",
                                       "EUR:5",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    /* Withdraw another 5 EUR coin, at fee of 1 ct */
    TALER_TESTING_cmd_withdraw_amount ("withdraw-revocation-coin-2",
                                       "create-reserve-1",
                                       "EUR:5",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    /* Try to partially spend (deposit) 1 EUR of the 5 EUR coin (in full)
     * (merchant would receive EUR:0.99 due to 1 ct deposit fee) *///
    TALER_TESTING_cmd_deposit ("deposit-partial",
                               "withdraw-revocation-coin-1",
                               0,
                               cred.user42_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":\"EUR:1\"}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:1",
                               MHD_HTTP_OK),
    /* Deposit another coin in full */
    TALER_TESTING_cmd_deposit ("deposit-full",
                               "withdraw-revocation-coin-2",
                               0,
                               cred.user42_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":\"EUR:5\"}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:5",
                               MHD_HTTP_OK),
    /**
     * Melt SOME of the rest of the coin's value
     * (EUR:3.17 = 3x EUR:1.03 + 7x EUR:0.13)
     */
    TALER_TESTING_cmd_melt ("refresh-melt-1",
                            "withdraw-revocation-coin-1",
                            MHD_HTTP_OK,
                            NULL),
    /**
     * Complete (successful) melt operation, and withdraw the coins
     */
    TALER_TESTING_cmd_refresh_reveal ("refresh-reveal-1",
                                      "refresh-melt-1",
                                      MHD_HTTP_OK),
    /* Try to recoup before it's allowed */
    TALER_TESTING_cmd_recoup_refresh ("recoup-not-allowed",
                                      MHD_HTTP_GONE,
                                      "refresh-reveal-1#0",
                                      "refresh-melt-1",
                                      "EUR:0.1"),
    /* Make refreshed coin invalid */
    TALER_TESTING_cmd_revoke ("revoke-2-EUR:5",
                              MHD_HTTP_OK,
                              "refresh-melt-1",
                              config_file),
    /* Also make fully spent coin invalid (should be same denom) */
    TALER_TESTING_cmd_revoke ("revoke-2-EUR:5",
                              MHD_HTTP_OK,
                              "withdraw-revocation-coin-2",
                              config_file),
    /* Refund fully spent coin (which should fail) */
    TALER_TESTING_cmd_recoup ("recoup-fully-spent",
                              MHD_HTTP_CONFLICT,
                              "withdraw-revocation-coin-2",
                              "EUR:0.1"),
    /* Refund coin to original coin */
    TALER_TESTING_cmd_recoup_refresh ("recoup-1a",
                                      MHD_HTTP_OK,
                                      "refresh-reveal-1#0",
                                      "refresh-melt-1",
                                      "EUR:1"),
    TALER_TESTING_cmd_recoup_refresh ("recoup-1b",
                                      MHD_HTTP_OK,
                                      "refresh-reveal-1#1",
                                      "refresh-melt-1",
                                      "EUR:1"),
    TALER_TESTING_cmd_recoup_refresh ("recoup-1c",
                                      MHD_HTTP_OK,
                                      "refresh-reveal-1#2",
                                      "refresh-melt-1",
                                      "EUR:1"),
    /* Repeat recoup to test idempotency */
    TALER_TESTING_cmd_recoup_refresh ("recoup-1c",
                                      MHD_HTTP_OK,
                                      "refresh-reveal-1#2",
                                      "refresh-melt-1",
                                      "EUR:1"),
    TALER_TESTING_cmd_recoup_refresh ("recoup-1c",
                                      MHD_HTTP_OK,
                                      "refresh-reveal-1#2",
                                      "refresh-melt-1",
                                      "EUR:1"),
    TALER_TESTING_cmd_recoup_refresh ("recoup-1c",
                                      MHD_HTTP_OK,
                                      "refresh-reveal-1#2",
                                      "refresh-melt-1",
                                      "EUR:1"),
    TALER_TESTING_cmd_recoup_refresh ("recoup-1c",
                                      MHD_HTTP_OK,
                                      "refresh-reveal-1#2",
                                      "refresh-melt-1",
                                      "EUR:1"),
    /* Now we have EUR:3.83 EUR back after 3x EUR:1 in recoups */
    /* Melt original coin AGAIN, but only create one 0.1 EUR coin;
       This costs EUR:0.03 in refresh and EUR:01 in withdraw fees,
       leaving EUR:3.69. */
    TALER_TESTING_cmd_melt ("refresh-melt-2",
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
                              config_file),
    /* Revoke also original coin denomination */
    TALER_TESTING_cmd_revoke ("revoke-4-EUR:5",
                              MHD_HTTP_OK,
                              "withdraw-revocation-coin-1",
                              config_file),
    /* Refund coin EUR:0.1 to original coin, creating zombie! */
    TALER_TESTING_cmd_recoup_refresh ("recoup-2",
                                      MHD_HTTP_OK,
                                      "refresh-reveal-2",
                                      "refresh-melt-2",
                                      "EUR:0.1"),
    /* Due to recoup, original coin is now at EUR:3.79 */
    /* Refund original (now zombie) coin to reserve */
    TALER_TESTING_cmd_recoup ("recoup-3",
                              MHD_HTTP_OK,
                              "withdraw-revocation-coin-1",
                              "EUR:3.79"),
    /* Check the money is back with the reserve */
    TALER_TESTING_cmd_status ("recoup-reserve-status-1",
                              "create-reserve-1",
                              "EUR:3.79",
                              MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };

  (void) cls;
  TALER_TESTING_run (is,
                     revocation);
}


int
main (int argc,
      char *const *argv)
{
  (void) argc;
  {
    char *cipher;

    cipher = GNUNET_STRINGS_get_suffix_from_binary_name (argv[0]);
    GNUNET_assert (NULL != cipher);
    GNUNET_asprintf (&config_file,
                     "test_exchange_api-%s.conf",
                     cipher);
    GNUNET_free (cipher);
  }
  return TALER_TESTING_main (argv,
                             "INFO",
                             config_file,
                             "exchange-account-2",
                             TALER_TESTING_BS_FAKEBANK,
                             &cred,
                             &run,
                             NULL);
}


/* end of test_exchange_api_revocation.c */
