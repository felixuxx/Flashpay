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
 * @file auditor-lib/testing_auditor_api_helpers.c
 * @brief helper functions
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * Remove files from previous runs
 *
 * @param cls NULL
 * @param cfg configuration
 * @return #GNUNET_OK on success
 */
static int
cleanup_files_cfg (void *cls,
		   const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  if (GNUNET_OK !=
      TALER_TESTING_cleanup_files_cfg (NULL,
				       cfg))
    return GNUNET_SYSERR;
  // TODO: auditor-specific clean-up here!  
#if FIXME
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONFIGURATION_get_value_filename
                   (cfg,
                    "exchange",
                    "keydir",
                    &dir));
  if (GNUNET_YES ==
      GNUNET_DISK_directory_test (dir,
                                  GNUNET_NO))
    GNUNET_break (GNUNET_OK ==
                  GNUNET_DISK_directory_remove (dir));
  GNUNET_free (dir);
#endif

  return GNUNET_OK;
}


/**
 * Remove files from previous runs
 *
 * @param config_name configuration filename.
 */
void
TALER_TESTING_AUDITOR_cleanup_files (const char *config_name)
{
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_parse_and_run (config_name,
					  &cleanup_files_cfg,
					  NULL))
    exit (77);
}


/**
 * Initialize scheduler loop and curl context for the testcase
 * including starting and stopping the auditor and exchange using the
 * given configuration file.
 *
 * @param main_cb routine containing all the commands to run.
 * @param main_cb_cls closure for @a main_cb, typically NULL.
 * @param config_file configuration file for the test-suite.
 *
 * @return #GNUNET_OK if all is okay, != #GNUNET_OK otherwise.
 *         non-#GNUNET_OK codes are #GNUNET_SYSERR most of the
 *         time.
 */
int
TALER_TESTING_AUDITOR_setup_with_auditor (TALER_TESTING_Main main_cb,
					  void *main_cb_cls,
					  const char *config_filename)
{
  int result;
  struct GNUNET_OS_Process *exchanged;
  struct GNUNET_OS_Process *auditord;
  struct GNUNET_CONFIGURATION_Handle *cfg;
  unsigned long long port;
  char *serve;
  char *base_url;

  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_load (cfg,
                                 config_filename))
    return GNUNET_NO;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "SERVE",
                                             &serve))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "SERVE");
    GNUNET_CONFIGURATION_destroy (cfg);
    return GNUNET_NO;
  }

  if (0 == strcmp ("tcp", serve))
  {
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_number (cfg,
                                               "exchange",
                                               "PORT",
                                               &port))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "PORT");
      GNUNET_CONFIGURATION_destroy (cfg);
      GNUNET_free (serve);
      return GNUNET_NO;
    }

    if (GNUNET_OK !=
        GNUNET_NETWORK_test_port_free (IPPROTO_TCP,
  				     (uint16_t) port))
    {
      fprintf (stderr,
               "Required port %llu not available, skipping.\n",
  	     port);
      GNUNET_free (serve);
      return GNUNET_NO;
    }
  }
  GNUNET_free (serve);
  exchanged = GNUNET_OS_start_process (GNUNET_NO,
                                       GNUNET_OS_INHERIT_STD_ALL,
                                       NULL, NULL, NULL,
                                       "taler-exchange-httpd",
                                       "taler-exchange-httpd",
                                       "-c", config_filename,
                                       "-i",
                                       NULL);
  auditord = GNUNET_OS_start_process (GNUNET_NO,
				      GNUNET_OS_INHERIT_STD_ALL,
				      NULL, NULL, NULL,
				      "taler-auditor-httpd",
				      "taler-auditor-httpd",
				      "-c", config_filename,
				      NULL);

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &base_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    GNUNET_CONFIGURATION_destroy (cfg);
    return GNUNET_NO;
  }
  GNUNET_CONFIGURATION_destroy (cfg);

  if (0 != TALER_TESTING_wait_exchange_ready (base_url))
  {
    GNUNET_free (base_url);
    return 77;
  }
  GNUNET_free (base_url);
  
  /* NOTE: this blocks.  */
  result = TALER_TESTING_setup (main_cb,
                                main_cb_cls,
                                config_filename,
                                exchanged,
                                GNUNET_YES);
  GNUNET_break (0 ==
                GNUNET_OS_process_kill (exchanged,
                                        SIGTERM));
  GNUNET_break (0 ==
                GNUNET_OS_process_kill (auditord,
                                        SIGTERM));
  GNUNET_break (GNUNET_OK ==
                GNUNET_OS_process_wait (exchanged));
  GNUNET_break (GNUNET_OK ==
                GNUNET_OS_process_wait (auditord));
  GNUNET_OS_process_destroy (exchanged);
  GNUNET_OS_process_destroy (auditord);
  return result;
}


/* end of testing_auditor_api_helpers.c */
