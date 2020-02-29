/*
  This file is part of TALER
  Copyright (C) 2014-2018 Taler Systems SA

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
 * @file testing_api_twister_helpers.c
 * @brief helper functions for test library.
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */

#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_twister_testing_lib.h"

/**
 * Prepare twister for execution; mainly checks whether the
 * HTTP port is available and construct the base URL based on it.
 *
 * @param config_filename configuration file name.
 * @return twister base URL, NULL upon errors.
 */
char *
TALER_TWISTER_prepare_twister (const char *config_filename)
{
  struct GNUNET_CONFIGURATION_Handle *cfg;
  unsigned long long port;
  char *base_url;

  cfg = GNUNET_CONFIGURATION_create ();

  if (GNUNET_OK != GNUNET_CONFIGURATION_load
        (cfg, config_filename))
    TWISTER_FAIL ();

  if (GNUNET_OK != GNUNET_CONFIGURATION_get_value_number
        (cfg, "twister",
        "HTTP_PORT", &port))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "twister",
                               "HTTP_PORT");
    GNUNET_CONFIGURATION_destroy (cfg);
    TWISTER_FAIL ();
  }

  GNUNET_CONFIGURATION_destroy (cfg);

  if (GNUNET_OK != GNUNET_NETWORK_test_port_free
        (IPPROTO_TCP, (uint16_t) port))
  {
    fprintf (stderr,
             "Required port %llu not available, skipping.\n",
             port);
    TWISTER_FAIL ();
  }

  GNUNET_assert (0 < GNUNET_asprintf
                   (&base_url,
                   "http://localhost:%llu/",
                   port));

  return base_url;
}


/**
 * Run the twister service.
 *
 * @param config_filename configuration file name.
 * @return twister process handle, NULL upon errors.
 */
struct GNUNET_OS_Process *
TALER_TWISTER_run_twister (const char *config_filename)
{
  struct GNUNET_OS_Process *proc;
  struct GNUNET_OS_Process *client_proc;
  unsigned long code;
  enum GNUNET_OS_ProcessStatusType type;

  proc = GNUNET_OS_start_process (GNUNET_NO,
                                  GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-twister-service",
                                  "taler-twister-service",
                                  "-c", config_filename,
                                  NULL);
  if (NULL == proc)
    TWISTER_FAIL ();

  client_proc = GNUNET_OS_start_process (GNUNET_NO,
                                         GNUNET_OS_INHERIT_STD_ALL,
                                         NULL, NULL, NULL,
                                         "taler-twister",
                                         "taler-twister",
                                         "-c", config_filename,
                                         "-a", NULL);
  if (NULL == client_proc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not start the taler-twister client\n");
    GNUNET_OS_process_kill (proc, SIGTERM);
    GNUNET_OS_process_wait (proc);
    GNUNET_OS_process_destroy (proc);
    TWISTER_FAIL ();
  }


  if (GNUNET_SYSERR == GNUNET_OS_process_wait_status
        (client_proc, &type, &code))
  {
    GNUNET_OS_process_destroy (client_proc);
    GNUNET_OS_process_kill (proc, SIGTERM);
    GNUNET_OS_process_wait (proc);
    GNUNET_OS_process_destroy (proc);
    TWISTER_FAIL ();
  }
  if ( (type == GNUNET_OS_PROCESS_EXITED) &&
       (0 != code) )
  {
    fprintf (stderr, "Failed to check twister works.\n");
    GNUNET_OS_process_destroy (client_proc);
    GNUNET_OS_process_kill (proc, SIGTERM);
    GNUNET_OS_process_wait (proc);
    GNUNET_OS_process_destroy (proc);
    TWISTER_FAIL ();
  }
  if ( (type != GNUNET_OS_PROCESS_EXITED) ||
       (0 != code) )
  {
    fprintf (stderr, "Unexpected error running"
             " `taler-twister'!\n");
    GNUNET_OS_process_destroy (client_proc);
    GNUNET_OS_process_kill (proc, SIGTERM);
    GNUNET_OS_process_wait (proc);
    GNUNET_OS_process_destroy (proc);
    TWISTER_FAIL ();
  }
  GNUNET_OS_process_destroy (client_proc);

  return proc;
}
