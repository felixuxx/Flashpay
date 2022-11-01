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
  TALER_TESTING_cmd_exec_wirewatch (label, config_file)

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
                                        &bc.exchange_auth,       \
                                        bc.user42_payto)

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
      "EUR:5.01", bc.user42_payto, bc.exchange_payto,
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
                               bc.user42_payto,
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
      "EUR:5.01", bc.user42_payto, bc.exchange_payto,
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
                               bc.user42_payto,
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
                               bc.user43_payto,
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
      ec.exchange_url,
      "EUR:4.98",
      bc.exchange_payto,
      bc.user42_payto),
    TALER_TESTING_cmd_check_bank_transfer (
      "check_bank_transfer-99c1",
      ec.exchange_url,
      "EUR:0.98",
      bc.exchange_payto,
      bc.user42_payto),
    TALER_TESTING_cmd_check_bank_transfer (
      "check_bank_transfer-99c",
      ec.exchange_url,
      "EUR:0.08",
      bc.exchange_payto,
      bc.user43_payto),

    /* The following transactions got originated within
     * the "massive deposit confirms" batch.  */
    TALER_TESTING_cmd_check_bank_transfer (
      "check-massive-transfer-1",
      ec.exchange_url,
      "EUR:0.98",
      bc.exchange_payto, bc.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-2",
      ec.exchange_url,
      "EUR:0.98",
      bc.exchange_payto, bc.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-3",
      ec.exchange_url,
      "EUR:0.98",
      bc.exchange_payto, bc.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-4",
      ec.exchange_url,
      "EUR:0.98",
      bc.exchange_payto, bc.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-5",
      ec.exchange_url,
      "EUR:0.98",
      bc.exchange_payto, bc.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-6",
      ec.exchange_url,
      "EUR:0.98",
      bc.exchange_payto, bc.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-7",
      ec.exchange_url,
      "EUR:0.98",
      bc.exchange_payto, bc.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-8",
      ec.exchange_url,
      "EUR:0.98",
      bc.exchange_payto, bc.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-9",
      ec.exchange_url,
      "EUR:0.98",
      bc.exchange_payto, bc.user43_payto),
    TALER_TESTING_cmd_check_bank_transfer
      ("check-massive-transfer-10",
      ec.exchange_url,
      "EUR:0.98",
      bc.exchange_payto, bc.user43_payto),
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
      bc.user42_payto,
      bc.exchange_payto,
      "create-reserve-unaggregated"),
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-unaggregated",
                                       "create-reserve-unaggregated",
                                       "EUR:5",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit ("deposit-unaggregated",
                               "withdraw-coin-unaggregated",
                               0,
                               bc.user43_payto,
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
                               bc.user42_payto,
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
                               bc.user42_payto,
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
    TALER_TESTING_cmd_exec_wirewatch ("short-lived-aggregation",
                                      config_file_expire_reserve_now),
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
                               bc.user42_payto,
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
      bc.user42_payto, bc.exchange_payto,
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
      bc.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit
      ("massive-deposit-2",
      "massive-withdraw-2",
      0,
      bc.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit
      ("massive-deposit-3",
      "massive-withdraw-3",
      0,
      bc.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit
      ("massive-deposit-4",
      "massive-withdraw-4",
      0,
      bc.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit
      ("massive-deposit-5",
      "massive-withdraw-5",
      0,
      bc.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit
      ("massive-deposit-6",
      "massive-withdraw-6",
      0,
      bc.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit
      ("massive-deposit-7",
      "massive-withdraw-7",
      0,
      bc.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit
      ("massive-deposit-8",
      "massive-withdraw-8",
      0,
      bc.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit
      ("massive-deposit-9",
      "massive-withdraw-9",
      0,
      bc.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit (
      "massive-deposit-10",
      "massive-withdraw-10",
      0,
      bc.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit_confirmation ("deposit-confirmation",
                                            is->auditor,
                                            "massive-deposit-10",
                                            0,
                                            "EUR:0.99",
                                            MHD_HTTP_OK),
    CMD_RUN_AUDITOR ("massive-auditor"),

    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command commands[] = {
    TALER_TESTING_cmd_exec_offline_sign_fees ("offline-sign-fees",
                                              config_file,
                                              "EUR:0.01",
                                              "EUR:0.01"),
    TALER_TESTING_cmd_auditor_add ("add-auditor-OK",
                                   MHD_HTTP_NO_CONTENT,
                                   false),
    TALER_TESTING_cmd_wire_add ("add-wire-account",
                                "payto://x-taler-bank/localhost/2?receiver-name=2",
                                MHD_HTTP_NO_CONTENT,
                                false),
    TALER_TESTING_cmd_exec_offline_sign_keys ("offline-sign-future-keys",
                                              config_file),
    TALER_TESTING_cmd_check_keys_pull_all_keys ("refetch /keys",
                                                2),
    TALER_TESTING_cmd_exec_auditor_offline ("auditor-offline",
                                            config_file),
    CMD_RUN_AUDITOR ("virgin-auditor"),
    TALER_TESTING_cmd_exchanges_with_url ("check-exchange",
                                          MHD_HTTP_OK,
                                          "http://localhost:8081/"),
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
    CMD_RUN_AUDITOR ("normal-auditor"),
    TALER_TESTING_cmd_end ()
  };

  (void) cls;
  TALER_TESTING_run_with_fakebank (is,
                                   commands,
                                   bc.exchange_auth.wire_gateway_url);
}


int
main (int argc,
      char *const *argv)
{
  char *cipher;

  (void) argc;
  /* These environment variables get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup (argv[0],
                    "INFO",
                    NULL);

  cipher = GNUNET_TESTING_get_testname_from_underscore (argv[0]);
  GNUNET_assert (NULL != cipher);
  GNUNET_asprintf (&config_file,
                   "test_auditor_api-%s.conf",
                   cipher);
  GNUNET_asprintf (&config_file_expire_reserve_now,
                   "test_auditor_api_expire_reserve_now-%s.conf",
                   cipher);
  GNUNET_free (cipher);
  /* Check fakebank port is available and get configuration data. */
  if (GNUNET_OK !=
      TALER_TESTING_prepare_fakebank (config_file,
                                      "exchange-account-2",
                                      &bc))
    return 77;
  TALER_TESTING_cleanup_files (config_file);
  /* @helpers.  Run keyup, create tables, ... Note: it
   * fetches the port number from config in order to see
   * if it's available. */
  switch (TALER_TESTING_prepare_exchange (config_file,
                                          GNUNET_YES,
                                          &ec))
  {
  case GNUNET_SYSERR:
    GNUNET_break (0);
    return 1;
  case GNUNET_NO:
    return 78;
  case GNUNET_OK:
    if (GNUNET_OK !=
        /* Set up event loop and reschedule context, plus
         * start/stop the exchange.  It calls TALER_TESTING_setup
         * which creates the 'is' object.
         */
        TALER_TESTING_auditor_setup (&run,
                                     NULL,
                                     config_file))
      return 2;
    break;
  default:
    GNUNET_break (0);
    return 3;
  }
  return 0;
}


/* end of test_auditor_api.c */
