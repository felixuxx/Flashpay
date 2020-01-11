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
 * @file bank/test_bank_api.c
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
#include "taler_testing_bank_lib.h"


#define CONFIG_FILE "bank.conf"

/**
 * Fakebank URL.
 */
static char *bank_url;

/**
 * Account URL.
 */
static char *account_url;

/**
 * payto://-URL of another account.
 */
static char *payto_url;

/**
 * Handle to the Py-bank daemon.
 */
static struct GNUNET_OS_Process *bankd;

/**
 * Flag indicating whether the test is running against the
 * Fakebank.  Set up at runtime.
 */
static int WITH_FAKEBANK;

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
  struct TALER_TESTING_Command commands[] = {
    TALER_TESTING_cmd_bank_credits ("history-0",
                                    account_url,
                                    NULL,
                                    1),
    TALER_TESTING_cmd_admin_add_incoming ("debit-1",
                                          "KUDOS:5.01",
                                          account_url,
                                          payto_url,
                                          NULL,
                                          NULL),
    TALER_TESTING_cmd_bank_credits ("history-1c",
                                    account_url,
                                    NULL,
                                    5),
    TALER_TESTING_cmd_bank_debits ("history-1d",
                                   account_url,
                                   NULL,
                                   5),
    TALER_TESTING_cmd_admin_add_incoming ("debit-2",
                                          "KUDOS:3.21",
                                          account_url,
                                          payto_url,
                                          NULL,
                                          NULL),
    TRANSFER ("credit-2",
              "KUDOS:3.22",
              TALER_TESTING_USER_ACCOUNT_NUMBER,
              TALER_TESTING_EXCHANGE_ACCOUNT_NUMBER,
              "credit 2"),
    TALER_TESTING_cmd_bank_debits ("history-2b",
                                   account_url,
                                   NULL,
                                   5),
    TALER_TESTING_cmd_end ()
  };

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Bank serves at `%s'\n",
              bank_url);
  GNUNET_asprintf (&account_url,
                   "%s/%s",
                   base_url,
                   "alice");
  GNUNET_asprintf (&payto_url,
                   "payto://x-taler-bank/%s/%s",
                   base_url,
                   "bob");
  if (GNUNET_YES == WITH_FAKEBANK)
    TALER_TESTING_run_with_fakebank (is,
                                     commands,
                                     bank_url);
  else
    TALER_TESTING_run (is,
                       commands);
}


int
main (int argc,
      char *const *argv)
{
  int rv;

  /* These environment variables get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-bank-api",
                    "DEBUG",
                    NULL);

  WITH_FAKEBANK = TALER_TESTING_has_in_name (argv[0],
                                             "_with_fakebank");
  if (GNUNET_YES == WITH_FAKEBANK)
  {
    TALER_LOG_DEBUG ("Running against the Fakebank.\n");
    if (NULL == (bank_url = TALER_TESTING_prepare_fakebank (CONFIG_FILE,
                                                            "account-1")))
    {
      GNUNET_break (0);
      return 77;
    }
  }
  else
  {
    TALER_LOG_DEBUG ("Running against the Pybank.\n");
    if (NULL == (bank_url = TALER_TESTING_prepare_bank (CONFIG_FILE)))
    {
      GNUNET_break (0);
      return 77;
    }

    if (NULL == (bankd = TALER_TESTING_run_bank (CONFIG_FILE,
                                                 bank_url)))
    {
      GNUNET_break (0);
      return 77;
    }
  }

  rv = (GNUNET_OK == TALER_TESTING_setup (&run,
                                          NULL,
                                          CONFIG_FILE,
                                          NULL,
                                          GNUNET_NO)) ? 0 : 1;
  if (GNUNET_NO == WITH_FAKEBANK)
  {

    GNUNET_OS_process_kill (bankd,
                            SIGKILL);
    GNUNET_OS_process_wait (bankd);
    GNUNET_OS_process_destroy (bankd);
    GNUNET_free (bank_url);
  }

  return rv;
}


/* end of test_bank_api.c */
