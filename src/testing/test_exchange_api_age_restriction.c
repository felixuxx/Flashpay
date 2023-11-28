/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file testing/test_exchange_api_age_restriction.c
 * @brief testcase to test exchange's age-restrictrition related HTTP API interfaces
 * @author Özgür Kesim
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
#include "taler_extensions.h"

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
 * Some tests behave differently when using CS as we cannot
 * reuse the coin private key for different denominations
 * due to the derivation of it with the /csr values. Hence
 * some tests behave differently in CS mode, hence this
 * flag.
 */
static bool uses_cs;

/**
 * Execute the taler-exchange-wirewatch command with
 * our configuration file.
 *
 * @param label label to use for the command.
 */
#define CMD_EXEC_WIREWATCH(label) \
  TALER_TESTING_cmd_exec_wirewatch2 (label, config_file, "exchange-account-2")

/**
 * Execute the taler-exchange-aggregator, closer and transfer commands with
 * our configuration file.
 *
 * @param label label to use for the command.
 */
#define CMD_EXEC_AGGREGATOR(label) \
  TALER_TESTING_cmd_sleep ("sleep-before-aggregator", 2), \
  TALER_TESTING_cmd_exec_aggregator (label "-aggregator", config_file), \
  TALER_TESTING_cmd_exec_transfer (label "-transfer", config_file)


/**
 * Run wire transfer of funds from some user's account to the
 * exchange.
 *
 * @param label label to use for the command.
 * @param amount amount to transfer, i.e. "EUR:1"
 */
#define CMD_TRANSFER_TO_EXCHANGE(label,amount) \
  TALER_TESTING_cmd_admin_add_incoming (label, amount, \
                                        &cred.ba,                \
                                        cred.user42_payto)

/**
 * Main function that will tell the interpreter what commands to
 * run.
 *
 * @param cls closure
 * @param is interpreter we use to run commands
 */
