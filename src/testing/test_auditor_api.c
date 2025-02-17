/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file testing/test_auditor_api.c
 * @brief testcase to test auditor's HTTP API interface
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_exchange_service.h"
#include "taler_auditor_service.h"
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

static char *config_file_expire_reserve_now;

/**
 * Our credentials.
 */
static struct TALER_TESTING_Credentials cred;

/**
 * Execute the taler-exchange-wirewatch command with
 * our configuration file.
 *
 * @param label label to use for the command.
 */
#define CMD_EXEC_WIREWATCH(label) \
        TALER_TESTING_cmd_exec_wirewatch2 (label, config_file, \
                                           "exchange-account-2")

/**
 * Execute the taler-exchange-aggregator, closer and transfer commands with
 * our configuration file.
 *
 * @param label label to use for the command.
 */
#define CMD_EXEC_AGGREGATOR(label) \
        TALER_TESTING_cmd_sleep (label "-sleep", 1), \
        TALER_TESTING_cmd_exec_aggregator (label, config_file), \
        TALER_TESTING_cmd_exec_transfer (label, config_file)

/**
 * Run wire transfer of funds from some user's account to the
 * exchange.
 *
 * @param label label to use for the command.
 * @param amount amount to transfer, i.e. "EUR:1"
 */
#define CMD_TRANSFER_TO_EXCHANGE(label,amount) \
        TALER_TESTING_cmd_admin_add_incoming (label, amount,           \
                                              &cred.ba,       \
                                              cred.user42_payto)

/**
 * Run the taler-auditor.
 *
 * @param label label to use for the command.
 */
