/*
  This file is part of TALER
  Copyright (C) 2014-2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file exchange/test_exchange_api_new.c
 * @brief testcase to test exchange's HTTP API interface
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler_bank_service.h"
#include "taler_fakebank_lib.h"
#include "taler_testing_lib.h"


/**
 * Is the configuration file is set to include wire format 'test'?
 */
#define WIRE_TEST 1

/**
 * Is the configuration file is set to include wire format 'sepa'?
 */
#define WIRE_SEPA 1

/**
 * Account number of the exchange at the bank.
 */
#define EXCHANGE_ACCOUNT_NO 2


/**
 * Handle to access the exchange.
 */
// static struct TALER_EXCHANGE_Handle *exchange;

/**
 * Handle to the exchange process.
 */
static struct GNUNET_OS_Process *exchanged;


/**
 * Handle to our fakebank.
 */
static struct TALER_FAKEBANK_Handle *fakebank;




/**
 * Function run when the test terminates (good or bad).
 * Cleans up our state.
 *
 * @param cls NULL
 */
static void
do_shutdown (void *cls)
{
  if (NULL != fakebank)
  {
    TALER_FAKEBANK_stop (fakebank);
    fakebank = NULL;
  }
}


/**
 * Main function that will tell the interpreter what to do.
 *
 * @param cls closure
 */
static void
run (void *cls,
     struct TALER_TESTING_Interpreter *is)
{
  struct TALER_TESTING_Command commands[] = {
    TALER_TESTING_cmd_fakebank_transfer ("create-reserve-1",
                                         "EUR:5.01",
                                         42,
                                         EXCHANGE_ACCOUNT_NO,
                                         "user42",
                                         "pass42"),
    TALER_TESTING_cmd_exec_wirewatch ("exec-wirewatch",
                                      "test_exchange_api.conf"),
    TALER_TESTING_cmd_end ()
  };

  fakebank = TALER_FAKEBANK_start (8082);
  TALER_TESTING_run (is,
                     commands);
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
}



int
main (int argc,
      char * const *argv)
{
  struct GNUNET_OS_Process *proc;
  enum GNUNET_OS_ProcessStatusType type;
  unsigned long code;
  unsigned int iter;
  int result;

  /* These might get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-exchange-api-new",
                    "INFO",
                    NULL);
  TALER_TESTING_cleanup_files ("test_exchange_api.conf");
  result = TALER_TESTING_prepare_exchange ("test_exchange_api.conf");
  if (GNUNET_SYSERR == result)
    return 1;
  if (GNUNET_NO == result)
    return 77;

  /* For fakebank */
  if (GNUNET_OK !=
      GNUNET_NETWORK_test_port_free (IPPROTO_TCP,
				     8082))
  {
    fprintf (stderr,
             "Required port %u not available, skipping.\n",
	     8082);
    return 77;
  }

  exchanged = GNUNET_OS_start_process (GNUNET_NO,
                                       GNUNET_OS_INHERIT_STD_ALL,
                                       NULL, NULL, NULL,
                                       "taler-exchange-httpd",
                                       "taler-exchange-httpd",
                                       "-c", "test_exchange_api.conf",
                                       "-i",
                                       NULL);
  /* give child time to start and bind against the socket */
  fprintf (stderr,
           "Waiting for `taler-exchange-httpd' to be ready");
  iter = 0;
  do
    {
      if (10 == iter)
      {
	fprintf (stderr,
		 "Failed to launch `taler-exchange-httpd' (or `wget')\n");
	GNUNET_OS_process_kill (exchanged,
				SIGTERM);
	GNUNET_OS_process_wait (exchanged);
	GNUNET_OS_process_destroy (exchanged);
	return 77;
      }
      fprintf (stderr, ".");
      sleep (1);
      iter++;
    }
  while (0 != system ("wget -q -t 1 -T 1 http://127.0.0.1:8081/keys -o /dev/null -O /dev/null"));
  fprintf (stderr, "\n");

  result = TALER_TESTING_setup (&run,
                                NULL);
  GNUNET_break (0 ==
                GNUNET_OS_process_kill (exchanged,
                                        SIGTERM));
  GNUNET_break (GNUNET_OK ==
                GNUNET_OS_process_wait (exchanged));
  GNUNET_OS_process_destroy (exchanged);
  return (GNUNET_OK == result) ? 0 : 1;
}
