/*
  This file is part of TALER
  Copyright (C) 2014--2022 Taler Systems SA

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
 *
 * TODO:
 * - Test setup with KYC where purse merge is only
 *   allowed for reserves with KYC completed.
 * - Test purse creation with reserve purse quota
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
 * Exchange configuration data.
 */
static struct TALER_TESTING_ExchangeConfiguration ec;

/**
 * Bank configuration data.
 */
static struct TALER_TESTING_BankConfiguration bc;

/**
 * Some tests behave differently when using CS as we cannot
 * re-use the coin private key for different denominations
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
  TALER_TESTING_cmd_exec_wirewatch (label, config_file)

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
   * Test withdrawal plus spending.
   */
  struct TALER_TESTING_Command withdraw[] = {
    /**
     * Move money to the exchange's bank account.
     */
    CMD_TRANSFER_TO_EXCHANGE ("create-reserve-1",
                              "EUR:5.01"),
    CMD_TRANSFER_TO_EXCHANGE ("create-reserve-2",
                              "EUR:5.01"),
    TALER_TESTING_cmd_reserve_poll ("poll-reserve-1",
                                    "create-reserve-1",
                                    "EUR:5.01",
                                    GNUNET_TIME_UNIT_MINUTES,
                                    MHD_HTTP_OK),
    TALER_TESTING_cmd_check_bank_admin_transfer ("check-create-reserve-1",
                                                 "EUR:5.01",
                                                 bc.user42_payto,
                                                 bc.exchange_payto,
                                                 "create-reserve-1"),
    TALER_TESTING_cmd_check_bank_admin_transfer ("check-create-reserve-2",
                                                 "EUR:5.01",
                                                 bc.user42_payto,
                                                 bc.exchange_payto,
                                                 "create-reserve-2"),
    /**
     * Make a reserve exist, according to the previous
     * transfer.
     */
    CMD_EXEC_WIREWATCH ("wirewatch-1"),
    TALER_TESTING_cmd_reserve_poll_finish ("finish-poll-reserve-1",
                                           GNUNET_TIME_UNIT_SECONDS,
                                           "poll-reserve-1"),
    /**
     * Withdraw EUR:5.
     */
    TALER_TESTING_cmd_withdraw_amount ("withdraw-coin-1",
                                       "create-reserve-1",
                                       "EUR:5",
                                       0, /* age restriction off */
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
  struct TALER_TESTING_Command push[] = {
    TALER_TESTING_cmd_purse_create_with_deposit (
      "purse-with-deposit",
      MHD_HTTP_OK,
      "{\"amount\":\"EUR:1\",\"summary\":\"ice cream\"}",
      true, /* upload contract */
      GNUNET_TIME_UNIT_MINUTES, /* expiration */
      "withdraw-coin-1",
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
      "EUR:1",
      MHD_HTTP_OK),
    /* POST history doesn't yet support P2P transfers */
    TALER_TESTING_cmd_reserve_status (
      "push-check-post-merge-reserve-balance-post",
      "create-reserve-1",
      "EUR:1",
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
      "EUR:2",
      MHD_HTTP_OK),
#if 1
    /* POST history doesn't yet support P2P transfers */
    TALER_TESTING_cmd_reserve_status (
      "push-check-post-merge-reserve-balance-post",
      "create-reserve-1",
      "EUR:2",
      MHD_HTTP_OK),
#endif
    /* create 2nd purse for a deposit conflict */
    TALER_TESTING_cmd_purse_create_with_reserve (
      "purse-create-with-reserve-2",
      MHD_HTTP_OK,
      "{\"amount\":\"EUR:4\",\"summary\":\"beer\"}",
      true /* upload contract */,
      GNUNET_TIME_UNIT_MINUTES, /* expiration */
      "create-reserve-1"),
#if FIXME_RESERVE_HISTORY
    TALER_TESTING_cmd_purse_deposit_coins (
      "purse-deposit-coins-conflict",
      MHD_HTTP_CONFLICT,
      0 /* min age */,
      "purse-create-with-reserve-2",
      "withdraw-coin-1",
      "EUR:4.01",
      NULL),
#endif
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command expire[] = {
    TALER_TESTING_cmd_purse_create_with_reserve (
      "purse-create-with-reserve-expire",
      MHD_HTTP_OK,
      "{\"amount\":\"EUR:2\",\"summary\":\"ice cream\"}",
      true /* upload contract */,
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
      "EUR:1.01",
      NULL),
    TALER_TESTING_cmd_purse_poll (
      "push-poll-purse-before-expire",
      MHD_HTTP_GONE,
      "purse-with-deposit-expire",
      "EUR:1",
      true,
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
    TALER_TESTING_cmd_sleep ("sleep",
                             2 /* seconds */),
    TALER_TESTING_cmd_exec_expire ("exec-expire",
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

  struct TALER_TESTING_Command commands[] = {
    /* setup exchange */
    TALER_TESTING_cmd_auditor_add ("add-auditor-OK",
                                   MHD_HTTP_NO_CONTENT,
                                   false),
    TALER_TESTING_cmd_exec_offline_sign_extensions ("offline-sign-extensions",
                                                    config_file),
    TALER_TESTING_cmd_wire_add ("add-wire-account",
                                "payto://x-taler-bank/localhost/2",
                                MHD_HTTP_NO_CONTENT,
                                false),
    TALER_TESTING_cmd_exec_offline_sign_fees ("offline-sign-wire-fees",
                                              config_file,
                                              "EUR:0.01",
                                              "EUR:0.01",
                                              "EUR:0.01"),
    TALER_TESTING_cmd_exec_offline_sign_global_fees ("offline-sign-global-fees",
                                                     config_file,
                                                     "EUR:0.01",
                                                     "EUR:0.01",
                                                     "EUR:0.01",
                                                     "EUR:0.01",
                                                     GNUNET_TIME_UNIT_MINUTES,
                                                     GNUNET_TIME_UNIT_MINUTES,
                                                     GNUNET_TIME_UNIT_DAYS,
                                                     1),
    TALER_TESTING_cmd_exec_offline_sign_keys ("offline-sign-future-keys",
                                              config_file),
    TALER_TESTING_cmd_check_keys_pull_all_keys ("refetch /keys",
                                                1),
    TALER_TESTING_cmd_batch ("withdraw",
                             withdraw),
    TALER_TESTING_cmd_batch ("push",
                             push),
    TALER_TESTING_cmd_batch ("pull",
                             pull),
    TALER_TESTING_cmd_batch ("expire",
                             expire),
    /* End the suite. */
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

  GNUNET_assert (GNUNET_OK ==
                 TALER_extension_age_restriction_register ());

  cipher = GNUNET_TESTING_get_testname_from_underscore (argv[0]);
  GNUNET_assert (NULL != cipher);
  uses_cs = (0 == strcmp (cipher, "cs"));
  GNUNET_asprintf (&config_file,
                   "test_exchange_api-%s.conf",
                   cipher);
  GNUNET_free (cipher);

  /* Check fakebank port is available and get config */
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
        TALER_TESTING_setup_with_exchange (&run,
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


/* end of test_exchange_p2p.c */
