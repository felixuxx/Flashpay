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
 * @file bank/test_bank_api_with_fakebank.c
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
#include "test_bank_interpreter.h"
#include "taler_testing_lib.h"
#include "taler_testing_bank_lib.h"


#define CONFIG_FILE "bank.conf"


/**
 * Fakebank URL.
 */
char *fakebank_url;

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
              "Fakebank serves at `%s'\n",
              fakebank_url);
  extern struct TALER_BANK_AuthenticationData AUTHS[];

  struct TALER_TESTING_Command commands[] = {

    /**
     * NOTE: this command uses internally the _fakebank_ version
     * of the add-incoming command.  However, this does seem to
     * work fine against the Python bank too!  Some renaming is
     * required..
     */
    TALER_TESTING_cmd_bank_history ("history-0",
                                    fakebank_url,
                                    BANK_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_BOTH,
                                    NULL,
                                    1),


    /* WARNING: old API has expected http response code among
     * the parameters, although it was always set as '200 OK' */
    TALER_TESTING_cmd_fakebank_transfer_with_subject
      ("debit-1",
       "KUDOS:5.01",
       fakebank_url,
       EXCHANGE_ACCOUNT_NUMBER,
       BANK_ACCOUNT_NUMBER,
       AUTHS[EXCHANGE_ACCOUNT_NUMBER -1].details.basic.username,
       AUTHS[EXCHANGE_ACCOUNT_NUMBER -1].details.basic.password,
       "subject 1",
       "http://exchange.com/"),

    TALER_TESTING_cmd_bank_history ("history-1c",
                                    fakebank_url,
                                    BANK_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_CREDIT,
                                    NULL,
                                    5),

    TALER_TESTING_cmd_bank_history ("history-1d",
                                    fakebank_url,
                                    BANK_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_DEBIT,
                                    NULL,
                                    5),

    TALER_TESTING_cmd_fakebank_transfer_with_subject
      ("debit-2",
       "KUDOS:3.21",
       fakebank_url,
       EXCHANGE_ACCOUNT_NUMBER, // debit account.
       USER_ACCOUNT_NUMBER,
       AUTHS[EXCHANGE_ACCOUNT_NUMBER -1].details.basic.username,
       AUTHS[EXCHANGE_ACCOUNT_NUMBER -1].details.basic.password,
       "subject 2",
       "http://exchange.org/"),

    TALER_TESTING_cmd_fakebank_transfer_with_subject
      ("credit-2",
       "KUDOS:3.22",
       fakebank_url,
       USER_ACCOUNT_NUMBER, // debit account.
       EXCHANGE_ACCOUNT_NUMBER,
       AUTHS[USER_ACCOUNT_NUMBER -1].details.basic.username,
       AUTHS[USER_ACCOUNT_NUMBER -1].details.basic.password,
       "credit 2",
       "http://exchange.org/"),

    TALER_TESTING_cmd_bank_history ("history-2b",
                                    fakebank_url,
                                    EXCHANGE_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_BOTH,
                                    NULL,
                                    5),

    TALER_TESTING_cmd_bank_history ("history-2bi",
                                    fakebank_url,
                                    EXCHANGE_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_BOTH,
                                    "debit-1",
                                    5),

    TALER_TESTING_cmd_check_bank_transfer_with_ref ("expect-2d",
                                                    "credit-2"),

    TALER_TESTING_cmd_check_bank_transfer_with_ref ("expect-2c",
                                                    "debit-2"),

    TALER_TESTING_cmd_check_bank_transfer_with_ref ("expect-1",
                                                    "debit-1"),

    TALER_TESTING_cmd_check_bank_empty ("expect-empty"),

    TALER_TESTING_cmd_fakebank_transfer_with_subject
      ("credit-for-reject-1",
       "KUDOS:5.01",
       fakebank_url,
       BANK_ACCOUNT_NUMBER,
       EXCHANGE_ACCOUNT_NUMBER,
       AUTHS[BANK_ACCOUNT_NUMBER -1].details.basic.username,
       AUTHS[BANK_ACCOUNT_NUMBER -1].details.basic.password,
       "subject 3",
       "http://exchange.net/"),

     TALER_TESTING_cmd_bank_reject ("reject-1",
                                    fakebank_url,
                                    "credit-for-reject-1"),

    TALER_TESTING_cmd_bank_history ("history-r1",
                                    fakebank_url,
                                    BANK_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_BOTH,
                                    NULL,
                                    5),

    TALER_TESTING_cmd_bank_history ("history-r1c",
                                    fakebank_url,
                                    BANK_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_BOTH |
                                    TALER_BANK_DIRECTION_CANCEL,
                                    NULL,
                                    5),

    TALER_TESTING_cmd_check_bank_transfer_with_ref
      ("expect-credit-reject-1",
       "credit-for-reject-1"),

    TALER_TESTING_cmd_check_bank_empty ("expect-empty-2"),

    /**
     * End the suite.  Fixme: better to have a label for this
     * too, as it shows a "(null)" token on logs.
     */
    TALER_TESTING_cmd_end ()
  };

  TALER_TESTING_run_with_fakebank (is,
                                   commands,
                                   fakebank_url);
}

int
main (int argc,
      char * const *argv)
{
  /* These environment variables get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-merchant-api-with-fakebank-new",
                    "DEBUG",
                    NULL);
  if (NULL ==
    (fakebank_url = TALER_TESTING_prepare_fakebank (CONFIG_FILE)))
    return 77;
  
  return (GNUNET_OK == TALER_TESTING_setup (&run,
                                            NULL,
                                            CONFIG_FILE,
                                            NULL)) ? 0 : 1;
}


/* end of test_bank_api_with_fakebank_new.c */
