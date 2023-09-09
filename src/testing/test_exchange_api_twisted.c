/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * @file testing/test_exchange_api_twisted.c
 * @brief testcase to test exchange's HTTP API interface
 * @author Marcello Stanisci
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
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
#include "taler_twister_testing_lib.h"
#include <taler/taler_twister_service.h>

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
 * (real) Twister URL.  Used at startup time to check if it runs.
 */
static char *twister_url;

/**
 * Twister process.
 */
static struct GNUNET_OS_Process *twisterd;


/**
 * Execute the taler-exchange-wirewatch command with
 * our configuration file.
 *
 * @param label label to use for the command.
 */
static struct TALER_TESTING_Command
CMD_EXEC_WIREWATCH (const char *label)
{
  return TALER_TESTING_cmd_exec_wirewatch2 (label,
                                            config_file,
                                            "exchange-account-2");
}


/**
 * Run wire transfer of funds from some user's account to the
 * exchange.
 *
 * @param label label to use for the command.
 * @param amount amount to transfer, i.e. "EUR:1"
 * @param url exchange_url
 */
static struct TALER_TESTING_Command
CMD_TRANSFER_TO_EXCHANGE (const char *label,
                          const char *amount)
{
  return TALER_TESTING_cmd_admin_add_incoming (label,
                                               amount,
                                               &cred.ba,
                                               cred.user42_payto);
}


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
   * This batch aims to trigger the 409 Conflict
   * response from a refresh-reveal operation.
   */
  struct TALER_TESTING_Command refresh_409_conflict[] = {
    CMD_TRANSFER_TO_EXCHANGE (
      "refresh-create-reserve",
      "EUR:5.01"),
    /**
     * Make previous command effective.
     */
    CMD_EXEC_WIREWATCH ("wirewatch"),
    /**
     * Withdraw EUR:5.
     */
    TALER_TESTING_cmd_withdraw_amount (
      "refresh-withdraw-coin",
      "refresh-create-reserve",
      "EUR:5",
      0,                                  /* age restriction off */
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit (
      "refresh-deposit-partial",
      "refresh-withdraw-coin",
      0,
      cred.user42_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":\"EUR:1\"}]}",
      GNUNET_TIME_UNIT_ZERO,
      "EUR:1",
      MHD_HTTP_OK),
    /**
     * Melt the rest of the coin's value
     * (EUR:4.00 = 3x EUR:1.03 + 7x EUR:0.13) */
    TALER_TESTING_cmd_melt (
      "refresh-melt",
      "refresh-withdraw-coin",
      MHD_HTTP_OK,
      NULL),
    /* Trigger 409 Conflict.  */
    TALER_TESTING_cmd_flip_upload (
      "flip-upload",
      config_file,
      "transfer_privs.0"),
    TALER_TESTING_cmd_refresh_reveal (
      "refresh-(flipped-)reveal",
      "refresh-melt",
      MHD_HTTP_CONFLICT),
    TALER_TESTING_cmd_end ()
  };


  /**
   * NOTE: not all CMDs actually need the twister,
   * so it may be better to move those into the "main"
   * lib test suite.
   */
  struct TALER_TESTING_Command refund[] = {
    CMD_TRANSFER_TO_EXCHANGE (
      "create-reserve-r1",
      "EUR:5.01"),
    CMD_EXEC_WIREWATCH ("wirewatch-r1"),
    TALER_TESTING_cmd_withdraw_amount (
      "withdraw-coin-r1",
      "create-reserve-r1",
      "EUR:5",
      0,                                  /* age restriction off */
      MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit (
      "deposit-refund-1",
      "withdraw-coin-r1",
      0,
      cred.user42_payto,
      "{\"items\":[{\"name\":\"ice cream\",\"value\":\"EUR:5\"}]}",
      GNUNET_TIME_UNIT_MINUTES,
      "EUR:5",
      MHD_HTTP_OK),
    TALER_TESTING_cmd_refund ("refund-currency-mismatch",
                              MHD_HTTP_BAD_REQUEST,
                              "USD:5",
                              "deposit-refund-1"),
    TALER_TESTING_cmd_flip_upload ("flip-upload",
                                   config_file,
                                   "merchant_sig"),
    TALER_TESTING_cmd_refund ("refund-bad-sig",
                              MHD_HTTP_FORBIDDEN,
                              "EUR:5",
                              "deposit-refund-1"),
    /* This next deposit CMD is only used to provide a
     * good merchant signature to the next (failing) refund
     * operations.  */
    TALER_TESTING_cmd_deposit (
      "deposit-refund-to-fail",
      "withdraw-coin-r1",
      0,                          /* coin index.  */
      cred.user42_payto,
      /* This parameter will make any comparison about
         h_contract_terms fail, when /refund will be handled.
         So in other words, this is h_contract mismatch.  */
      "{\"items\":[{\"name\":\"ice skate\",\"value\":\"EUR:5\"}]}",
      GNUNET_TIME_UNIT_MINUTES,
      "EUR:5",
      MHD_HTTP_CONFLICT),
    TALER_TESTING_cmd_refund ("refund-deposit-not-found",
                              MHD_HTTP_NOT_FOUND,
                              "EUR:5",
                              "deposit-refund-to-fail"),
    TALER_TESTING_cmd_refund ("refund-insufficient-funds",
                              MHD_HTTP_CONFLICT,
                              "EUR:50",
                              "deposit-refund-1"),
    TALER_TESTING_cmd_end ()
  };

#if 0
  /**
   * Test that we don't get errors when the keys from the exchange
   * are out of date.
   */
  struct TALER_TESTING_Command expired_keys[] = {
    TALER_TESTING_cmd_modify_header_dl (
      "modify-expiration",
      config_file,
      MHD_HTTP_HEADER_EXPIRES,
      "Wed, 19 Jan 586524 08:01:49 GMT"),
    TALER_TESTING_cmd_check_keys_pull_all_keys (
      "check-keys-expiration-0",
      2),
    /**
     * Run some normal commands after this to make sure everything is fine.
     */
    CMD_TRANSFER_TO_EXCHANGE ("create-reserve-r2",
                              "EUR:55.01"),
    CMD_EXEC_WIREWATCH ("wirewatch-r2"),
    TALER_TESTING_cmd_withdraw_amount (
      "withdraw-coin-r2",
      "create-reserve-r2",
      "EUR:5",
      0,                                  /* age restriction off */
      MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };
#endif

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
    TALER_TESTING_cmd_batch (
      "refresh-reveal-409-conflict",
      refresh_409_conflict),
    TALER_TESTING_cmd_batch (
      "refund",
      refund),
#if 0
    TALER_TESTING_cmd_batch ("expired-keys",
                             expired_keys),
#endif
    TALER_TESTING_cmd_end ()
  };

  (void) cls;
  TALER_TESTING_run (is,
                     commands);
}


/**
 * Kill, wait, and destroy convenience function.
 *
 * @param[in] process process to purge.
 */
static void
purge_process (struct GNUNET_OS_Process *process)
{
  GNUNET_OS_process_kill (process,
                          SIGINT);
  GNUNET_OS_process_wait (process);
  GNUNET_OS_process_destroy (process);
}


int
main (int argc,
      char *const *argv)
{
  int ret;

  (void) argc;
  {
    char *cipher;

    cipher = GNUNET_STRINGS_get_suffix_from_binary_name (argv[0]);
    GNUNET_assert (NULL != cipher);
    GNUNET_asprintf (&config_file,
                     "test_exchange_api_twisted-%s.conf",
                     cipher);
    GNUNET_free (cipher);
  }
  /* FIXME: introduce commands for twister! */
  twister_url = TALER_TWISTER_prepare_twister (config_file);
  if (NULL == twister_url)
    return 77;
  twisterd = TALER_TWISTER_run_twister (config_file);
  if (NULL == twisterd)
    return 77;
  ret = TALER_TESTING_main (argv,
                            "INFO",
                            config_file,
                            "exchange-account-2",
                            TALER_TESTING_BS_FAKEBANK,
                            &cred,
                            &run,
                            NULL);
  purge_process (twisterd);
  GNUNET_free (twister_url);
  return ret;
}


/* end of test_exchange_api_twisted.c */
