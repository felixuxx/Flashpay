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
 * @file testing/test_exchange_api.c
 * @brief testcase to test exchange's HTTP API interface
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

#define CONFIG_FILE_EXPIRE_RESERVE_NOW \
  "test_exchange_api_expire_reserve_now.conf"


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
#define CMD_EXEC_AGGREGATOR(label) \
  TALER_TESTING_cmd_exec_aggregator (label "-aggregator", CONFIG_FILE), \
  TALER_TESTING_cmd_exec_transfer (label "-transfer", CONFIG_FILE)


/**
 * Run wire transfer of funds from some user's account to the
 * exchange.
 *
 * @param label label to use for the command.
 * @param amount amount to transfer, i.e. "EUR:1"
 */
#define CMD_TRANSFER_TO_EXCHANGE(label,amount) \
  TALER_TESTING_cmd_admin_add_incoming (label, amount, \
                                        &bc.exchange_auth,                \
                                        bc.user42_payto)

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
  /**
   * Checks made against /wire response.
   */
  struct TALER_TESTING_Command wire[] = {
    /**
     * Check if 'x-taler-bank' wire method is offered
     * by the exchange.
     */
    TALER_TESTING_cmd_wire ("wire-taler-bank-1",
                            "x-taler-bank",
                            NULL,
                            MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };

  /**
   * Test withdrawal plus spending.
   */
  struct TALER_TESTING_Command withdraw[] = {
    /**
     * Move money to the exchange's bank account.
     */
    CMD_TRANSFER_TO_EXCHANGE ("create-reserve-1",
                              "EUR:4.01"),
    TALER_TESTING_cmd_check_bank_admin_transfer ("check-create-reserve-1",
                                                 "EUR:4.01",
                                                 bc.user42_payto,
                                                 bc.exchange_payto,
                                                 "create-reserve-1"),
    /**
     * Make a reserve exist, according to the previous
     * transfer.
     */
    CMD_EXEC_WIREWATCH ("wirewatch-1"),
    /**
     * Do another transfer to the same reserve
     */
    TALER_TESTING_cmd_admin_add_incoming_with_ref ("create-reserve-1.2",
                                                   "EUR:1",
                                                   &bc.exchange_auth,
                                                   bc.user42_payto,
                                                   "create-reserve-1"),
    TALER_TESTING_cmd_check_bank_admin_transfer ("check-create-reserve-1.2",
                                                 "EUR:1",
                                                 bc.user42_payto,
                                                 bc.exchange_payto,
                                                 "create-reserve-1.2"),
    CMD_EXEC_WIREWATCH ("wirewatch-1.2"),
    /**
     * Withdraw EUR:5.
     */
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-1",
                                       "create-reserve-1",
                                       "EUR:5",
                                       MHD_HTTP_OK),
    /**
     * Check the reserve is depleted.
     */
    TALER_TESTING_cmd_status ("status-1",
                              "create-reserve-1",
                              "EUR:0",
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
    TALER_TESTING_cmd_deposit_replay ("deposit-simple-replay",
                                      "deposit-simple",
                                      MHD_HTTP_OK),
    /*
     * Try to overdraw.
     */
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-2",
                                       "create-reserve-1",
                                       "EUR:5",
                                       MHD_HTTP_CONFLICT),
    /**
     * Try to double spend using different wire details.
     */
    TALER_TESTING_cmd_deposit ("deposit-double-1",
                               "withdraw-coin-1",
                               0,
                               bc.user43_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:5",
                               MHD_HTTP_CONFLICT),
    /* Try to double spend using a different transaction id.
     * The test needs the contract terms to differ. This
     * is currently the case because of the "timestamp" field,
     * which is set automatically by #TALER_TESTING_cmd_deposit().
     * This could theoretically fail if at some point a deposit
     * command executes in less than 1 ms. *///
    TALER_TESTING_cmd_deposit ("deposit-double-1",
                               "withdraw-coin-1",
                               0,
                               bc.user43_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:5",
                               MHD_HTTP_CONFLICT),
    /**
     * Try to double spend with different proposal.
     */
    TALER_TESTING_cmd_deposit ("deposit-double-2",
                               "withdraw-coin-1",
                               0,
                               bc.user43_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":2}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:5",
                               MHD_HTTP_CONFLICT),
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command refresh[] = {
    /* Fill reserve with EUR:5, 1ct is for fees. */
    CMD_TRANSFER_TO_EXCHANGE ("refresh-create-reserve-1",
                              "EUR:5.01"),
    TALER_TESTING_cmd_check_bank_admin_transfer ("ck-refresh-create-reserve-1",
                                                 "EUR:5.01",
                                                 bc.user42_payto,
                                                 bc.exchange_payto,
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
                                       MHD_HTTP_OK),
    /* Try to partially spend (deposit) 1 EUR of the 5 EUR coin
     * (in full) (merchant would receive EUR:0.99 due to 1 ct
     * deposit fee) *///
    TALER_TESTING_cmd_deposit ("refresh-deposit-partial",
                               "refresh-withdraw-coin-1",
                               0,
                               bc.user42_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":\"EUR:1\"}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:1",
                               MHD_HTTP_OK),
    /**
     * Melt the rest of the coin's value
     * (EUR:4.00 = 3x EUR:1.03 + 7x EUR:0.13) */
    TALER_TESTING_cmd_melt_double ("refresh-melt-1",
                                   "refresh-withdraw-coin-1",
                                   MHD_HTTP_OK,
                                   NULL),
    /**
     * Complete (successful) melt operation, and
     * withdraw the coins
     */
    TALER_TESTING_cmd_refresh_reveal ("refresh-reveal-1",
                                      "refresh-melt-1",
                                      MHD_HTTP_OK),
    /**
     * Do it again to check idempotency
     */
    TALER_TESTING_cmd_refresh_reveal ("refresh-reveal-1-idempotency",
                                      "refresh-melt-1",
                                      MHD_HTTP_OK),
    /**
     * Test that /refresh/link works
     */
    TALER_TESTING_cmd_refresh_link ("refresh-link-1",
                                    "refresh-reveal-1",
                                    MHD_HTTP_OK),
    /**
     * Try to spend a refreshed EUR:1 coin
     */
    TALER_TESTING_cmd_deposit ("refresh-deposit-refreshed-1a",
                               "refresh-reveal-1-idempotency",
                               0,
                               bc.user42_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":3}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:1",
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
    /* Test running a failing melt operation (same operation
     * again must fail) */
    TALER_TESTING_cmd_melt ("refresh-melt-failing",
                            "refresh-withdraw-coin-1",
                            MHD_HTTP_CONFLICT,
                            NULL),
    /* Test running a failing melt operation (on a coin that
       was itself revealed and subsequently deposited) */
    TALER_TESTING_cmd_melt ("refresh-melt-failing-2",
                            "refresh-reveal-1",
                            MHD_HTTP_CONFLICT,
                            NULL),

    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command track[] = {
    /* Try resolving a deposit's WTID, as we never triggered
     * execution of transactions, the answer should be that
     * the exchange knows about the deposit, but has no WTID yet.
     *///
    TALER_TESTING_cmd_track_transaction ("deposit-wtid-found",
                                         "deposit-simple",
                                         0,
                                         MHD_HTTP_ACCEPTED,
                                         NULL),
    /* Try resolving a deposit's WTID for a failed deposit.
     * As the deposit failed, the answer should be that the
     * exchange does NOT know about the deposit.
     *///
    TALER_TESTING_cmd_track_transaction ("deposit-wtid-failing",
                                         "deposit-double-2",
                                         0,
                                         MHD_HTTP_NOT_FOUND,
                                         NULL),
    /* Try resolving an undefined (all zeros) WTID; this
     * should fail as obviously the exchange didn't use that
     * WTID value for any transaction.
     *///
    TALER_TESTING_cmd_track_transfer_empty ("wire-deposit-failing",
                                            NULL,
                                            0,
                                            MHD_HTTP_NOT_FOUND),
    TALER_TESTING_cmd_sleep ("sleep-before-aggregator",
                             1),
    /* Run transfers. Note that _actual_ aggregation will NOT
     * happen here, as each deposit operation is run with a
     * fresh merchant public key, so the aggregator will treat
     * them as "different" merchants and do the wire transfers
     * individually. *///
    CMD_EXEC_AGGREGATOR ("run-aggregator"),
    /**
     * Check all the transfers took place.
     */
    TALER_TESTING_cmd_check_bank_transfer ("check_bank_transfer-499c",
                                           ec.exchange_url,
                                           "EUR:4.98",
                                           bc.exchange_payto,
                                           bc.user42_payto),
    TALER_TESTING_cmd_check_bank_transfer ("check_bank_transfer-99c1",
                                           ec.exchange_url,
                                           "EUR:0.98",
                                           bc.exchange_payto,
                                           bc.user42_payto),
    TALER_TESTING_cmd_check_bank_transfer ("check_bank_transfer-99c2",
                                           ec.exchange_url,
                                           "EUR:0.98",
                                           bc.exchange_payto,
                                           bc.user42_payto),
    TALER_TESTING_cmd_check_bank_transfer ("check_bank_transfer-99c",
                                           ec.exchange_url,
                                           "EUR:0.08",
                                           bc.exchange_payto,
                                           bc.user43_payto),
    TALER_TESTING_cmd_check_bank_empty ("check_bank_empty"),
    TALER_TESTING_cmd_track_transaction ("deposit-wtid-ok",
                                         "deposit-simple",
                                         0,
                                         MHD_HTTP_OK,
                                         "check_bank_transfer-499c"),
    TALER_TESTING_cmd_track_transfer ("wire-deposit-success-bank",
                                      "check_bank_transfer-99c1",
                                      0,
                                      MHD_HTTP_OK,
                                      "EUR:0.98",
                                      "EUR:0.01"),
    TALER_TESTING_cmd_track_transfer ("wire-deposits-success-wtid",
                                      "deposit-wtid-ok",
                                      0,
                                      MHD_HTTP_OK,
                                      "EUR:4.98",
                                      "EUR:0.01"),
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
    /* "consume" reserve creation transfer.  */
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "check-create-reserve-unaggregated",
      "EUR:5.01",
      bc.user42_payto,
      bc.exchange_payto,
      "create-reserve-unaggregated"),
    CMD_EXEC_WIREWATCH ("wirewatch-unaggregated"),
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-unaggregated",
                                       "create-reserve-unaggregated",
                                       "EUR:5",
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit ("deposit-unaggregated",
                               "withdraw-coin-unaggregated",
                               0,
                               bc.user43_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
                               GNUNET_TIME_relative_multiply (
                                 GNUNET_TIME_UNIT_YEARS,
                                 3000),
                               "EUR:5",
                               MHD_HTTP_OK),
    CMD_EXEC_AGGREGATOR ("aggregation-attempt"),

    TALER_TESTING_cmd_check_bank_empty
      ("far-future-aggregation-b"),

    TALER_TESTING_cmd_end ()
  };


  /**
   * This block exercises the aggretation logic by making two payments
   * to the same merchant.
   */
  struct TALER_TESTING_Command aggregation[] = {
    CMD_TRANSFER_TO_EXCHANGE ("create-reserve-aggtest",
                              "EUR:5.01"),
    /* "consume" reserve creation transfer.  */
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "check-create-reserve-aggtest",
      "EUR:5.01",
      bc.user42_payto,
      bc.exchange_payto,
      "create-reserve-aggtest"),
    CMD_EXEC_WIREWATCH ("wirewatch-aggtest"),
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-aggtest",
                                       "create-reserve-aggtest",
                                       "EUR:5",
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit ("deposit-aggtest-1",
                               "withdraw-coin-aggtest",
                               0,
                               bc.user43_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:2",
                               MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit_with_ref ("deposit-aggtest-2",
                                        "withdraw-coin-aggtest",
                                        0,
                                        bc.user43_payto,
                                        "{\"items\":[{\"name\":\"foo bar\",\"value\":1}]}",
                                        GNUNET_TIME_UNIT_ZERO,
                                        "EUR:2",
                                        MHD_HTTP_OK,
                                        "deposit-aggtest-1"),
    CMD_EXEC_AGGREGATOR ("aggregation-aggtest"),
    TALER_TESTING_cmd_check_bank_transfer ("check-bank-transfer-aggtest",
                                           ec.exchange_url,
                                           "EUR:3.97",
                                           bc.exchange_payto,
                                           bc.user43_payto),
    TALER_TESTING_cmd_check_bank_empty ("check-bank-empty-aggtest"),
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command refund[] = {
    /**
     * Fill reserve with EUR:5.01, as withdraw fee is 1 ct per
     * config.
     */
    CMD_TRANSFER_TO_EXCHANGE ("create-reserve-r1",
                              "EUR:5.01"),
    TALER_TESTING_cmd_check_bank_admin_transfer ("check-create-reserve-r1",
                                                 "EUR:5.01",
                                                 bc.user42_payto,
                                                 bc.exchange_payto,
                                                 "create-reserve-r1"),
    /**
     * Run wire-watch to trigger the reserve creation.
     */
    CMD_EXEC_WIREWATCH ("wirewatch-3"),
    /* Withdraw a 5 EUR coin, at fee of 1 ct */
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-r1",
                                       "create-reserve-r1",
                                       "EUR:5",
                                       MHD_HTTP_OK),
    /**
     * Spend 5 EUR of the 5 EUR coin (in full) (merchant would
     * receive EUR:4.99 due to 1 ct deposit fee)
     */
    TALER_TESTING_cmd_deposit ("deposit-refund-1",
                               "withdraw-coin-r1",
                               0,
                               bc.user42_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":\"EUR:5\"}]}",
                               GNUNET_TIME_UNIT_MINUTES,
                               "EUR:5",
                               MHD_HTTP_OK),
    /**
     * Run transfers. Should do nothing as refund deadline blocks it
     */
    CMD_EXEC_AGGREGATOR ("run-aggregator-refund"),
    /* Check that aggregator didn't do anything, as expected.
     * Note, this operation takes two commands: one to "flush"
     * the preliminary transfer (used to withdraw) from the
     * fakebank and the second to actually check there are not
     * other transfers around. *///
    TALER_TESTING_cmd_check_bank_empty ("check_bank_transfer-pre-refund"),
    TALER_TESTING_cmd_refund ("refund-ok",
                              MHD_HTTP_OK,
                              "EUR:5",
                              "deposit-refund-1"),
    TALER_TESTING_cmd_refund ("refund-ok-double",
                              MHD_HTTP_OK,
                              "EUR:5",
                              "deposit-refund-1"),
    /* Previous /refund(s) had id == 0.  */
    TALER_TESTING_cmd_refund_with_id ("refund-conflicting",
                                      MHD_HTTP_CONFLICT,
                                      "EUR:5",
                                      "deposit-refund-1",
                                      1),
    /**
     * Spend 4.99 EUR of the refunded 4.99 EUR coin (1ct gone
     * due to refund) (merchant would receive EUR:4.98 due to
     * 1 ct deposit fee) */
    TALER_TESTING_cmd_deposit ("deposit-refund-2",
                               "withdraw-coin-r1",
                               0,
                               bc.user42_payto,
                               "{\"items\":[{\"name\":\"more ice cream\",\"value\":\"EUR:5\"}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:4.99",
                               MHD_HTTP_OK),
    /**
     * Run transfers. This will do the transfer as refund deadline
     * was 0
     */
    CMD_EXEC_AGGREGATOR ("run-aggregator-3"),
    /**
     * Check that deposit did run.
     */
    TALER_TESTING_cmd_check_bank_transfer ("check_bank_transfer-pre-refund",
                                           ec.exchange_url,
                                           "EUR:4.97",
                                           bc.exchange_payto,
                                           bc.user42_payto),
    /**
     * Run failing refund, as past deadline & aggregation.
     */
    TALER_TESTING_cmd_refund ("refund-fail",
                              MHD_HTTP_GONE,
                              "EUR:4.99",
                              "deposit-refund-2"),
    TALER_TESTING_cmd_check_bank_empty ("check-empty-after-refund"),
    /**
     * Test refunded coins are never executed, even past
     * refund deadline
     */
    CMD_TRANSFER_TO_EXCHANGE ("create-reserve-rb",
                              "EUR:5.01"),
    TALER_TESTING_cmd_check_bank_admin_transfer ("check-create-reserve-rb",
                                                 "EUR:5.01",
                                                 bc.user42_payto,
                                                 bc.exchange_payto,
                                                 "create-reserve-rb"),
    CMD_EXEC_WIREWATCH ("wirewatch-rb"),
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-rb",
                                       "create-reserve-rb",
                                       "EUR:5",
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit ("deposit-refund-1b",
                               "withdraw-coin-rb",
                               0,
                               bc.user42_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":\"EUR:5\"}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:5",
                               MHD_HTTP_OK),
    /**
     * Trigger refund (before aggregator had a chance to execute
     * deposit, even though refund deadline was zero).
     */
    TALER_TESTING_cmd_refund ("refund-ok-fast",
                              MHD_HTTP_OK,
                              "EUR:5",
                              "deposit-refund-1b"),
    /**
     * Run transfers. This will do the transfer as refund deadline
     * was 0, except of course because the refund succeeded, the
     * transfer should no longer be done.
     *///
    CMD_EXEC_AGGREGATOR ("run-aggregator-3b"),
    /* check that aggregator didn't do anything, as expected */
    TALER_TESTING_cmd_check_bank_empty ("check-refund-fast-not-run"),
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command recoup[] = {
    /**
     * Fill reserve with EUR:5.01, as withdraw fee is 1 ct per
     * config.
     */
    CMD_TRANSFER_TO_EXCHANGE ("recoup-create-reserve-1",
                              "EUR:15.02"),
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "recoup-create-reserve-1-check",
      "EUR:15.02",
      bc.user42_payto,
      bc.exchange_payto,
      "recoup-create-reserve-1"),
    /**
     * Run wire-watch to trigger the reserve creation.
     */
    CMD_EXEC_WIREWATCH ("wirewatch-4"),
    /* Withdraw a 5 EUR coin, at fee of 1 ct */
    TALER_TESTING_cmd_withdraw_amount ("recoup-withdraw-coin-1",
                                       "recoup-create-reserve-1",
                                       "EUR:5",
                                       MHD_HTTP_OK),
    /* Withdraw a 10 EUR coin, at fee of 1 ct */
    TALER_TESTING_cmd_withdraw_amount ("recoup-withdraw-coin-1b",
                                       "recoup-create-reserve-1",
                                       "EUR:10",
                                       MHD_HTTP_OK),
    /* melt 10 EUR coin to get 5 EUR refreshed coin */
    TALER_TESTING_cmd_melt ("recoup-melt-coin-1b",
                            "recoup-withdraw-coin-1b",
                            MHD_HTTP_OK,
                            "EUR:5",
                            NULL),
    TALER_TESTING_cmd_refresh_reveal ("recoup-reveal-coin-1b",
                                      "recoup-melt-coin-1b",
                                      MHD_HTTP_OK),
    /* Revoke both 5 EUR coins */
    TALER_TESTING_cmd_revoke ("revoke-0-EUR:5",
                              MHD_HTTP_OK,
                              "recoup-withdraw-coin-1",
                              CONFIG_FILE),
    /* Recoup coin to reserve */
    TALER_TESTING_cmd_recoup ("recoup-1",
                              MHD_HTTP_OK,
                              "recoup-withdraw-coin-1",
                              NULL,
                              "EUR:5"),
    /* Check the money is back with the reserve */
    TALER_TESTING_cmd_status ("recoup-reserve-status-1",
                              "recoup-create-reserve-1",
                              "EUR:5.0",
                              MHD_HTTP_OK),
    /* Recoup-refresh coin to 10 EUR coin */
    TALER_TESTING_cmd_recoup ("recoup-1b",
                              MHD_HTTP_OK,
                              "recoup-reveal-coin-1b",
                              "recoup-melt-coin-1b",
                              "EUR:5"),
    /* melt 10 EUR coin *again* to get 1 EUR refreshed coin */
    TALER_TESTING_cmd_melt ("recoup-remelt-coin-1a",
                            "recoup-withdraw-coin-1b",
                            MHD_HTTP_OK,
                            "EUR:1",
                            NULL),
    TALER_TESTING_cmd_refresh_reveal ("recoup-reveal-coin-1a",
                                      "recoup-remelt-coin-1a",
                                      MHD_HTTP_OK),
    /* Try melting for more than the residual value to provoke an error */
    TALER_TESTING_cmd_melt ("recoup-remelt-coin-1b",
                            "recoup-withdraw-coin-1b",
                            MHD_HTTP_OK,
                            "EUR:1",
                            NULL),
    TALER_TESTING_cmd_melt ("recoup-remelt-coin-1c",
                            "recoup-withdraw-coin-1b",
                            MHD_HTTP_OK,
                            "EUR:1",
                            NULL),
    TALER_TESTING_cmd_melt ("recoup-remelt-coin-1d",
                            "recoup-withdraw-coin-1b",
                            MHD_HTTP_OK,
                            "EUR:1",
                            NULL),
    TALER_TESTING_cmd_melt ("recoup-remelt-coin-1e",
                            "recoup-withdraw-coin-1b",
                            MHD_HTTP_OK,
                            "EUR:1",
                            NULL),
    TALER_TESTING_cmd_melt ("recoup-remelt-coin-1f",
                            "recoup-withdraw-coin-1b",
                            MHD_HTTP_OK,
                            "EUR:1",
                            NULL),
    TALER_TESTING_cmd_melt ("recoup-remelt-coin-1g",
                            "recoup-withdraw-coin-1b",
                            MHD_HTTP_OK,
                            "EUR:1",
                            NULL),
    TALER_TESTING_cmd_melt ("recoup-remelt-coin-1h",
                            "recoup-withdraw-coin-1b",
                            MHD_HTTP_OK,
                            "EUR:1",
                            NULL),
    TALER_TESTING_cmd_melt ("recoup-remelt-coin-1i",
                            "recoup-withdraw-coin-1b",
                            MHD_HTTP_OK,
                            "EUR:1",
                            NULL),
    TALER_TESTING_cmd_melt ("recoup-remelt-coin-1b-failing",
                            "recoup-withdraw-coin-1b",
                            MHD_HTTP_CONFLICT,
                            "EUR:1",
                            NULL),
    /* Re-withdraw from this reserve */
    TALER_TESTING_cmd_withdraw_amount ("recoup-withdraw-coin-2",
                                       "recoup-create-reserve-1",
                                       "EUR:1",
                                       MHD_HTTP_OK),
    /**
     * This withdrawal will test the logic to create a "recoup"
     * element to insert into the reserve's history.
     */
    TALER_TESTING_cmd_withdraw_amount ("recoup-withdraw-coin-2-over",
                                       "recoup-create-reserve-1",
                                       "EUR:10",
                                       MHD_HTTP_CONFLICT),
    TALER_TESTING_cmd_status ("recoup-reserve-status-2",
                              "recoup-create-reserve-1",
                              "EUR:3.99",
                              MHD_HTTP_OK),
    /* These commands should close the reserve because
     * the aggregator is given a config file that overrides
     * the reserve expiration time (making it now-ish) */
    CMD_TRANSFER_TO_EXCHANGE ("short-lived-reserve",
                              "EUR:5.01"),
    TALER_TESTING_cmd_check_bank_admin_transfer ("check-short-lived-reserve",
                                                 "EUR:5.01",
                                                 bc.user42_payto,
                                                 bc.exchange_payto,
                                                 "short-lived-reserve"),
    TALER_TESTING_cmd_exec_wirewatch ("short-lived-aggregation",
                                      CONFIG_FILE_EXPIRE_RESERVE_NOW),
    TALER_TESTING_cmd_exec_closer ("close-reserves",
                                   CONFIG_FILE_EXPIRE_RESERVE_NOW,
                                   "EUR:5",
                                   "EUR:0.01",
                                   "short-lived-reserve"),
    TALER_TESTING_cmd_exec_transfer ("close-reserves-transfer",
                                     CONFIG_FILE_EXPIRE_RESERVE_NOW),

    TALER_TESTING_cmd_status ("short-lived-status",
                              "short-lived-reserve",
                              "EUR:0",
                              MHD_HTTP_OK),
    TALER_TESTING_cmd_withdraw_amount ("expired-withdraw",
                                       "short-lived-reserve",
                                       "EUR:1",
                                       MHD_HTTP_CONFLICT),
    TALER_TESTING_cmd_check_bank_transfer ("check_bank_short-lived_reimburse",
                                           ec.exchange_url,
                                           "EUR:5",
                                           bc.exchange_payto,
                                           bc.user42_payto),
    /* Fill reserve with EUR:2.02, as withdraw fee is 1 ct per
     * config, then withdraw two coin, partially spend one, and
     * then have the rest paid back.  Check deposit of other coin
     * fails.  Do not use EUR:5 here as the EUR:5 coin was
     * revoked and we did not bother to create a new one... *///
    CMD_TRANSFER_TO_EXCHANGE ("recoup-create-reserve-2",
                              "EUR:2.02"),
    TALER_TESTING_cmd_check_bank_admin_transfer ("ck-recoup-create-reserve-2",
                                                 "EUR:2.02",
                                                 bc.user42_payto,
                                                 bc.exchange_payto,
                                                 "recoup-create-reserve-2"),
    /* Make previous command effective. */
    CMD_EXEC_WIREWATCH ("wirewatch-5"),
    /* Withdraw a 1 EUR coin, at fee of 1 ct */
    TALER_TESTING_cmd_withdraw_amount ("recoup-withdraw-coin-2a",
                                       "recoup-create-reserve-2",
                                       "EUR:1",
                                       MHD_HTTP_OK),
    /* Withdraw a 1 EUR coin, at fee of 1 ct */
    TALER_TESTING_cmd_withdraw_amount ("recoup-withdraw-coin-2b",
                                       "recoup-create-reserve-2",
                                       "EUR:1",
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit ("recoup-deposit-partial",
                               "recoup-withdraw-coin-2a",
                               0,
                               bc.user42_payto,
                               "{\"items\":[{\"name\":\"more ice cream\",\"value\":1}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:0.5",
                               MHD_HTTP_OK),
    TALER_TESTING_cmd_revoke ("revoke-1-EUR:1",
                              MHD_HTTP_OK,
                              "recoup-withdraw-coin-2a",
                              CONFIG_FILE),
    TALER_TESTING_cmd_recoup ("recoup-2",
                              MHD_HTTP_OK,
                              "recoup-withdraw-coin-2a",
                              NULL,
                              "EUR:0.5"),
    /* Idempotency of recoup (withdrawal variant) */
    TALER_TESTING_cmd_recoup ("recoup-2b",
                              MHD_HTTP_OK,
                              "recoup-withdraw-coin-2a",
                              NULL,
                              NULL),
    TALER_TESTING_cmd_deposit ("recoup-deposit-revoked",
                               "recoup-withdraw-coin-2b",
                               0,
                               bc.user42_payto,
                               "{\"items\":[{\"name\":\"more ice cream\",\"value\":1}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:1",
                               MHD_HTTP_NOT_FOUND),
    /* Test deposit fails after recoup, with proof in recoup */

    /* Note that, the exchange will never return the coin's transaction
     * history with recoup data, as we get a 404 on the DK! */
    TALER_TESTING_cmd_deposit ("recoup-deposit-partial-after-recoup",
                               "recoup-withdraw-coin-2a",
                               0,
                               bc.user42_payto,
                               "{\"items\":[{\"name\":\"extra ice cream\",\"value\":1}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:0.5",
                               MHD_HTTP_NOT_FOUND),
    /* Test that revoked coins cannot be withdrawn */
    CMD_TRANSFER_TO_EXCHANGE ("recoup-create-reserve-3",
                              "EUR:1.01"),
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "check-recoup-create-reserve-3",
      "EUR:1.01",
      bc.user42_payto,
      bc.exchange_payto,
      "recoup-create-reserve-3"),
    CMD_EXEC_WIREWATCH ("wirewatch-6"),
    TALER_TESTING_cmd_withdraw_amount ("recoup-withdraw-coin-3-revoked",
                                       "recoup-create-reserve-3",
                                       "EUR:1",
                                       MHD_HTTP_NOT_FOUND),
    /* check that we are empty before the rejection test */
    TALER_TESTING_cmd_check_bank_empty ("check-empty-again"),

    TALER_TESTING_cmd_end ()
  };

#define RESERVE_OPEN_CLOSE_CHUNK 4
#define RESERVE_OPEN_CLOSE_ITERATIONS 3

  struct TALER_TESTING_Command reserve_open_close[(RESERVE_OPEN_CLOSE_ITERATIONS
                                                   * RESERVE_OPEN_CLOSE_CHUNK)
                                                  + 1];
  for (unsigned int i = 0;
       i < RESERVE_OPEN_CLOSE_ITERATIONS;
       i++)
  {
    reserve_open_close[(i * RESERVE_OPEN_CLOSE_CHUNK) + 0]
      = CMD_TRANSFER_TO_EXCHANGE ("reserve-open-close-key",
                                  "EUR:20");
    reserve_open_close[(i * RESERVE_OPEN_CLOSE_CHUNK) + 1]
      = TALER_TESTING_cmd_exec_wirewatch ("reserve-open-close-wirewatch",
                                          CONFIG_FILE_EXPIRE_RESERVE_NOW);
    reserve_open_close[(i * RESERVE_OPEN_CLOSE_CHUNK) + 2]
      = TALER_TESTING_cmd_exec_closer ("reserve-open-close-aggregation",
                                       CONFIG_FILE_EXPIRE_RESERVE_NOW,
                                       "EUR:19.99",
                                       "EUR:0.01",
                                       "reserve-open-close-key");
    reserve_open_close[(i * RESERVE_OPEN_CLOSE_CHUNK) + 3]
      = TALER_TESTING_cmd_status ("reserve-open-close-status",
                                  "reserve-open-close-key",
                                  "EUR:0",
                                  MHD_HTTP_OK);
  }
  reserve_open_close[RESERVE_OPEN_CLOSE_ITERATIONS * RESERVE_OPEN_CLOSE_CHUNK]
    = TALER_TESTING_cmd_end ();

  {
    struct TALER_TESTING_Command commands[] = {
      TALER_TESTING_cmd_batch ("wire",
                               wire),
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
      TALER_TESTING_cmd_batch ("aggregation",
                               aggregation),
      TALER_TESTING_cmd_batch ("refund",
                               refund),
      TALER_TESTING_cmd_batch ("recoup",
                               recoup),
      TALER_TESTING_cmd_batch ("reserve-open-close",
                               reserve_open_close),
      /* End the suite. */
      TALER_TESTING_cmd_end ()
    };

    TALER_TESTING_run_with_fakebank (is,
                                     commands,
                                     bc.exchange_auth.wire_gateway_url);
  }
}


int
main (int argc,
      char *const *argv)
{
  /* These environment variables get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-exchange-api",
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


/* end of test_exchange_api.c */
