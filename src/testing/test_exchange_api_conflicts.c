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
 * @file testing/test_exchange_api_conflicts.c
 * @brief testcase to test exchange's handling of coin conflicts: same private
 *        keys but different denominations or age restrictions
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
   * Test withdrawal with conflicting coins.
   */
  struct TALER_TESTING_Command withdraw_conflict_denom[] = {
    /**
     * Move money to the exchange's bank account.
     */
    CMD_TRANSFER_TO_EXCHANGE ("create-reserve-denom",
                              "EUR:21.03"),
    TALER_TESTING_cmd_check_bank_admin_transfer ("check-create-reserve-denom",
                                                 "EUR:21.03",
                                                 cred.user42_payto,
                                                 cred.exchange_payto,
                                                 "create-reserve-denom"),
    /**
     * Make a reserve exist, according to the previous
     * transfer.
     */
    CMD_EXEC_WIREWATCH ("wirewatch-conflict-denom"),
    /**
     * Withdraw EUR:1, EUR:5, EUR:15, but using the same private key each time.
     */
    TALER_TESTING_cmd_batch_withdraw_with_conflict ("withdraw-coin-denom-1",
                                                    "create-reserve-denom",
                                                    Conflict_Denom,
                                                    0, /* age */
                                                    MHD_HTTP_OK,
                                                    "EUR:1",
                                                    "EUR:5",
                                                    "EUR:10",
                                                    NULL),

    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command spend_conflict_denom[] = {
    /**
     * Spend the coin.
     */
    TALER_TESTING_cmd_deposit ("deposit",
                               "withdraw-coin-denom-1",
                               0,
                               cred.user42_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:0.99",
                               MHD_HTTP_OK),
    TALER_TESTING_cmd_deposit ("deposit-denom-conflict",
                               "withdraw-coin-denom-1",
                               1,
                               cred.user42_payto,
                               "{\"items\":[{\"name\":\"ice cream\",\"value\":1}]}",
                               GNUNET_TIME_UNIT_ZERO,
                               "EUR:4.99",
                               /* FIXME: this fails for cs denominations! */
                               MHD_HTTP_CONFLICT),
    TALER_TESTING_cmd_end ()
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
      TALER_TESTING_cmd_batch ("withdraw-conflict-denom",
                               withdraw_conflict_denom),
      TALER_TESTING_cmd_batch ("spend-conflict-denom",
                               spend_conflict_denom),
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
                     "test_exchange_api_conflicts-%s.conf",
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


/* end of test_exchange_api_conflicts.c */
