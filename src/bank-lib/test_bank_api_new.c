/*
  This file is part of TALER
  Copyright (C) 2016, 2017 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published
  by the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/> 
*/

/**
 * @file bank/test_bank_api_new.c
 * @brief testcase to test bank's HTTP API
 *        interface against the "real" bank
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */

#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_bank_service.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include <microhttpd.h>
#include "taler_exchange_service.h"
#include "test_bank_interpreter.h"
#include "taler_testing_lib.h"
#include "taler_testing_bank_lib.h"

#define CONFIG_FILE "bank.conf"

/**
 * Bank process.
 */
struct GNUNET_OS_Process *bankd;

/**
 * Bank URL.
 */
char *bank_url;

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
  
  extern struct TALER_BANK_AuthenticationData AUTHS[];

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Bank serves at `%s'\n",
              bank_url);

  struct TALER_TESTING_Command commands[] = {

    /**
     * NOTE: this command uses internally the _fakebank_ version
     * of the add-incoming command.  However, this does seem to
     * work fine against the Python bank too!  Some renaming is
     * required..
     */
    TALER_TESTING_cmd_bank_history ("history-0",
                                    bank_url,
                                    EXCHANGE_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_BOTH,
                                    NULL,
                                    5),

    /* WARNING: old API has expected http response code among
     * the parameters, although it was always set as '200 OK' */
    TALER_TESTING_cmd_fakebank_transfer_with_subject
      ("deposit-1",
       "KUDOS:5.01",
       bank_url,
       BANK_ACCOUNT_NUMBER,
       EXCHANGE_ACCOUNT_NUMBER,
       AUTHS[BANK_ACCOUNT_NUMBER -1].details.basic.username,
       AUTHS[BANK_ACCOUNT_NUMBER -1].details.basic.password,
       "subject 1",
       "http://exchange.com/"),

    TALER_TESTING_cmd_fakebank_transfer_with_subject
      ("deposit-2",
       "KUDOS:5.01",
       bank_url,
       BANK_ACCOUNT_NUMBER,
       EXCHANGE_ACCOUNT_NUMBER,
       AUTHS[BANK_ACCOUNT_NUMBER -1].details.basic.username,
       AUTHS[BANK_ACCOUNT_NUMBER -1].details.basic.password,
       "subject 2",
       "http://exchange.com/"),

    TALER_TESTING_cmd_bank_history ("history-1c",
                                    bank_url,
                                    EXCHANGE_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_CREDIT,
                                    NULL,
                                    5),

    TALER_TESTING_cmd_bank_history ("history-1d",
                                    bank_url,
                                    EXCHANGE_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_DEBIT,
                                    NULL,
                                    5),

    TALER_TESTING_cmd_bank_history ("history-1dr",
                                    bank_url,
                                    EXCHANGE_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_DEBIT,
                                    NULL,
                                    -5),

    TALER_TESTING_cmd_bank_history ("history-2fwd",
                                    bank_url,
                                    EXCHANGE_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_DEBIT,
                                    "deposit-1",
                                    5),

    TALER_TESTING_cmd_bank_reject ("reject-1",
                                   bank_url,
                                   "deposit-1"),
    /**
     * End the suite.  Fixme: better to have a label for this
     * too, as it shows a "(null)" token on logs.
     */
    TALER_TESTING_cmd_end ()
  };

  TALER_TESTING_run (is, commands);
}


/* Pacifies "make check" */
int
main(int argc,
     char * const *argv)
{
  unsigned int ret;
  /* These environment variables get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-bank-api-new", "DEBUG", NULL);

  if (NULL ==
    (bank_url = TALER_TESTING_prepare_bank (CONFIG_FILE)))
    return 77;

  if (NULL == (bankd =
      TALER_TESTING_run_bank (CONFIG_FILE)))
    return 77;
  
  ret = TALER_TESTING_setup (&run,
                             NULL,
                             CONFIG_FILE,
                             NULL); // means no exchange.

  GNUNET_OS_process_kill (bankd, SIGKILL); 
  GNUNET_OS_process_wait (bankd); 
  GNUNET_OS_process_destroy (bankd); 
  GNUNET_free (bank_url);

  if (GNUNET_OK == ret)
    return 0;

  return 1;
}

/* end of test_bank_api_new.c */
