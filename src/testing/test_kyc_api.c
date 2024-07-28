/*
  This file is part of TALER
  Copyright (C) 2014-2024 Taler Systems SA

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
#include "taler_attributes.h"
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
 * Our credentials.
 */
struct TALER_TESTING_Credentials cred;


/**
 * Execute the taler-exchange-wirewatch command with
 * our configuration file.
 *
 * @param label label to use for the command.
 */
#define CMD_EXEC_WIREWATCH(label)           \
        TALER_TESTING_cmd_exec_wirewatch2 ( \
          label,                            \
          CONFIG_FILE,                      \
          "exchange-account-2")

/**
 * Execute the taler-exchange-aggregator, closer and transfer commands with
 * our configuration file.
 *
 * @param label label to use for the command.
 */
#define CMD_EXEC_AGGREGATOR(label)                   \
        TALER_TESTING_cmd_sleep (                    \
          label "-sleep", 1),                        \
        TALER_TESTING_cmd_exec_aggregator_with_kyc ( \
          label, CONFIG_FILE),                       \
        TALER_TESTING_cmd_exec_transfer (            \
          label, CONFIG_FILE)

/**
 * Run wire transfer of funds from some user's account to the
 * exchange.
 *
 * @param label label to use for the command.
 * @param amount amount to transfer, i.e. "EUR:1"
 */
