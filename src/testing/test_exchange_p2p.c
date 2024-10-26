/*
  This file is part of TALER
  Copyright (C) 2014--2024 Taler Systems SA

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
 * @file testing/test_exchange_p2p.c
 * @brief testcase to test exchange's P2P payments
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_attributes.h"
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
struct TALER_TESTING_Credentials cred;

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
        TALER_TESTING_cmd_exec_wirewatch2 (label, config_file, \
                                           "exchange-account-2")

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
#define CMD_TRANSFER_TO_EXCHANGE(label,amount)                  \
        TALER_TESTING_cmd_admin_add_incoming (label, amount,    \
                                              &cred.ba,         \
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
  /**
   * Test withdrawal plus spending.
   */
  struct TALER_TESTING_Command withdraw[] = {
    /**
     * Move money to the exchange's bank account.
     */
    CMD_TRANSFER_TO_EXCHANGE (
      "create-reserve-1",
      "EUR:5.04"),
    CMD_TRANSFER_TO_EXCHANGE (
      "create-reserve-2",
      "EUR:5.01"),
    TALER_TESTING_cmd_reserve_poll (
      "poll-reserve-1",
      "create-reserve-1",
      "EUR:5.04",
      GNUNET_TIME_UNIT_MINUTES,
      MHD_HTTP_OK),
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "check-create-reserve-1",
      "EUR:5.04",
      cred.user42_payto,
      cred.exchange_payto,
      "create-reserve-1"),
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "check-create-reserve-2",
      "EUR:5.01",
      cred.user42_payto,
      cred.exchange_payto,
      "create-reserve-2"),
    /**
     * Make a reserve exist, according to the previous
     * transfer.
     */
    CMD_EXEC_WIREWATCH ("wirewatch-1"),
    TALER_TESTING_cmd_reserve_poll_finish (
      "finish-poll-reserve-1",
      GNUNET_TIME_UNIT_SECONDS,
      "poll-reserve-1"),
    /**
     * Withdraw EUR:5.
     */
    TALER_TESTING_cmd_withdraw_amount (
      "withdraw-coin-1",
      "create-reserve-1",
      "EUR:5",
      0,    /* age restriction off */
      MHD_HTTP_OK),
    /**
     * Check the reserve is depleted.
     */
    TALER_TESTING_cmd_status (
      "status-1",
      "create-reserve-1",
      "EUR:0.03",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };
  struct TALER_TESTING_Command push[] = {
    TALER_TESTING_cmd_purse_create_with_deposit (
      "purse-with-deposit-for-delete",
      MHD_HTTP_OK,
      "{\"amount\":\"EUR:1\",\"summary\":\"ice cream\"}",
      true, /* upload contract */
      GNUNET_TIME_UNIT_MINUTES, /* expiration */
      "withdraw-coin-1",
      "EUR:1.01",
      NULL),
    TALER_TESTING_cmd_purse_delete (
      "purse-with-deposit-delete",
      MHD_HTTP_NO_CONTENT,
      "purse-with-deposit-for-delete"),
    TALER_TESTING_cmd_purse_create_with_deposit (
      "purse-with-deposit",
      MHD_HTTP_OK,
      "{\"amount\":\"EUR:0.99\",\"summary\":\"ice cream\"}",
      true, /* upload contract */
      GNUNET_TIME_UNIT_MINUTES, /* expiration */
      "withdraw-coin-1",
      "EUR:1.00",
      NULL),
    TALER_TESTING_cmd_purse_poll (
      "push-poll-purse-before-merge",
      MHD_HTTP_OK,
      "purse-with-deposit",
      "EUR:0.99",
      true,
      GNUNET_TIME_UNIT_MINUTES),
    TALER_TESTING_cmd_contract_get (
      "push-get-contract",
      MHD_HTTP_OK,
      true, /* for merge */
      "purse-with-deposit"),
    TALER_TESTING_cmd_purse_merge (
      "purse-merge-into-reserve",
      MHD_HTTP_OK,
      "push-get-contract",
      "create-reserve-1"),
    TALER_TESTING_cmd_purse_poll_finish (
      "push-merge-purse-poll-finish",
      GNUNET_TIME_relative_multiply (
        GNUNET_TIME_UNIT_SECONDS,
        5),
      "push-poll-purse-before-merge"),
    TALER_TESTING_cmd_status (
      "push-check-post-merge-reserve-balance-get",
      "create-reserve-1",
      "EUR:1.02",
      MHD_HTTP_OK),
    /* POST history doesn't yet support P2P transfers */
    TALER_TESTING_cmd_reserve_history (
      "push-check-post-merge-reserve-balance-post",
      "create-reserve-1",
      "EUR:1.02",
      MHD_HTTP_OK),
    /* Test conflicting merge */
    TALER_TESTING_cmd_purse_merge (
      "purse-merge-into-reserve",
      MHD_HTTP_CONFLICT,
      "push-get-contract",
      "create-reserve-2"),

    TALER_TESTING_cmd_end ()
  };
  struct TALER_TESTING_Command pull[] = {
    TALER_TESTING_cmd_purse_create_with_reserve (
      "purse-create-with-reserve",
      MHD_HTTP_OK,
      "{\"amount\":\"EUR:1\",\"summary\":\"ice cream\"}",
      true /* upload contract */,
      true /* pay purse fee */,
      GNUNET_TIME_UNIT_MINUTES, /* expiration */
      "create-reserve-1"),
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
      "withdraw-coin-1",
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
      "create-reserve-1",
      "EUR:2.02",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_reserve_history (
      "push-check-post-merge-reserve-balance-post",
      "create-reserve-1",
      "EUR:2.02",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_purse_deposit_coins (
      "purse-deposit-coins-idempotent",
      MHD_HTTP_OK,
      0 /* min age */,
      "purse-create-with-reserve",
      "withdraw-coin-1",
      "EUR:1.01",
      NULL),
    /* create 2nd purse for a deposit conflict */
    TALER_TESTING_cmd_purse_create_with_reserve (
      "purse-create-with-reserve-2",
      MHD_HTTP_OK,
      "{\"amount\":\"EUR:4\",\"summary\":\"beer\"}",
      true /* upload contract */,
      true /* pay purse fee */,
      GNUNET_TIME_UNIT_MINUTES, /* expiration */
      "create-reserve-1"),
    TALER_TESTING_cmd_purse_deposit_coins (
      "purse-deposit-coins-conflict",
      MHD_HTTP_CONFLICT,
      0 /* min age */,
      "purse-create-with-reserve-2",
      "withdraw-coin-1",
      "EUR:4.01",
      NULL),
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command expire[] = {
    TALER_TESTING_cmd_purse_create_with_reserve (
      "purse-create-with-reserve-expire",
      MHD_HTTP_OK,
      "{\"amount\":\"EUR:2\",\"summary\":\"ice cream\"}",
      true /* upload contract */,
      true /* pay purse fee */,
      GNUNET_TIME_relative_multiply (
        GNUNET_TIME_UNIT_SECONDS,
        1), /* expiration */
      "create-reserve-1"),
    TALER_TESTING_cmd_purse_poll (
      "pull-poll-purse-before-expire",
      MHD_HTTP_GONE,
      "purse-create-with-reserve-expire",
      "EUR:1",
      false,
      GNUNET_TIME_UNIT_MINUTES),
    TALER_TESTING_cmd_purse_create_with_deposit (
      "purse-with-deposit-expire",
      MHD_HTTP_OK,
      "{\"amount\":\"EUR:1\",\"summary\":\"ice cream\"}",
      true, /* upload contract */
      GNUNET_TIME_relative_multiply (
        GNUNET_TIME_UNIT_SECONDS,
        1), /* expiration */
      "withdraw-coin-1",
      "EUR:1.02",
      NULL),
    TALER_TESTING_cmd_purse_poll (
      "push-poll-purse-before-expire",
      MHD_HTTP_GONE,
      "purse-with-deposit-expire",
      "EUR:1",
      true, /* wait for merge */
      GNUNET_TIME_UNIT_MINUTES),
    /* This should fail, as too much of the coin
       is already spend / in a purse */
    TALER_TESTING_cmd_purse_create_with_deposit (
      "purse-with-deposit-overspending",
      MHD_HTTP_CONFLICT,
      "{\"amount\":\"EUR:2\",\"summary\":\"ice cream\"}",
      true, /* upload contract */
      GNUNET_TIME_relative_multiply (
        GNUNET_TIME_UNIT_SECONDS,
        1), /* expiration */
      "withdraw-coin-1",
      "EUR:2.01",
      NULL),
    TALER_TESTING_cmd_sleep (
      "sleep",
      2 /* seconds */),
    TALER_TESTING_cmd_exec_expire (
      "exec-expire",
      config_file),
    TALER_TESTING_cmd_purse_poll_finish (
      "push-merge-purse-poll-finish-expire",
      GNUNET_TIME_relative_multiply (
        GNUNET_TIME_UNIT_SECONDS,
        15),
      "push-poll-purse-before-expire"),
    TALER_TESTING_cmd_purse_poll_finish (
      "pull-deposit-purse-poll-expire-finish",
      GNUNET_TIME_relative_multiply (
        GNUNET_TIME_UNIT_SECONDS,
        15),
      "pull-poll-purse-before-expire"),
    /* coin was refunded, so now this should be OK */
    /* This should fail, as too much of the coin
       is already spend / in a purse */
    TALER_TESTING_cmd_purse_create_with_deposit (
      "purse-with-deposit-refunded",
      MHD_HTTP_OK,
      "{\"amount\":\"EUR:2\",\"summary\":\"ice cream\"}",
      true, /* upload contract */
      GNUNET_TIME_relative_multiply (
        GNUNET_TIME_UNIT_SECONDS,
        1), /* expiration */
      "withdraw-coin-1",
      "EUR:2.01",
      NULL),
    TALER_TESTING_cmd_end ()
  };
  struct TALER_TESTING_Command reserves[] = {
    CMD_TRANSFER_TO_EXCHANGE (
      "create-reserve-100",
      "EUR:1.04"),
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "check-create-reserve-100",
      "EUR:1.04",
      cred.user42_payto,
      cred.exchange_payto,
      "create-reserve-100"),
    CMD_TRANSFER_TO_EXCHANGE (
      "create-reserve-101",
      "EUR:1.04"),
    TALER_TESTING_cmd_check_bank_admin_transfer (
      "check-create-reserve-101",
      "EUR:1.04",
      cred.user42_payto,
      cred.exchange_payto,
      "create-reserve-101"),
    CMD_EXEC_WIREWATCH ("wirewatch-100"),
    TALER_TESTING_cmd_withdraw_amount (
      "withdraw-coin-100",
      "create-reserve-100",
      "EUR:1",
      0,       /* age restriction off */
      MHD_HTTP_OK),
    TALER_TESTING_cmd_reserve_open (
      "reserve-open-101-fail",
      "create-reserve-101",
      "EUR:0",
      GNUNET_TIME_UNIT_YEARS,
      5,     /* min purses */
      MHD_HTTP_PAYMENT_REQUIRED,
      NULL,
      NULL),
    TALER_TESTING_cmd_reserve_open (
      "reserve-open-101-ok-a",
      "create-reserve-101",
      "EUR:0.01",
      GNUNET_TIME_UNIT_MONTHS,
      1,                               /* min purses */
      MHD_HTTP_OK,
      NULL,
      NULL),
    TALER_TESTING_cmd_status (
      "status-101-open-paid",
      "create-reserve-101",
      "EUR:1.03",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_reserve_open (
      "reserve-open-101-ok-b",
      "create-reserve-101",
      "EUR:0",
      GNUNET_TIME_UNIT_MONTHS,
      2,            /* min purses */
      MHD_HTTP_OK,
      "withdraw-coin-100",
      "EUR:0.03",  /* 0.02 for the reserve open, 0.01 for deposit fee */
      NULL,
      NULL),
    /* Use purse creation with purse quota here */
    TALER_TESTING_cmd_purse_create_with_reserve (
      "purse-create-with-reserve-101-a",
      MHD_HTTP_OK,
      "{\"amount\":\"EUR:1\",\"summary\":\"ice cream\"}",
      true /* upload contract */,
      false /* pay purse fee */,
      GNUNET_TIME_UNIT_MINUTES, /* expiration */
      "create-reserve-101"),
    TALER_TESTING_cmd_purse_create_with_reserve (
      "purse-create-with-reserve-101-b",
      MHD_HTTP_OK,
      "{\"amount\":\"EUR:1\",\"summary\":\"ice cream\"}",
      true /* upload contract */,
      false /* pay purse fee */,
      GNUNET_TIME_UNIT_MINUTES, /* expiration */
      "create-reserve-101"),
    TALER_TESTING_cmd_purse_create_with_reserve (
      "purse-create-with-reserve-101-fail",
      MHD_HTTP_CONFLICT,
      "{\"amount\":\"EUR:1\",\"summary\":\"ice cream\"}",
      true /* upload contract */,
      false /* pay purse fee */,
      GNUNET_TIME_UNIT_MINUTES, /* expiration */
      "create-reserve-101"),
    TALER_TESTING_cmd_reserve_get_attestable (
      "reserve-101-attestable",
      "create-reserve-101",
      MHD_HTTP_NOT_FOUND,
      NULL),
    TALER_TESTING_cmd_reserve_get_attestable (
      "reserve-101-attest",
      "create-reserve-101",
      MHD_HTTP_NOT_FOUND,
      "nx-attribute-name",
      NULL),
    TALER_TESTING_cmd_oauth_with_birthdate (
      "start-oauth-service",
      "2015-00-00",
      6666),
    TALER_TESTING_cmd_reserve_close (
      "reserve-101-close-kyc",
      "create-reserve-101",
      /* 42b => not to origin */
      "payto://x-taler-bank/localhost/42b?receiver-name=42b",
      MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS),
    TALER_TESTING_cmd_admin_add_kycauth (
      "setup-account-key",
      "EUR:0.01",
      &cred.ba,
      "payto://x-taler-bank/localhost/42b?receiver-name=42b",
      NULL /* create new key */),
    CMD_EXEC_WIREWATCH (
      "import-kyc-account"),
    TALER_TESTING_cmd_check_kyc_get (
      "check-kyc-close-pending",
      "reserve-101-close-kyc",
      "setup-account-key",
      TALER_EXCHANGE_KLPT_KYC_AUTH_TRANSFER,
      MHD_HTTP_ACCEPTED),
    TALER_TESTING_cmd_get_kyc_info (
      "get-kyc-info",
      "check-kyc-close-pending",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_post_kyc_start (
      "start-kyc-process",
      "get-kyc-info",
      0,
      MHD_HTTP_OK),
    TALER_TESTING_cmd_proof_kyc_oauth2 (
      "proof-close-kyc",
      "reserve-101-close-kyc",
      "test-oauth2",
      "pass",
      MHD_HTTP_SEE_OTHER),
    TALER_TESTING_cmd_check_kyc_get (
      "check-kyc-close-ok",
      "reserve-101-close-kyc",
      "setup-account-key",
      TALER_EXCHANGE_KLPT_KYC_OK,
      MHD_HTTP_OK),
    /* Now it should pass */
    TALER_TESTING_cmd_reserve_close (
      "reserve-101-close",
      "create-reserve-101",
      /* 42b => not to origin */
      "payto://x-taler-bank/localhost/42b?receiver-name=42b",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_exec_closer (
      "close-reserves-101",
      config_file,
      "EUR:1.02",
      "EUR:0.01",
      "create-reserve-101"),
    TALER_TESTING_cmd_exec_transfer (
      "close-reserves-101-transfer",
      config_file),
    TALER_TESTING_cmd_status (
      "reserve-101-closed-status",
      "create-reserve-101",
      "EUR:0",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };

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
    TALER_TESTING_cmd_batch ("withdraw",
                             withdraw),
    TALER_TESTING_cmd_batch ("push",
                             push),
    TALER_TESTING_cmd_batch ("pull",
                             pull),
    TALER_TESTING_cmd_batch ("expire",
                             expire),
    TALER_TESTING_cmd_batch ("reserves",
                             reserves),
    /* End the suite. */
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
    uses_cs = (0 == strcmp (cipher, "cs"));
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


/* end of test_exchange_p2p.c */