static void
run (void *cls,
     struct TALER_TESTING_Interpreter *is)
{
  (void) cls;
  /**
   * Test withdrawal with age restriction.  Success is expected (because the
   * amount is below the kyc threshold ), so it MUST be
   * called _after_ TALER_TESTING_cmd_exec_offline_sign_extensions is called,
   * i. e. age restriction is activated in the exchange!
   *
   * TODO: create a test that tries to withdraw coins with age restriction but
   * (expectedly) fails because the exchange doesn't support age restriction
   * yet.
   */
  struct TALER_TESTING_Command withdraw_age[] = {
    /**
     * Move money to the exchange's bank account.
     */
    CMD_TRANSFER_TO_EXCHANGE ("create-reserve-age",
                              "EUR:6.01"),
    TALER_TESTING_cmd_check_bank_admin_transfer ("check-create-reserve-age",
                                                 "EUR:6.01",
                                                 cred.user42_payto,
                                                 cred.exchange_payto,
                                                 "create-reserve-age"),
    /**
     * Make a reserve exist, according to the previous
     * transfer.
     */
    CMD_EXEC_WIREWATCH ("wirewatch-age"),
    /**
     * Withdraw EUR:5.
     */
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-age-1",
                                       "create-reserve-age",
                                       "EUR:5",
                                       13,
                                       MHD_HTTP_OK),

    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command spend_age[] = {
    /**
     * Spend the coin.
     */
    TALER_TESTING_cmd_deposit ("deposit-simple-age",
                               "withdraw-coin-age-1",
                               0,
                               cred.user42_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:4.99",
                               MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit_replay ("deposit-simple-replay-age",
                                      "deposit-simple-age",
                                      MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };


  struct TALER_TESTING_Command refresh_age[] = {
    /* Fill reserve with EUR:5, 1ct is for fees. */
    CMD_TRANSFER_TO_EXCHANGE ("refresh-create-reserve-age-1",
                              "EUR:6.01"),
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "ck-refresh-create-reserve-age-1",
      "EUR:6.01",
      cred.user42_payto,
      cred.exchange_payto,
      "refresh-create-reserve-age-1"),
    /**
     * Make previous command effective.
     */
    CMD_EXEC_WIREWATCH ("wirewatch-age-2"),
    /**
     * Withdraw EUR:7 with age restriction for age 13.
     */
    TALER_TESTING_cmd_withdraw_amount ("refresh-withdraw-coin-age-1",
                                       "refresh-create-reserve-age-1",
                                       "EUR:5",
                                       13,
                                       MHD_HTTP_OK),
    /* Try to partially spend (deposit) 1 EUR of the 5 EUR coin
     * (in full) (merchant would receive EUR:0.99 due to 1 ct
     * deposit fee)
     */
    TALER_TESTING_cmd_deposit ("refresh-deposit-partial-age",
                               "refresh-withdraw-coin-age-1",
                               0,
                               cred.user42_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":\"EUR:1\"}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:1",
                               MHD_HTTP_OK),
    /**
     * Melt the rest of the coin's value
     * (EUR:4.00 = 3x EUR:1.03 + 7x EUR:0.13) */
    TALER_TESTING_cmd_melt_double ("refresh-melt-age-1",
                                   "refresh-withdraw-coin-age-1",
                                   MHD_HTTP_OK,
                                   NULL),
    /**
     * Complete (successful) melt operation, and
     * withdraw the coins
     */
    TALER_TESTING_cmd_refresh_reveal ("refresh-reveal-age-1",
                                      "refresh-melt-age-1",
                                      MHD_HTTP_OK),
    /**
     * Do it again to check idempotency
     */
    TALER_TESTING_cmd_refresh_reveal ("refresh-reveal-age-1-idempotency",
                                      "refresh-melt-age-1",
                                      MHD_HTTP_OK),
    /**
     * Test that /refresh/link works
     */
    TALER_TESTING_cmd_refresh_link ("refresh-link-age-1",
                                    "refresh-reveal-age-1",
                                    MHD_HTTP_OK),
    /**
     * Try to spend a refreshed EUR:1 coin
     */
    TALER_TESTING_cmd_deposit ("refresh-deposit-refreshed-age-1a",
                               "refresh-reveal-age-1-idempotency",
                               0,
                               cred.user42_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":3}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:1",
                               MHD_HTTP_OK),
    /**
     * Try to spend a refreshed EUR:0.1 coin
     */
    TALER_TESTING_cmd_deposit ("refresh-deposit-refreshed-age-1b",
                               "refresh-reveal-age-1",
                               3,
                               cred.user43_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":3}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:0.1",
                               MHD_HTTP_OK),
    /* Test running a failing melt operation (same operation
     * again must fail) */
    TALER_TESTING_cmd_melt ("refresh-melt-failing-age",
                            "refresh-withdraw-coin-age-1",
                            MHD_HTTP_CONFLICT,
                            NULL),
    /* Test running a failing melt operation (on a coin that
       was itself revealed and subsequently deposited) */
    TALER_TESTING_cmd_melt ("refresh-melt-failing-age-2",
                            "refresh-reveal-age-1",
                            MHD_HTTP_CONFLICT,
                            NULL),
    TALER_TESTING_cmd_end ()
  };

  /**
   * Test with age-withdraw, after kyc process has set a birthdate
   */
  struct TALER_TESTING_Command age_withdraw[] = {
    CMD_TRANSFER_TO_EXCHANGE ("create-reserve-kyc-1",
                              "EUR:30.02"),
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "check-create-reserve-kyc-1",
      "EUR:30.02",
      cred.user42_payto,
      cred.exchange_payto,
      "create-reserve-kyc-1"),
    CMD_EXEC_WIREWATCH ("wirewatch-age-withdraw-1"),
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-1-lacking-kyc",
                                       "create-reserve-kyc-1",
                                       "EUR:10",
                                       0, /* age restriction off */
                                       MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS),
    TALER_TESTING_cmd_check_kyc_get ("check-kyc-withdraw",
                                     "withdraw-coin-1-lacking-kyc",
                                     MHD_HTTP_ACCEPTED),
    TALER_TESTING_cmd_proof_kyc_oauth2 ("proof-kyc",
                                        "withdraw-coin-1-lacking-kyc",
                                        "kyc-provider-test-oauth2",
                                        "pass",
                                        MHD_HTTP_SEE_OTHER),
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-1-with-kyc",
                                       "create-reserve-kyc-1",
                                       "EUR:10",
                                       0, /* age restriction off */
                                       MHD_HTTP_CONFLICT),
    TALER_TESTING_cmd_age_withdraw ("age-withdraw-coin-1-too-low",
                                    "create-reserve-kyc-1",
                                    18, /* Too high */
                                    MHD_HTTP_CONFLICT,
                                    "EUR:10",
                                    NULL),
    TALER_TESTING_cmd_age_withdraw ("age-withdraw-coins-1",
                                    "create-reserve-kyc-1",
                                    8,
                                    MHD_HTTP_OK,
                                    "EUR:10",
                                    "EUR:10",
                                    "EUR:5",
                                    NULL),
    TALER_TESTING_cmd_age_withdraw_reveal ("age-withdraw-coins-reveal-1",
                                           "age-withdraw-coins-1",
                                           MHD_HTTP_OK),
    TALER_TESTING_cmd_end (),
  };

  {
    struct TALER_TESTING_Command commands[] = {
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
      TALER_TESTING_cmd_oauth_with_birthdate ("oauth-service-with-birthdate",
                                              "2015-00-00", /* enough for a while */
                                              6666),
      TALER_TESTING_cmd_batch ("withdraw-age",
                               withdraw_age),
      TALER_TESTING_cmd_batch ("spend-age",
                               spend_age),
      TALER_TESTING_cmd_batch ("refresh-age",
                               refresh_age),
      TALER_TESTING_cmd_batch ("age-withdraw",
                               age_withdraw),
      /* End the suite. */
      TALER_TESTING_cmd_end ()
    };

    TALER_TESTING_run (is,
                       commands);
  }
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
    uses_cs = (0 == strcmp (cipher,
                            "cs"));
    GNUNET_asprintf (&config_file,
                     "test_exchange_api_age_restriction-%s.conf",
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


/* end of test_exchange_api_age_restriction.c */
