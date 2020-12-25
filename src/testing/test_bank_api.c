/*
  This file is part of TALER
  Copyright (C) 2016-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/test_bank_api.c
 * @brief testcase to test bank's HTTP API
 *        interface against the fakebank
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_bank_service.h"
#include "taler_exchange_service.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include <microhttpd.h>
#include "taler_testing_lib.h"

#define CONFIG_FILE_FAKEBANK "test_bank_api_fakebank.conf"
#define CONFIG_FILE_PYBANK "test_bank_api_pybank.conf"
#define CONFIG_FILE_NEXUS "test_bank_api_nexus.conf"

/**
 * Bank configuration data.
 */
static struct TALER_TESTING_BankConfiguration bc;

/**
 * Handle to the Py-bank daemon.
 */
static struct GNUNET_OS_Process *bankd;

/**
 * Flag indicating whether the test is running against the
 * Fakebank.  Set up at runtime.
 */
static int with_fakebank;

/**
 * Handles to the libeufin services.
 */
static struct TALER_TESTING_LibeufinServices libeufin_services;

/**
 * Needed to shutdown differently.
 */
static int with_libeufin;

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
  struct TALER_WireTransferIdentifierRawP wtid;

  memset (&wtid, 42, sizeof (wtid));

  {
    struct TALER_TESTING_Command commands[] = {
      TALER_TESTING_cmd_bank_credits ("history-0",
                                      &bc.exchange_auth,
                                      NULL,
                                      1),
      TALER_TESTING_cmd_admin_add_incoming ("credit-1",
                                            "KUDOS:5.01",
                                            &bc.exchange_auth,
                                            bc.user42_payto),
      TALER_TESTING_cmd_sleep ("Waiting 4s for 'credit-1' to settle",
                               4),
      TALER_TESTING_cmd_bank_credits ("history-1c",
                                      &bc.exchange_auth,
                                      NULL,
                                      5),
      TALER_TESTING_cmd_bank_debits ("history-1d",
                                     &bc.exchange_auth,
                                     NULL,
                                     5),
      TALER_TESTING_cmd_admin_add_incoming ("credit-2",
                                            "KUDOS:3.21",
                                            &bc.exchange_auth,
                                            bc.user42_payto),
      TALER_TESTING_cmd_transfer ("debit-1",
                                  "KUDOS:3.22",
                                  &bc.exchange_auth,
                                  bc.exchange_payto,
                                  bc.user42_payto,
                                  &wtid,
                                  "http://exchange.example.com/"),

      TALER_TESTING_cmd_sleep ("Waiting 5s for 'debit-1' to settle",
                               5),
      TALER_TESTING_cmd_bank_debits ("history-2b",
                                     &bc.exchange_auth,
                                     NULL,
                                     5),
      TALER_TESTING_cmd_end ()
    };

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Bank serves at `%s'\n",
                bc.exchange_auth.wire_gateway_url);
    if (GNUNET_YES == with_fakebank)
      TALER_TESTING_run_with_fakebank (is,
                                       commands,
                                       bc.exchange_auth.wire_gateway_url);
    else
      TALER_TESTING_run (is,
                         commands);
  }
}


/**
 * Runs #TALER_TESTING_setup() using the configuration.
 *
 * @param cls unused
 * @param cfg configuration to use
 * @return status code
 */
static int
setup_with_cfg (void *cls,
                const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  (void) cls;
  return TALER_TESTING_setup (&run,
                              NULL,
                              cfg,
                              NULL,
                              GNUNET_NO);
}


int
main (int argc,
      char *const *argv)
{
  int rv;
  const char *cfgfile;

  /* These environment variables get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-bank-api",
                    "DEBUG",
                    NULL);

  with_fakebank = TALER_TESTING_has_in_name (argv[0],
                                             "_with_fakebank");
  if (GNUNET_YES == with_fakebank)
  {
    TALER_LOG_DEBUG ("Running against the Fakebank.\n");
    cfgfile = CONFIG_FILE_FAKEBANK;
    if (GNUNET_OK !=
        TALER_TESTING_prepare_fakebank (CONFIG_FILE_FAKEBANK,
                                        "exchange-account-2",
                                        &bc))
    {
      GNUNET_break (0);
      return 77;
    }
  }
  else if (GNUNET_YES == TALER_TESTING_has_in_name (argv[0],
                                                    "_with_pybank"))
  {
    TALER_LOG_DEBUG ("Running against the Pybank.\n");
    cfgfile = CONFIG_FILE_PYBANK;
    if (GNUNET_OK !=
        TALER_TESTING_prepare_bank (CONFIG_FILE_PYBANK,
                                    GNUNET_YES,
                                    "exchange-account-2",
                                    &bc))
    {
      GNUNET_break (0);
      return 77;
    }

    if (NULL == (bankd = TALER_TESTING_run_bank (
                   CONFIG_FILE_PYBANK,
                   bc.exchange_auth.wire_gateway_url)))
    {
      GNUNET_break (0);
      return 77;
    }
  }
  else if (GNUNET_YES == TALER_TESTING_has_in_name (argv[0],
                                                    "_with_nexus"))
  {
    TALER_LOG_DEBUG ("Running with Nexus.\n");
    with_libeufin = GNUNET_YES;
    cfgfile = CONFIG_FILE_NEXUS;
    if (GNUNET_OK != TALER_TESTING_prepare_nexus (CONFIG_FILE_NEXUS,
                                                  GNUNET_YES,
                                                  "exchange-account-2",
                                                  &bc))
    {
      GNUNET_break (0);
      return 77;
    }
    libeufin_services = TALER_TESTING_run_libeufin (&bc);
    if ( (NULL == libeufin_services.nexus) ||
         (NULL == libeufin_services.sandbox) )
      return 77;
  }
  else
  {
    /* no bank service was ever invoked.  */
    return 77;
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_parse_and_run (cfgfile,
                                          &setup_with_cfg,
                                          NULL))
    rv = 1;
  else
    rv = 0;

  if (GNUNET_NO == with_fakebank)
  {
    // -> pybank
    if (GNUNET_NO == with_libeufin)
    {

      GNUNET_OS_process_kill (bankd,
                              SIGKILL);
      GNUNET_OS_process_wait (bankd);
      GNUNET_OS_process_destroy (bankd);
    }
    else // -> libeufin
    {
      GNUNET_OS_process_kill (libeufin_services.nexus,
                              SIGKILL);
      GNUNET_OS_process_wait (libeufin_services.nexus);
      GNUNET_OS_process_destroy (libeufin_services.nexus);

      GNUNET_OS_process_kill (libeufin_services.sandbox,
                              SIGKILL);
      GNUNET_OS_process_wait (libeufin_services.sandbox);
      GNUNET_OS_process_destroy (libeufin_services.sandbox);
    }
  }

  return rv;
}


/* end of test_bank_api.c */