#define CMD_RUN_AUDITOR(label) \
        TALER_TESTING_cmd_exec_auditor (label, config_file)


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
    /**
     * Move money to the exchange's bank account.
     */
    CMD_TRANSFER_TO_EXCHANGE ("create-reserve-1",
                              "EUR:5.01"),
    TALER_TESTING_cmd_check_bank_admin_transfer
      ("check-create-reserve-1",
      "EUR:5.01", cred.user42_payto, cred.exchange_payto,
      "create-reserve-1"),
    /**
     * Make a reserve exist, according to the previous transfer.
     */
    CMD_EXEC_WIREWATCH ("wirewatch-1"),
    /**
     * Withdraw EUR:5.
     */
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-1",
                                       "create-reserve-1",
                                       "EUR:5",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command spend[] = {
    /**
     * Spend the coin.
     */
    TALER_TESTING_cmd_deposit ("deposit-simple",
                               "withdraw-coin-1",
                               0,
                               cred.user42_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:5",
                               MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command refresh[] = {
    /* Fill reserve with EUR:5, 1ct is for fees.  NOTE: the old
     * test-suite gave a account number of _424_ to the user at
     * this step; to type less, here the _42_ number is reused.
     * Does this change the tests semantics? *///
    CMD_TRANSFER_TO_EXCHANGE ("refresh-create-reserve-1",
                              "EUR:5.01"),
    TALER_TESTING_cmd_check_bank_admin_transfer
      ("check-refresh-create-reserve-1",
      "EUR:5.01", cred.user42_payto, cred.exchange_payto,
      "refresh-create-reserve-1"),
    /**
     * Make previous command effective.
     */
    CMD_EXEC_WIREWATCH ("wirewatch-2"),
    /**
     * Withdraw EUR:5.
     */
    TALER_TESTING_cmd_withdraw_amount ("refresh-withdraw-coin-1",
                                       "refresh-create-reserve-1",
                                       "EUR:5",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    /**
     * Try to partially spend (deposit) 1 EUR of the 5 EUR coin (in
     * full) Merchant receives EUR:0.99 due to 1 ct deposit fee.
     */
    TALER_TESTING_cmd_deposit ("refresh-deposit-partial",
                               "refresh-withdraw-coin-1",
                               0,
                               cred.user42_payto,
                               "{\"items\":[{\"name\":\"ice\",\"value\":\"EUR:1\"}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:1",
                               MHD_HTTP_OK),
    /**
     * Melt the rest of the coin's value (EUR:4.00 = 3x EUR:1.03 + 7x
     * EUR:0.13)
     */
    TALER_TESTING_cmd_melt_double ("refresh-melt-1",
                                   "refresh-withdraw-coin-1",
                                   MHD_HTTP_OK,
                                   NULL),
    /**
     * Complete (successful) melt operation, and withdraw the coins
     */
    TALER_TESTING_cmd_refresh_reveal ("refresh-reveal-1",
                                      "refresh-melt-1",
                                      MHD_HTTP_OK),
    /**
     * Try to spend a refreshed EUR:0.1 coin
     */
    TALER_TESTING_cmd_deposit ("refresh-deposit-refreshed-1b",
                               "refresh-reveal-1",
                               3,
                               cred.user43_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":3}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:0.1",
                               MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command track[] = {
    /**
     * Run transfers. Note that _actual_ aggregation will NOT
     * happen here, as each deposit operation is run with a
     * fresh merchant public key! NOTE: this comment comes
     * "verbatim" from the old test-suite, and IMO does not explain
     * a lot! */
    CMD_EXEC_AGGREGATOR ("run-aggregator"),

    /**
     * Check all the transfers took place.
     */
    TALER_TESTING_cmd_check_bank_transfer (
      "check_bank_transfer-499c",
      cred.exchange_url,
      "EUR:4.98",
      cred.exchange_payto,
      cred.user42_payto),
    TALER_TESTING_cmd_check_bank_transfer (
      "check_bank_transfer-99c1",
      cred.exchange_url,
      "EUR:0.98",
      cred.exchange_payto,
      cred.user42_payto),
    TALER_TESTING_cmd_check_bank_transfer (
      "check_bank_transfer-99c",
      cred.exchange_url,
      "EUR:0.08",
      cred.exchange_payto,
      cred.user43_payto),

    /* The following transactions got originated within
     * the "massive deposit confirms" batch.  */
    TALER_TESTING_cmd_check_bank_transfer (
      "check-massive-transfer-1",
      cred.exchange_url,
      "EUR:0.98",
      cred.exchange_payto, cred.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-2",
      cred.exchange_url,
      "EUR:0.98",
      cred.exchange_payto, cred.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-3",
      cred.exchange_url,
      "EUR:0.98",
      cred.exchange_payto, cred.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-4",
      cred.exchange_url,
      "EUR:0.98",
      cred.exchange_payto, cred.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-5",
      cred.exchange_url,
      "EUR:0.98",
      cred.exchange_payto, cred.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-6",
      cred.exchange_url,
      "EUR:0.98",
      cred.exchange_payto, cred.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-7",
      cred.exchange_url,
      "EUR:0.98",
      cred.exchange_payto, cred.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-8",
      cred.exchange_url,
      "EUR:0.98",
      cred.exchange_payto, cred.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-9",
      cred.exchange_url,
      "EUR:0.98",
      cred.exchange_payto, cred.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-10",
      cred.exchange_url,
      "EUR:0.98",
      cred.exchange_payto, cred.user43_payto),
    TALER_TESTING_cmd_check_bank_empty ("check_bank_empty"),
    TALER_TESTING_cmd_end ()
  };

  /**
   * This block checks whether a wire deadline
   * very far in the future does NOT get aggregated now.
   */
  struct TALER_TESTING_Command unaggregation[] = {
    TALER_TESTING_cmd_check_bank_empty ("far-future-aggregation-a"),
    CMD_TRANSFER_TO_EXCHANGE ("create-reserve-unaggregated",
                              "EUR:5.01"),
    CMD_EXEC_WIREWATCH ("wirewatch-unaggregated"),
    /* "consume" reserve creation transfer.  */
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "check_bank_transfer-unaggregated",
      "EUR:5.01",
      cred.user42_payto,
      cred.exchange_payto,
      "create-reserve-unaggregated"),
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-unaggregated",
                                       "create-reserve-unaggregated",
                                       "EUR:5",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit ("deposit-unaggregated",
                               "withdraw-coin-unaggregated",
                               0,
                               cred.user43_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
                               GNUNET_TIME_relative_multiply
                                 (GNUNET_TIME_UNIT_YEARS,
                                 3000),
                               "EUR:5",
                               MHD_HTTP_OK),
    CMD_EXEC_AGGREGATOR ("aggregation-attempt"),
    TALER_TESTING_cmd_check_bank_empty ("far-future-aggregation-b"),
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command refund[] = {
    /**
     * Fill reserve with EUR:5.01, as withdraw fee is 1 ct per config.
     */
    CMD_TRANSFER_TO_EXCHANGE ("create-reserve-r1",
                              "EUR:5.01"),
    /**
     * Run wire-watch to trigger the reserve creation.
     */
    CMD_EXEC_WIREWATCH ("wirewatch-3"),
    /**
     * Withdraw a 5 EUR coin, at fee of 1 ct
     */
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-r1",
                                       "create-reserve-r1",
                                       "EUR:5",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    /**
     * Spend 5 EUR of the 5 EUR coin (in full). Merchant would
     * receive EUR:4.99 due to 1 ct deposit fee.
     */
    TALER_TESTING_cmd_deposit ("deposit-refund-1",
                               "withdraw-coin-r1",
                               0,
                               cred.user42_payto,
                               "{\"items\":[{\"name\":\"ice\",\"value\":\"EUR:5\"}]}",
                               GNUNET_TIME_UNIT_MINUTES,
                               "EUR:5",
                               MHD_HTTP_OK),

    TALER_TESTING_cmd_refund ("refund-ok",
                              MHD_HTTP_OK,
                              "EUR:5",
                              "deposit-refund-1"),
    /**
     * Spend 4.99 EUR of the refunded 4.99 EUR coin (1ct gone
     * due to refund) (merchant would receive EUR:4.98 due to
     * 1 ct deposit fee) */
    TALER_TESTING_cmd_deposit ("deposit-refund-2",
                               "withdraw-coin-r1",
                               0,
                               cred.user42_payto,
                               "{\"items\":[{\"name\":\"more\",\"value\":\"EUR:5\"}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:4.99",
                               MHD_HTTP_OK),
    /**
     * Run transfers. This will do the transfer as refund deadline was
     * 0.
     */
    CMD_EXEC_AGGREGATOR ("run-aggregator-3"),
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command recoup[] = {
    /**
     * Fill reserve with EUR:5.01, as withdraw fee is 1 ct per
     * config.
     */
    CMD_TRANSFER_TO_EXCHANGE ("recoup-create-reserve-1",
                              "EUR:5.01"),
    /**
     * Run wire-watch to trigger the reserve creation.
     */
    CMD_EXEC_WIREWATCH ("wirewatch-4"),
    /**
     * Withdraw a 5 EUR coin, at fee of 1 ct
     */
    TALER_TESTING_cmd_withdraw_amount ("recoup-withdraw-coin-1",
                                       "recoup-create-reserve-1",
                                       "EUR:5",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_revoke ("revoke-1",
                              MHD_HTTP_OK,
                              "recoup-withdraw-coin-1",
                              config_file),
    TALER_TESTING_cmd_recoup ("recoup-1",
                              MHD_HTTP_OK,
                              "recoup-withdraw-coin-1",
                              "EUR:5"),
    /**
     * Re-withdraw from this reserve
     */
    TALER_TESTING_cmd_withdraw_amount ("recoup-withdraw-coin-2",
                                       "recoup-create-reserve-1",
                                       "EUR:1",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    /**
     * These commands should close the reserve because the aggregator
     * is given a config file that overrides the reserve expiration
     * time (making it now-ish)
     */
    CMD_TRANSFER_TO_EXCHANGE ("short-lived-reserve",
                              "EUR:5.01"),
    TALER_TESTING_cmd_exec_wirewatch2 ("short-lived-aggregation",
                                       config_file_expire_reserve_now,
                                       "exchange-account-2"),
    TALER_TESTING_cmd_exec_aggregator ("close-reserves",
                                       config_file_expire_reserve_now),
    /**
     * Fill reserve with EUR:2.02, as withdraw fee is 1 ct per
     * config, then withdraw two coin, partially spend one, and
     * then have the rest paid back.  Check deposit of other coin
     * fails.  (Do not use EUR:5 here as the EUR:5 coin was
     * revoked and we did not bother to create a new one...)
     */CMD_TRANSFER_TO_EXCHANGE ("recoup-create-reserve-2",
                              "EUR:2.02"),
    /**
     * Make previous command effective.
     */
    CMD_EXEC_WIREWATCH ("wirewatch-5"),
    /**
     * Withdraw a 1 EUR coin, at fee of 1 ct
     */
    TALER_TESTING_cmd_withdraw_amount ("recoup-withdraw-coin-2a",
                                       "recoup-create-reserve-2",
                                       "EUR:1",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    /**
     * Withdraw a 1 EUR coin, at fee of 1 ct
     */
    TALER_TESTING_cmd_withdraw_amount ("recoup-withdraw-coin-2b",
                                       "recoup-create-reserve-2",
                                       "EUR:1",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit ("recoup-deposit-partial",
                               "recoup-withdraw-coin-2a",
                               0,
                               cred.user42_payto,
                               "{\"items\":[{\"name\":\"more ice cream\",\"value\":1}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:0.5",
                               MHD_HTTP_OK),
    TALER_TESTING_cmd_revoke ("revoke-2",
                              MHD_HTTP_OK,
                              "recoup-withdraw-coin-2a",
                              config_file),
    TALER_TESTING_cmd_recoup ("recoup-2",
                              MHD_HTTP_OK,
                              "recoup-withdraw-coin-2a",
                              "EUR:0.5"),
    TALER_TESTING_cmd_end ()
  };


  struct TALER_TESTING_Command massive_deposit_confirms[] = {

    /**
     * Move money to the exchange's bank account.
     */
    CMD_TRANSFER_TO_EXCHANGE ("massive-reserve",
                              "EUR:10.10"),
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "check-massive-transfer",
      "EUR:10.10",
      cred.user42_payto,
      cred.exchange_payto,
      "massive-reserve"),
    CMD_EXEC_WIREWATCH ("massive-wirewatch"),
    TALER_TESTING_cmd_withdraw_amount ("massive-withdraw-1",
                                       "massive-reserve",
                                       "EUR:1",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_withdraw_amount ("massive-withdraw-2",
                                       "massive-reserve",
                                       "EUR:1",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_withdraw_amount ("massive-withdraw-3",
                                       "massive-reserve",
                                       "EUR:1",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_withdraw_amount ("massive-withdraw-4",
                                       "massive-reserve",
                                       "EUR:1",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_withdraw_amount ("massive-withdraw-5",
                                       "massive-reserve",
                                       "EUR:1",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_withdraw_amount ("massive-withdraw-6",
                                       "massive-reserve",
                                       "EUR:1",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_withdraw_amount ("massive-withdraw-7",
                                       "massive-reserve",
                                       "EUR:1",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_withdraw_amount ("massive-withdraw-8",
                                       "massive-reserve",
                                       "EUR:1",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_withdraw_amount ("massive-withdraw-9",
                                       "massive-reserve",
                                       "EUR:1",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_withdraw_amount ("massive-withdraw-10",
                                       "massive-reserve",
                                       "EUR:1",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit (
      "massive-deposit-1",
      "massive-withdraw-1",
      0,
      cred.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit
      ("massive-deposit-2",
      "massive-withdraw-2",
      0,
      cred.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit
      ("massive-deposit-3",
      "massive-withdraw-3",
      0,
      cred.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit
      ("massive-deposit-4",
      "massive-withdraw-4",
      0,
      cred.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit
      ("massive-deposit-5",
      "massive-withdraw-5",
      0,
      cred.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit
      ("massive-deposit-6",
      "massive-withdraw-6",
      0,
      cred.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit
      ("massive-deposit-7",
      "massive-withdraw-7",
      0,
      cred.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit
      ("massive-deposit-8",
      "massive-withdraw-8",
      0,
      cred.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit
      ("massive-deposit-9",
      "massive-withdraw-9",
      0,
      cred.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit (
      "massive-deposit-10",
      "massive-withdraw-10",
      0,
      cred.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit_confirmation ("deposit-confirmation",
                                            "massive-deposit-10",
                                            1,
                                            "EUR:0.99",
                                            MHD_HTTP_OK),
    // CMD_RUN_AUDITOR ("massive-auditor"),

    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command commands[] = {
    TALER_TESTING_cmd_run_fakebank ("run-fakebank",
                                    cred.cfg,
                                    "exchange-account-2"),
    TALER_TESTING_cmd_system_start ("start-taler",
                                    config_file,
                                    "-u", "exchange-account-2",
                                    "-ea",
                                    NULL),
    TALER_TESTING_cmd_get_exchange ("get-exchange",
                                    cred.cfg,
                                    NULL,
                                    true,
                                    true),
    TALER_TESTING_cmd_get_auditor ("get-auditor",
                                   cred.cfg,
                                   true),
    TALER_TESTING_cmd_exec_auditor_offline ("auditor-offline",
                                            config_file),
    // CMD_RUN_AUDITOR ("virgin-auditor"),
    TALER_TESTING_cmd_batch ("massive-deposit-confirms",
                             massive_deposit_confirms),
    TALER_TESTING_cmd_batch ("withdraw",
                             withdraw),
    TALER_TESTING_cmd_batch ("spend",
                             spend),
    TALER_TESTING_cmd_batch ("refresh",
                             refresh),
    TALER_TESTING_cmd_batch ("track",
                             track),
    TALER_TESTING_cmd_batch ("unaggregation",
                             unaggregation),
    TALER_TESTING_cmd_batch ("refund",
                             refund),
    TALER_TESTING_cmd_batch ("recoup",
                             recoup),
    // CMD_RUN_AUDITOR ("normal-auditor"),
    TALER_TESTING_cmd_end ()
  };

  (void) cls;
  TALER_TESTING_run (is,
                     commands);
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
                     "test_auditor_api-%s.conf",
                     cipher);
    GNUNET_asprintf (&config_file_expire_reserve_now,
                     "test_auditor_api_expire_reserve_now-%s.conf",
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


/* end of test_auditor_api.c */
