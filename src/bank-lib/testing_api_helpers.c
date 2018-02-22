/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

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
 * @file bank-lib/testing_api_helpers.c
 * @brief convenience functions for bank-lib tests.
 * @author Marcello Stanisci
 */

#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_testing_bank_lib.h"

/* Keeps each bank account credential at bank account number - 1 */
struct TALER_BANK_AuthenticationData AUTHS[] = {

  /* Bank credentials */
  {.method = TALER_BANK_AUTH_BASIC,
   .details.basic.username = BANK_USERNAME,
   .details.basic.password = BANK_PASSWORD},

  /* Exchange credentials */
  {.method = TALER_BANK_AUTH_BASIC,
   .details.basic.username = EXCHANGE_USERNAME,
   .details.basic.password = EXCHANGE_PASSWORD },

  /* User credentials */
  {.method = TALER_BANK_AUTH_BASIC,
   .details.basic.username = USER_USERNAME,
   .details.basic.password = USER_PASSWORD } 
};

/**
 * Start the (Python) bank process.  Assume the port
 * is available and the database is clean.  Use the "prepare
 * bank" function to do such tasks.
 *
 * @param config_filename configuration filename.
 *
 * @return the process, or NULL if the process could not
 *         be started.
 */
struct GNUNET_OS_Process *
TALER_TESTING_run_bank (const char *config_filename)
{

  struct GNUNET_OS_Process *bank_proc;
  unsigned int iter;

  bank_proc = GNUNET_OS_start_process
    (GNUNET_NO,
     GNUNET_OS_INHERIT_STD_ALL,
     NULL, NULL, NULL,
     "taler-bank-manage",
     "taler-bank-manage",
     "-c", config_filename,
     "--with-db=postgres:///talercheck",
     "serve-http", NULL);
  if (NULL == bank_proc)
    BANK_FAIL ();

  /* give child time to start and bind against the socket */
  fprintf (stderr,
           "Waiting for `taler-bank-manage' to be ready");
  iter = 0;
  do
    {
      if (10 == iter)
      {
	fprintf (
          stderr,
	  "Failed to launch `taler-bank-manage' (or `wget')\n");
	GNUNET_OS_process_kill (bank_proc,
				SIGTERM);
	GNUNET_OS_process_wait (bank_proc);
	GNUNET_OS_process_destroy (bank_proc);
	BANK_FAIL ();
      }
      fprintf (stderr, ".");
      sleep (1);
      iter++;
    }
                                   /*FIXME: no hardcode port*/
  while (0 != system ("wget -q -t 1 -T 1 http://127.0.0.1:8081/" \
                      " -o /dev/null -O /dev/null"));
  fprintf (stderr, "\n");

  return bank_proc;

}

/**
 * Prepare the bank execution.  Check if the port is available
 * (and reset database?).
 *
 * @param config_filename configuration filename.
 *
 * @return the base url, or NULL upon errors.  Must be freed
 *         by the caller.
 */
char *
TALER_TESTING_prepare_bank (const char *config_filename)
{
  struct GNUNET_CONFIGURATION_Handle *cfg;
  unsigned long long port;
  struct GNUNET_OS_Process *dbreset_proc;
  enum GNUNET_OS_ProcessStatusType type;
  unsigned long code;
  char *base_url;

  cfg = GNUNET_CONFIGURATION_create ();

  if (GNUNET_OK != GNUNET_CONFIGURATION_load (cfg, config_filename))
    BANK_FAIL ();

  if (GNUNET_OK != GNUNET_CONFIGURATION_get_value_number
    (cfg, "bank",
     "HTTP_PORT", &port))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "bank",
                               "HTTP_PORT");
    GNUNET_CONFIGURATION_destroy (cfg);
    BANK_FAIL ();
  }
  GNUNET_CONFIGURATION_destroy (cfg);

  if (GNUNET_OK != GNUNET_NETWORK_test_port_free
    (IPPROTO_TCP, (uint16_t) port))
  {
    fprintf (stderr,
             "Required port %llu not available, skipping.\n",
	     port);
    BANK_FAIL ();
  }

  /* DB preparation */
  if (NULL ==
     (dbreset_proc = GNUNET_OS_start_process (
       GNUNET_NO,
       GNUNET_OS_INHERIT_STD_ALL,
       NULL, NULL, NULL,
       "taler-bank-manage",
       "taler-bank-manage",
       "-c", "bank.conf",
       "--with-db=postgres:///talercheck", /*FIXME: no hardcoded*/
       "django",
       "flush",
       "--no-input", NULL)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to flush the bank db.\n");
    BANK_FAIL ();
  }

  if (GNUNET_SYSERR ==
      GNUNET_OS_process_wait_status (dbreset_proc,
                                     &type,
                                     &code))
  {
    GNUNET_OS_process_destroy (dbreset_proc);
    BANK_FAIL ();
  }
  if ( (type == GNUNET_OS_PROCESS_EXITED) &&
       (0 != code) )
  {
    fprintf (stderr,
             "Failed to setup database\n");
    BANK_FAIL ();
  }
  if ( (type != GNUNET_OS_PROCESS_EXITED) ||
       (0 != code) )
  {
    fprintf (stderr,
             "Unexpected error running"
             " `taler-bank-manage django flush..'!\n");
    BANK_FAIL ();
  }

  GNUNET_OS_process_destroy (dbreset_proc);

  GNUNET_asprintf (&base_url,
                   "http://localhost:%llu/",
                   port);
  return base_url;
}


/* end of testing_api_helpers.c */
