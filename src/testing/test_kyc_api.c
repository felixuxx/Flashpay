/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
  TALER_TESTING_cmd_sleep (label "-sleep", 1), \
  TALER_TESTING_cmd_exec_aggregator_with_kyc (label, CONFIG_FILE), \
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
                              "EUR:15.02"),
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "check-create-reserve-1",
      "EUR:15.02", bc.user42_payto, bc.exchange_payto,
      "create-reserve-1"),
    CMD_EXEC_WIREWATCH ("wirewatch-1"),
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-1-no-kyc",
                                       "create-reserve-1",
                                       "EUR:10",
                                       0, /* age restriction off */
                                       MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS),
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-1",
                                       "create-reserve-1",
                                       "EUR:5",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };
  /**
   * Test withdraw with KYC.
   */
  struct TALER_TESTING_Command withdraw_kyc[] = {
    CMD_EXEC_WIREWATCH ("wirewatch-1"),
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-1-lacking-kyc",
                                       "create-reserve-1",
                                       "EUR:5",
                                       0, /* age restriction off */
                                       MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS),
    TALER_TESTING_cmd_check_kyc_get ("check-kyc-withdraw",
                                     "withdraw-coin-1-lacking-kyc",
                                     MHD_HTTP_ACCEPTED),
    TALER_TESTING_cmd_proof_kyc_oauth2 ("proof-kyc",
                                        "withdraw-coin-1-lacking-kyc",
                                        "kyc-provider-test-oauth2",
                                        "pass",
                                        "state",
                                        MHD_HTTP_SEE_OTHER),
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-1-with-kyc",
                                       "create-reserve-1",
                                       "EUR:5",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };
  struct TALER_TESTING_Command spend[] = {
    TALER_TESTING_cmd_deposit (
      "deposit-simple",
      "withdraw-coin-1",
      0,
      bc.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:5",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_track_transaction (
      "track-deposit",
      "deposit-simple",
      0,
      MHD_HTTP_ACCEPTED,
      NULL),
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command track[] = {
    CMD_EXEC_AGGREGATOR ("run-aggregator-before-kyc"),
    TALER_TESTING_cmd_check_bank_empty ("check_bank_empty-no-kyc"),
    TALER_TESTING_cmd_track_transaction (
      "track-deposit-kyc-ready",
      "deposit-simple",
      0,
      MHD_HTTP_ACCEPTED,
      NULL),
    TALER_TESTING_cmd_check_kyc_get ("check-kyc-deposit",
                                     "track-deposit-kyc-ready",
                                     MHD_HTTP_ACCEPTED),
    TALER_TESTING_cmd_proof_kyc_oauth2 ("proof-kyc-no-service",
                                        "track-deposit-kyc-ready",
                                        "kyc-provider-test-oauth2",
                                        "bad",
                                        "state",
                                        MHD_HTTP_BAD_GATEWAY),
    TALER_TESTING_cmd_oauth ("start-oauth-service",
                             6666),
    TALER_TESTING_cmd_proof_kyc_oauth2 ("proof-kyc-fail",
                                        "track-deposit-kyc-ready",
                                        "kyc-provider-test-oauth2",
                                        "bad",
                                        "state",
                                        MHD_HTTP_FORBIDDEN),
    TALER_TESTING_cmd_proof_kyc_oauth2 ("proof-kyc-fail",
                                        "track-deposit-kyc-ready",
                                        "kyc-provider-test-oauth2",
                                        "pass",
                                        "state",
                                        MHD_HTTP_SEE_OTHER),
    CMD_EXEC_AGGREGATOR ("run-aggregator-after-kyc"),
    TALER_TESTING_cmd_check_bank_transfer (
      "check_bank_transfer-499c",
      ec.exchange_url,
      "EUR:4.98",
      bc.exchange_payto,
      bc.user43_payto),
    TALER_TESTING_cmd_check_bank_empty ("check_bank_empty"),
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command wallet_kyc[] = {
    TALER_TESTING_cmd_oauth ("start-oauth-service",
                             6666),
    TALER_TESTING_cmd_wallet_kyc_get ("wallet-kyc-fail",
                                      NULL,
                                      "EUR:1000000",
                                      MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS),
    TALER_TESTING_cmd_check_kyc_get ("check-kyc-wallet",
                                     "wallet-kyc-fail",
                                     MHD_HTTP_ACCEPTED),
    TALER_TESTING_cmd_proof_kyc_oauth2 ("proof-wallet-kyc",
                                        "wallet-kyc-fail",
                                        "kyc-provider-test-oauth2",
                                        "pass",
                                        "state",
                                        MHD_HTTP_SEE_OTHER),
    TALER_TESTING_cmd_check_kyc_get ("wallet-kyc-check",
                                     "wallet-kyc-fail",
                                     MHD_HTTP_NO_CONTENT),
    TALER_TESTING_cmd_end ()
  };

  /**
   * Test withdrawal for P2P
   */
  struct TALER_TESTING_Command p2p_withdraw[] = {
    /**
     * Move money to the exchange's bank account.
     */
    CMD_TRANSFER_TO_EXCHANGE ("p2p_create-reserve-1",
                              "EUR:5.04"),
    CMD_TRANSFER_TO_EXCHANGE ("p2p_create-reserve-2",
                              "EUR:5.01"),
    CMD_TRANSFER_TO_EXCHANGE ("p2p_create-reserve-3",
                              "EUR:0.03"),
    TALER_TESTING_cmd_reserve_poll ("p2p_poll-reserve-1",
                                    "p2p_create-reserve-1",
                                    "EUR:5.04",
                                    GNUNET_TIME_UNIT_MINUTES,
                                    MHD_HTTP_OK),
    TALER_TESTING_cmd_check_bank_admin_transfer ("p2p_check-create-reserve-1",
                                                 "EUR:5.04",
                                                 bc.user42_payto,
                                                 bc.exchange_payto,
                                                 "p2p_create-reserve-1"),
    TALER_TESTING_cmd_check_bank_admin_transfer ("p2p_check-create-reserve-2",
                                                 "EUR:5.01",
                                                 bc.user42_payto,
                                                 bc.exchange_payto,
                                                 "p2p_create-reserve-2"),
    /**
     * Make a reserve exist, according to the previous
     * transfer.
     */
    CMD_EXEC_WIREWATCH ("p2p_wirewatch-1"),
    TALER_TESTING_cmd_reserve_poll_finish ("p2p_finish-poll-reserve-1",
                                           GNUNET_TIME_UNIT_SECONDS,
                                           "p2p_poll-reserve-1"),
    /**
     * Withdraw EUR:5.
     */
    TALER_TESTING_cmd_withdraw_amount ("p2p_withdraw-coin-1",
                                       "p2p_create-reserve-1",
                                       "EUR:5",
                                       0, /* age restriction off */
                                       MHD_HTTP_OK),
    /**
     * Check the reserve is depleted.
     */
    TALER_TESTING_cmd_status ("p2p_status-1",
                              "p2p_create-reserve-1",
                              "EUR:0.03",
                              MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };
  struct TALER_TESTING_Command push[] = {
    TALER_TESTING_cmd_purse_create_with_deposit (
      "purse-with-deposit",
      MHD_HTTP_OK,
      "{\"amount\":\"EUR:1\",\"summary\":\"ice cream\"}",
      true, /* upload contract */
      GNUNET_TIME_UNIT_MINUTES, /* expiration */
      "p2p_withdraw-coin-1",
      "EUR:1.01",
      NULL),
    TALER_TESTING_cmd_purse_poll (
      "push-poll-purse-before-merge",
      MHD_HTTP_OK,
      "purse-with-deposit",
      "EUR:1",
      true,
      GNUNET_TIME_UNIT_MINUTES),
    TALER_TESTING_cmd_contract_get (
      "push-get-contract",
      MHD_HTTP_OK,
      true, /* for merge */
      "purse-with-deposit"),
    TALER_TESTING_cmd_purse_merge (
      "purse-merge-into-reserve",
      MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS,
      "push-get-contract",
      "p2p_create-reserve-1"),
    TALER_TESTING_cmd_check_kyc_get ("check-kyc-purse-merge",
                                     "purse-merge-into-reserve",
                                     MHD_HTTP_ACCEPTED),
    TALER_TESTING_cmd_proof_kyc_oauth2 ("p2p_proof-kyc",
                                        "purse-merge-into-reserve",
                                        "kyc-provider-test-oauth2",
                                        "pass",
                                        "state",
                                        MHD_HTTP_SEE_OTHER),
    TALER_TESTING_cmd_purse_merge (
      "purse-merge-into-reserve",
      MHD_HTTP_OK,
      "push-get-contract",
      "p2p_create-reserve-1"),
    TALER_TESTING_cmd_purse_poll_finish (
      "push-merge-purse-poll-finish",
      GNUNET_TIME_relative_multiply (
        GNUNET_TIME_UNIT_SECONDS,
        5),
      "push-poll-purse-before-merge"),
    TALER_TESTING_cmd_status (
      "push-check-post-merge-reserve-balance-get",
      "p2p_create-reserve-1",
      "EUR:1.03",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_reserve_status (
      "push-check-post-merge-reserve-balance-post",
      "p2p_create-reserve-1",
      "EUR:1.03",
      MHD_HTTP_OK),

    TALER_TESTING_cmd_end ()
  };
  struct TALER_TESTING_Command pull[] = {
    TALER_TESTING_cmd_purse_create_with_reserve (
      "purse-create-with-reserve",
      MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS,
      "{\"amount\":\"EUR:1\",\"summary\":\"ice cream\"}",
      true /* upload contract */,
      false /* pay purse fee */,
      GNUNET_TIME_UNIT_MINUTES, /* expiration */
      "p2p_create-reserve-3"),
    TALER_TESTING_cmd_check_kyc_get ("check-kyc-purse-create",
                                     "purse-create-with-reserve",
                                     MHD_HTTP_ACCEPTED),
    TALER_TESTING_cmd_proof_kyc_oauth2 ("p2p_proof-kyc-pull",
                                        "purse-create-with-reserve",
                                        "kyc-provider-test-oauth2",
                                        "pass",
                                        "state",
                                        MHD_HTTP_SEE_OTHER),
    TALER_TESTING_cmd_purse_create_with_reserve (
      "purse-create-with-reserve",
      MHD_HTTP_OK,
      "{\"amount\":\"EUR:1\",\"summary\":\"ice cream\"}",
      true /* upload contract */,
      false /* pay purse fee */,
      GNUNET_TIME_UNIT_MINUTES, /* expiration */
      "p2p_create-reserve-3"),
    TALER_TESTING_cmd_contract_get (
      "pull-get-contract",
      MHD_HTTP_OK,
      false, /* for deposit */
      "purse-create-with-reserve"),
    TALER_TESTING_cmd_purse_poll (
      "pull-poll-purse-before-deposit",
      MHD_HTTP_OK,
      "purse-create-with-reserve",
      "EUR:1",
      false,
      GNUNET_TIME_UNIT_MINUTES),
    TALER_TESTING_cmd_purse_deposit_coins (
      "purse-deposit-coins",
      MHD_HTTP_OK,
      0 /* min age */,
      "purse-create-with-reserve",
      "p2p_withdraw-coin-1",
      "EUR:1.01",
      NULL),
    TALER_TESTING_cmd_purse_poll_finish (
      "pull-deposit-purse-poll-finish",
      GNUNET_TIME_relative_multiply (
        GNUNET_TIME_UNIT_SECONDS,
        5),
      "pull-poll-purse-before-deposit"),
    TALER_TESTING_cmd_status (
      "pull-check-post-merge-reserve-balance-get",
      "p2p_create-reserve-3",
      "EUR:1.02",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_reserve_status (
      "push-check-post-merge-reserve-balance-post",
      "p2p_create-reserve-3",
      "EUR:1.02",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };


  struct TALER_TESTING_Command commands[] = {
    TALER_TESTING_cmd_exec_offline_sign_fees ("offline-sign-fees",
                                              CONFIG_FILE,
                                              "EUR:0.01",
                                              "EUR:0.01",
                                              "EUR:0.01"),
    TALER_TESTING_cmd_exec_offline_sign_global_fees ("offline-sign-global-fees",
                                                     CONFIG_FILE,
                                                     "EUR:0.01",
                                                     "EUR:0.01",
                                                     "EUR:0.01",
                                                     "EUR:0.01",
                                                     GNUNET_TIME_UNIT_MINUTES,
                                                     GNUNET_TIME_UNIT_MINUTES,
                                                     GNUNET_TIME_UNIT_DAYS,
                                                     1),
    TALER_TESTING_cmd_auditor_add ("add-auditor-OK",
                                   MHD_HTTP_NO_CONTENT,
                                   false),
    TALER_TESTING_cmd_wire_add ("add-wire-account",
                                "payto://x-taler-bank/localhost/2?receiver-name=2",
                                MHD_HTTP_NO_CONTENT,
                                false),
    TALER_TESTING_cmd_exec_offline_sign_keys ("offline-sign-future-keys",
                                              CONFIG_FILE),
    TALER_TESTING_cmd_check_keys_pull_all_keys ("refetch /keys",
                                                2),
    TALER_TESTING_cmd_batch ("withdraw",
                             withdraw),
    TALER_TESTING_cmd_batch ("spend",
                             spend),
    TALER_TESTING_cmd_batch ("track",
                             track),
    TALER_TESTING_cmd_batch ("withdraw-kyc",
                             withdraw_kyc),
    TALER_TESTING_cmd_batch ("wallet-kyc",
                             wallet_kyc),
    TALER_TESTING_cmd_batch ("p2p_withdraw",
                             p2p_withdraw),
    TALER_TESTING_cmd_batch ("push",
                             push),
    TALER_TESTING_cmd_batch ("pull",
                             pull),
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
  (void) argc;
  (void) argv;
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