#define CMD_TRANSFER_TO_EXCHANGE(label,amount) \
        TALER_TESTING_cmd_admin_add_incoming ( \
          label,                               \
          amount,                              \
          &cred.ba,                            \
          cred.user42_payto)

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
  struct TALER_TESTING_Command withdraw[] = {
    CMD_TRANSFER_TO_EXCHANGE (
      "create-reserve-1",
      "EUR:15.02"),
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "check-create-reserve-1",
      "EUR:15.02",
      cred.user42_payto,
      cred.exchange_payto,
      "create-reserve-1"),
    CMD_EXEC_WIREWATCH ("wirewatch-1"),
    TALER_TESTING_cmd_withdraw_amount (
      "withdraw-coin-1-no-kyc",
      "create-reserve-1",
      "EUR:10",
      0,    /* age restriction off */
      MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS),
    TALER_TESTING_cmd_withdraw_amount (
      "withdraw-coin-1",
      "create-reserve-1",
      "EUR:5",
      0,    /* age restriction off */
      MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };
  /**
   * Test withdraw with KYC.
   */
  struct TALER_TESTING_Command withdraw_kyc[] = {
    CMD_EXEC_WIREWATCH ("wirewatch-1"),
    TALER_TESTING_cmd_withdraw_amount (
      "withdraw-coin-1-lacking-kyc",
      "create-reserve-1",
      "EUR:5",
      0,     /* age restriction off */
      MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS),
    TALER_TESTING_cmd_check_kyc_get (
      "check-kyc-withdraw",
      "withdraw-coin-1-lacking-kyc",
      "create-reserve-1", /* CHECK! */
      MHD_HTTP_ACCEPTED),
    TALER_TESTING_cmd_get_kyc_info (
      "get-kyc-info-withdraw",
      "check-kyc-withdraw",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_post_kyc_start (
      "start-kyc-process-withdraw",
      "get-kyc-info-withdraw",
      0,
      MHD_HTTP_OK),
    TALER_TESTING_cmd_proof_kyc_oauth2 (
      "proof-kyc-withdraw-oauth2",
      "start-kyc-process-withdraw",
      "test-oauth2",
      "pass",
      MHD_HTTP_SEE_OTHER),
    TALER_TESTING_cmd_withdraw_amount (
      "withdraw-coin-1-with-kyc",
      "create-reserve-1",
      "EUR:5",
      0,      /* age restriction off */
      MHD_HTTP_OK),
    /* Attestations above are bound to the originating *bank* account,
       not to the reserve (!). Hence, they are NOT found here! */
    TALER_TESTING_cmd_reserve_get_attestable (
      "reserve-get-attestable",
      "create-reserve-1",
      MHD_HTTP_NOT_FOUND,
      NULL),
    TALER_TESTING_cmd_end ()
  };
  struct TALER_TESTING_Command spend[] = {
    TALER_TESTING_cmd_deposit (
      "deposit-simple",
      "withdraw-coin-1",
      0,
      cred.user43_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:5",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposits_get (
      "track-deposit",
      "deposit-simple",
      0,
      MHD_HTTP_ACCEPTED,
      NULL),
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command track[] = {
    CMD_EXEC_AGGREGATOR ("run-aggregator-before-kyc"),
    TALER_TESTING_cmd_check_bank_empty (
      "check_bank_empty-no-kyc"),
    TALER_TESTING_cmd_deposits_get (
      "track-deposit-kyc-ready",
      "deposit-simple",
      0,
      MHD_HTTP_ACCEPTED,
      NULL),
    TALER_TESTING_cmd_admin_add_kycauth (
      "setup-account-key-deposit",
      "EUR:0.01",
      &cred.ba,
      cred.user43_payto,
      NULL /* create new key */),
    CMD_EXEC_WIREWATCH (
      "import-kyc-account-deposit"),
    TALER_TESTING_cmd_check_kyc_get (
      "check-kyc-deposit",
      "track-deposit-kyc-ready",
      "setup-account-key-deposit",
      MHD_HTTP_ACCEPTED),
    TALER_TESTING_cmd_get_kyc_info (
      "get-kyc-info-deposit",
      "check-kyc-deposit",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_post_kyc_start (
      "start-kyc-process-deposit",
      "get-kyc-info-deposit",
      0,
      MHD_HTTP_OK),
    TALER_TESTING_cmd_proof_kyc_oauth2 (
      "proof-kyc-no-service",
      "start-kyc-process-deposit",
      "test-oauth2",
      "bad",
      MHD_HTTP_BAD_GATEWAY),
    TALER_TESTING_cmd_oauth (
      "start-oauth-service",
      6666),
    TALER_TESTING_cmd_proof_kyc_oauth2 (
      "proof-kyc-fail",
      "start-kyc-process-deposit",
      "test-oauth2",
      "bad",
      MHD_HTTP_FORBIDDEN),
    TALER_TESTING_cmd_check_kyc_get (
      "check-kyc-deposit-again",
      "track-deposit-kyc-ready",
      "FIXME",
      MHD_HTTP_ACCEPTED),
    TALER_TESTING_cmd_proof_kyc_oauth2 (
      "proof-kyc-pass",
      "start-kyc-process-deposit",
      "test-oauth2",
      "pass",
      MHD_HTTP_SEE_OTHER),
    CMD_EXEC_AGGREGATOR (
      "run-aggregator-after-kyc"),
    TALER_TESTING_cmd_check_bank_transfer (
      "check_bank_transfer-499c",
      cred.exchange_url,
      "EUR:4.98",
      cred.exchange_payto,
      cred.user43_payto),
    TALER_TESTING_cmd_check_bank_empty (
      "check_bank_empty"),
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command wallet_kyc[] = {
    TALER_TESTING_cmd_wallet_kyc_get (
      "wallet-kyc-fail",
      NULL,
      "EUR:1000000",
      MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS),
    TALER_TESTING_cmd_check_kyc_get (
      "check-kyc-wallet",
      "wallet-kyc-fail",
      "FIXME",
      MHD_HTTP_ACCEPTED),
    TALER_TESTING_cmd_proof_kyc_oauth2 (
      "proof-wallet-kyc",
      "wallet-kyc-fail",
      "kyc-provider-test-oauth2",
      "pass",
      MHD_HTTP_SEE_OTHER),
    TALER_TESTING_cmd_check_kyc_get (
      "wallet-kyc-check",
      "wallet-kyc-fail",
      "FIXME",
      MHD_HTTP_NO_CONTENT),
    TALER_TESTING_cmd_reserve_get_attestable (
      "wallet-get-attestable",
      "wallet-kyc-fail",
      MHD_HTTP_OK,
      TALER_ATTRIBUTE_FULL_NAME,
      NULL),
    TALER_TESTING_cmd_reserve_attest (
      "wallet-get-attest",
      "wallet-kyc-fail",
      MHD_HTTP_OK,
      TALER_ATTRIBUTE_FULL_NAME,
      NULL),
    TALER_TESTING_cmd_end ()
  };

  /**
   * Test withdrawal for P2P
   */
  struct TALER_TESTING_Command p2p_withdraw[] = {
    /**
     * Move money to the exchange's bank account.
     */
    CMD_TRANSFER_TO_EXCHANGE (
      "p2p_create-reserve-1",
      "EUR:5.04"),
    CMD_TRANSFER_TO_EXCHANGE (
      "p2p_create-reserve-2",
      "EUR:5.01"),
    CMD_TRANSFER_TO_EXCHANGE (
      "p2p_create-reserve-3",
      "EUR:0.03"),
    TALER_TESTING_cmd_reserve_poll (
      "p2p_poll-reserve-1",
      "p2p_create-reserve-1",
      "EUR:5.04",
      GNUNET_TIME_UNIT_MINUTES,
      MHD_HTTP_OK),
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "p2p_check-create-reserve-1",
      "EUR:5.04",
      cred.user42_payto,
      cred.exchange_payto,
      "p2p_create-reserve-1"),
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "p2p_check-create-reserve-2",
      "EUR:5.01",
      cred.user42_payto,
      cred.exchange_payto,
      "p2p_create-reserve-2"),
    /**
     * Make a reserve exist, according to the previous
     * transfer.
     */
    CMD_EXEC_WIREWATCH ("p2p_wirewatch-1"),
    TALER_TESTING_cmd_reserve_poll_finish (
      "p2p_finish-poll-reserve-1",
      GNUNET_TIME_UNIT_SECONDS,
      "p2p_poll-reserve-1"),
    /**
     * Withdraw EUR:5.
     */
    TALER_TESTING_cmd_withdraw_amount (
      "p2p_withdraw-coin-1",
      "p2p_create-reserve-1",
      "EUR:5",
      0,      /* age restriction off */
      MHD_HTTP_OK),
    /**
     * Check the reserve is depleted.
     */
    TALER_TESTING_cmd_status (
      "p2p_status-1",
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
    TALER_TESTING_cmd_coin_history (
      "coin-history-purse-with-deposit",
      "p2p_withdraw-coin-1#0",
      "EUR:3.99",
      MHD_HTTP_OK),
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
    TALER_TESTING_cmd_check_kyc_get (
      "check-kyc-purse-merge",
      "purse-merge-into-reserve",
      "p2p_create-reserve-1", /* CHECK! */
      MHD_HTTP_ACCEPTED),
    TALER_TESTING_cmd_get_kyc_info (
      "get-kyc-info-purse-merge-into-reserve",
      "check-kyc-purse-merge",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_post_kyc_start (
      "start-kyc-process-purse-merge-into-reserve",
      "get-kyc-info-purse-merge-into-reserve",
      0,
      MHD_HTTP_OK),
    TALER_TESTING_cmd_proof_kyc_oauth2 (
      "p2p_proof-kyc",
      "start-kyc-process-purse-merge-into-reserve",
      "test-oauth2",
      "pass",
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
    TALER_TESTING_cmd_reserve_history (
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
      true /* pay purse fee */,
      GNUNET_TIME_UNIT_MINUTES, /* expiration */
      "p2p_create-reserve-3"),
    TALER_TESTING_cmd_check_kyc_get (
      "check-kyc-purse-create",
      "purse-create-with-reserve",
      "purse-create-with-reserve", /* correct!? */
      MHD_HTTP_ACCEPTED),
    TALER_TESTING_cmd_get_kyc_info (
      "get-kyc-info-purse-create",
      "check-kyc-purse-create",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_post_kyc_start (
      "start-kyc-process-purse-create",
      "get-kyc-info-purse-create",
      0,
      MHD_HTTP_OK),
    TALER_TESTING_cmd_proof_kyc_oauth2 (
      "p2p_proof-kyc-pull",
      "purse-create-with-reserve",
      "test-oauth2",
      "pass",
      MHD_HTTP_SEE_OTHER),
    TALER_TESTING_cmd_purse_create_with_reserve (
      "purse-create-with-reserve",
      MHD_HTTP_OK,
      "{\"amount\":\"EUR:1\",\"summary\":\"ice cream\"}",
      true /* upload contract */,
      true /* pay purse fee */,
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
    TALER_TESTING_cmd_coin_history (
      "coin-history-purse-pull-deposit",
      "p2p_withdraw-coin-1#0",
      "EUR:2.98",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_purse_poll_finish (
      "pull-deposit-purse-poll-finish",
      GNUNET_TIME_relative_multiply (
        GNUNET_TIME_UNIT_SECONDS,
        5),
      "pull-poll-purse-before-deposit"),
    TALER_TESTING_cmd_status (
      "pull-check-post-merge-reserve-balance-get-2",
      "p2p_create-reserve-3",
      "EUR:1.03",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_reserve_history (
      "push-check-post-merge-reserve-balance-post-2",
      "p2p_create-reserve-3",
      "EUR:1.03",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };
  struct TALER_TESTING_Command aml[] = {
    /* Trigger something upon which an AML officer could act */
#if FIXME
    TALER_TESTING_cmd_wallet_kyc_get (
      "wallet-trigger-kyc-for-aml",
      NULL,
      "EUR:1000",
      MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS),
#endif
    TALER_TESTING_cmd_set_officer (
      "create-aml-officer-1",
      NULL,
      "Peter Falk",
      true,
      false),
#if FIXME
    TALER_TESTING_cmd_check_aml_decisions (
      "check-decisions-none-normal",
      "create-aml-officer-1",
      TALER_AML_NORMAL,
      MHD_HTTP_NO_CONTENT),
    TALER_TESTING_cmd_check_aml_decisions (
      "check-decisions-none-pending",
      "create-aml-officer-1",
      TALER_AML_PENDING,
      MHD_HTTP_NO_CONTENT),
    TALER_TESTING_cmd_check_aml_decisions (
      "check-decisions-none-frozen",
      "create-aml-officer-1",
      TALER_AML_FROZEN,
      MHD_HTTP_NO_CONTENT),
#endif
    TALER_TESTING_cmd_sleep (
      "sleep-1a",
      1),
    TALER_TESTING_cmd_set_officer (
      "create-aml-officer-1-disable",
      "create-aml-officer-1",
      "Peter Falk",
      true,
      true),
    /* Test that we are not allowed to take AML decisions as our
       AML staff account is on read-only */
#if FIXME
    TALER_TESTING_cmd_take_aml_decision (
      "aml-decide-while-disabled",
      "create-aml-officer-1",
      "wallet-trigger-kyc-for-aml",
      "EUR:10000",
      "party time",
      TALER_AML_NORMAL,
      NULL,
      MHD_HTTP_FORBIDDEN),
    /* Check that no decision was taken, but that we are allowed
       to read this information */
    TALER_TESTING_cmd_check_aml_decision (
      "check-aml-decision-empty",
      "create-aml-officer-1",
      "aml-decide-while-disabled",
      MHD_HTTP_NO_CONTENT),
#endif
    TALER_TESTING_cmd_sleep (
      "sleep-1b",
      1),
    TALER_TESTING_cmd_set_officer (
      "create-aml-officer-1-enable",
      "create-aml-officer-1",
      "Peter Falk",
      true,
      false),
#if FIXME
    TALER_TESTING_cmd_take_aml_decision (
      "aml-decide",
      "create-aml-officer-1",
      "wallet-trigger-kyc-for-aml",
      "EUR:10000",
      "party time",
      TALER_AML_NORMAL,
      NULL,
      MHD_HTTP_NO_CONTENT),
    TALER_TESTING_cmd_check_aml_decisions (
      "check-decisions-one-normal",
      "create-aml-officer-1",
      TALER_AML_NORMAL,
      MHD_HTTP_OK),
    TALER_TESTING_cmd_check_aml_decisions (
      "check-decisions-zero-frozen",
      "create-aml-officer-1",
      TALER_AML_FROZEN,
      MHD_HTTP_NO_CONTENT),
    TALER_TESTING_cmd_check_aml_decision (
      "check-aml-decision",
      "create-aml-officer-1",
      "aml-decide",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_sleep (
      "sleep-1c",
      1),
    TALER_TESTING_cmd_take_aml_decision (
      "aml-decide-freeze",
      "create-aml-officer-1",
      "wallet-trigger-kyc-for-aml",
      "EUR:1000",
      "party over",
      TALER_AML_FROZEN,
      NULL,
      MHD_HTTP_NO_CONTENT),
    TALER_TESTING_cmd_check_aml_decisions (
      "check-decisions-one-frozen",
      "create-aml-officer-1",
      TALER_AML_FROZEN,
      MHD_HTTP_OK),
    TALER_TESTING_cmd_check_aml_decisions (
      "check-decisions-zero-normal",
      "create-aml-officer-1",
      TALER_AML_NORMAL,
      MHD_HTTP_NO_CONTENT),
    TALER_TESTING_cmd_sleep (
      "sleep-1d",
      1),
#endif
    TALER_TESTING_cmd_set_officer (
      "create-aml-officer-1-disable",
      "create-aml-officer-1",
      "Peter Falk",
      false,
      true),
    /* Test that we are NOT allowed to read AML decisions now that
       our AML staff account is disabled */
#if FIXME
    TALER_TESTING_cmd_check_aml_decision (
      "check-aml-decision-disabled",
      "create-aml-officer-1",
      "aml-decide",
      MHD_HTTP_FORBIDDEN),
#endif
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command commands[] = {
    TALER_TESTING_cmd_run_fakebank (
      "run-fakebank",
      cred.cfg,
      "exchange-account-2"),
    TALER_TESTING_cmd_system_start (
      "start-taler",
      CONFIG_FILE,
      "-e",
      NULL),
    TALER_TESTING_cmd_get_exchange (
      "get-exchange",
      cred.cfg,
      NULL,
      true,
      true),
    TALER_TESTING_cmd_batch (
      "withdraw",
      withdraw),
    TALER_TESTING_cmd_batch (
      "spend",
      spend),
    TALER_TESTING_cmd_batch (
      "track",
      track),
    TALER_TESTING_cmd_batch (
      "withdraw-kyc",
      withdraw_kyc),
    TALER_TESTING_cmd_batch (
      "wallet-kyc",
      wallet_kyc),
    TALER_TESTING_cmd_batch (
      "p2p_withdraw",
      p2p_withdraw),
    TALER_TESTING_cmd_batch (
      "push",
      push),
    TALER_TESTING_cmd_batch (
      "pull",
      pull),
    TALER_TESTING_cmd_batch ("aml",
                             aml),
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
  return TALER_TESTING_main (
    argv,
    "INFO",
    CONFIG_FILE,
    "exchange-account-2",
    TALER_TESTING_BS_FAKEBANK,
    &cred,
    &run,
    NULL);
}


/* end of test_kyc_api.c */
