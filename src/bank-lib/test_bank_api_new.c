/*
  This file is part of TALER
  Copyright (C) 2016, 2017 GNUnet e.V.

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
 * @file bank/test_bank_api_new.c
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
 * Handle to the Py-bank daemon.
 */
static struct GNUNET_OS_Process *bankd;

/**
 * Flag indicating whether the test is running against the
 * Fakebank.  Set up at runtime.
 */
static int WITH_FAKEBANK;

/**
 * Transfer @a amount from @a src account to @a dst using
 * @a subject and the @a label for the command.
 */
#define TRANSFER(label,amount,src,dst,subject)          \
  TALER_TESTING_cmd_fakebank_transfer_with_subject (label, \
                                                    amount,   \
                                                    bank_url, \
                                                    src,                \
                                                    dst, \
                                                    AUTHS[src \
                                                          - 1].details.basic. \
                                                    username, \
                                                    AUTHS[src \
                                                          - 1].details.basic. \
                                                    password, \
                                                    subject, \
                                                    "http://exchange.net/")


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
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Bank serves at `%s'\n",
              bank_url);
  extern struct TALER_BANK_AuthenticationData AUTHS[];
  struct TALER_TESTING_Command commands[] = {
    TALER_TESTING_cmd_bank_history ("history-0",
                                    bank_url,
                                    BANK_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_BOTH,
                                    GNUNET_YES,
                                    NULL,
                                    1),
    /* WARNING: old API has expected http response code among
     * the parameters, although it was always set as '200 OK' */
    TRANSFER ("debit-1",
              "KUDOS:5.01",
              EXCHANGE_ACCOUNT_NUMBER,
              BANK_ACCOUNT_NUMBER,
              "subject 1"),
    TALER_TESTING_cmd_bank_history ("history-1c",
                                    bank_url,
                                    BANK_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_CREDIT,
                                    GNUNET_YES,
                                    NULL,
                                    5),
    TALER_TESTING_cmd_bank_history ("history-1d",
                                    bank_url,
                                    BANK_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_DEBIT,
                                    GNUNET_YES,
                                    NULL,
                                    5),
    TRANSFER ("debit-2",
              "KUDOS:3.21",
              EXCHANGE_ACCOUNT_NUMBER,
              USER_ACCOUNT_NUMBER,
              "subject 2"),
    TRANSFER ("credit-2",
              "KUDOS:3.22",
              USER_ACCOUNT_NUMBER,
              EXCHANGE_ACCOUNT_NUMBER,
              "credit 2"),
    TALER_TESTING_cmd_bank_history ("history-2b",
                                    bank_url,
                                    EXCHANGE_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_BOTH,
                                    GNUNET_YES,
                                    NULL,
                                    5),
    TALER_TESTING_cmd_bank_history ("history-2bi",
                                    bank_url,
                                    EXCHANGE_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_BOTH,
                                    GNUNET_YES,
                                    "debit-1",
                                    5),
    TRANSFER ("credit-for-reject-1",
              "KUDOS:1.01",
              BANK_ACCOUNT_NUMBER,
              EXCHANGE_ACCOUNT_NUMBER,
              "subject 3"),
    TALER_TESTING_cmd_bank_reject ("reject-1",
                                   bank_url,
                                   "credit-for-reject-1"),
    TALER_TESTING_cmd_bank_history ("history-r1",
                                    bank_url,
                                    BANK_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_BOTH,
                                    GNUNET_YES,
                                    NULL,
                                    5),
    TALER_TESTING_cmd_bank_history ("history-r1c",
                                    bank_url,
                                    BANK_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_BOTH
                                    | TALER_BANK_DIRECTION_CANCEL,
                                    GNUNET_YES,
                                    NULL,
                                    5),
    TALER_TESTING_cmd_end ()
  };

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
  GNUNET_log_setup ("test-bank-api-with-(fake)bank-new",
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


/* end of test_bank_api_new.c */
