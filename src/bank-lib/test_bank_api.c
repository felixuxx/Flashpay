/*
  This file is part of TALER
  Copyright (C) 2016, 2017 GNUnet e.V.

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
 * @file bank/test_bank_api.c
 * @brief testcase to test bank's HTTP API interface against the "real" bank
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_bank_service.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include <microhttpd.h>
#include "test_bank_interpreter.h"


/**
 * Main function that will be run by the scheduler.
 *
 * @param cls closure
 */
static void
run (void *cls)
{
  int *resultp = cls;
  static struct TBI_Command commands[] =
  {
    /* Add EUR:5.01 to account 42 */
    { .oc = TBI_OC_ADMIN_ADD_INCOMING,
      .label = "deposit-1",
      .details.admin_add_incoming.expected_response_code = MHD_HTTP_OK,
      .details.admin_add_incoming.credit_account_no = 1,
      .details.admin_add_incoming.debit_account_no = 2,
      .details.admin_add_incoming.amount = "PUDOS:5.01" },

    { .oc = TBI_OC_END }
  };

  TBI_run_interpreter (resultp,
                       GNUNET_NO /* we use the "real" taler bank */,
                       commands);
}


/**
 * Main function for the testcase for the bank API.
 *
 * @param argc expected to be 1
 * @param argv expected to only contain the program name
 */
int
main (int argc,
      char * const *argv)
{
  struct GNUNET_OS_Process *bankd;
  struct GNUNET_OS_Process *bankd_admin;
  unsigned int cnt;
  int result;

  if (GNUNET_OK !=
      GNUNET_NETWORK_test_port_free (IPPROTO_TCP,
				     8081))
  {
    fprintf (stderr,
             "Required port %u not available, skipping.\n",
	     8081);
    return 77;
  }
  GNUNET_log_setup ("test-bank-api",
                    "WARNING",
                    NULL);
  bankd_admin = GNUNET_OS_start_process (GNUNET_NO,
                                         GNUNET_OS_INHERIT_STD_ALL,
                                         NULL, NULL, NULL,
                                         "taler-bank-manage",
                                         "taler-bank-manage",
                                         "--admin",
                                         "serve-http",
				         "--port", "8081",
                                         NULL);
  if (NULL == bankd_admin) 
  {
    fprintf (stderr,
             "Failed to launch `taler-bank-manage' for admin, skipping test\n");
    return 77; /* report 'skip' */
  }
  bankd = GNUNET_OS_start_process (GNUNET_NO,
                                   GNUNET_OS_INHERIT_STD_ALL,
                                   NULL, NULL, NULL,
                                   "taler-bank-manage",
                                   "taler-bank-manage",
                                   "serve-http",
                                   "--port", "8080",
                                   NULL);

  if (NULL == bankd)
  {
    fprintf (stderr,
             "Failed to launch taler-bank-manage, skipping test\n");
    GNUNET_OS_process_kill (bankd_admin,
			    SIGTERM);
    GNUNET_OS_process_wait (bankd_admin);
    GNUNET_OS_process_destroy (bankd_admin);
    return 77; /* report 'skip' */
  }
  /* give child time to start and bind against the socket */
  fprintf (stderr,
           "Waiting for taler-bank-manage to be ready\n");
  cnt = 0;
  do
    {
      fprintf (stderr, ".");
      sleep (1);
      cnt++;
      if (cnt > 30)
        break;
    }
  while (0 != system ("wget -q -t 1 -T 1 http://127.0.0.1:8080/ -o /dev/null -O /dev/null"));

  do
    {
      fprintf (stderr, ".");
      sleep (1);
      cnt++;
      if (cnt > 30)
        break;
    }
  while (0 != system ("wget -q -t 1 -T 1 http://127.0.0.1:8081/admin/add/incoming -o /dev/null -O /dev/null"));

  fprintf (stderr, "\n");
  result = GNUNET_SYSERR;
  if (cnt <= 30)
    GNUNET_SCHEDULER_run (&run, &result);
  GNUNET_OS_process_kill (bankd,
                          SIGTERM);
  GNUNET_OS_process_kill (bankd_admin,
                          SIGTERM);
  GNUNET_OS_process_wait (bankd);
  GNUNET_OS_process_destroy (bankd);
  GNUNET_OS_process_wait (bankd_admin);
  GNUNET_OS_process_destroy (bankd_admin);
  if (cnt > 30)
  {
    fprintf (stderr,
             "taler-bank-manage failed to start properly.\n");
    return 77;
  }
  return (GNUNET_OK == result) ? 0 : 1;
}

/* end of test_bank_api.c */
