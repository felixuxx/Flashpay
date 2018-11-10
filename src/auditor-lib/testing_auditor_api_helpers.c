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
 * @param config_name configuration filename.
 */
void
TALER_TESTING_AUDITOR_cleanup_files (const char *config_name)
{
  struct GNUNET_CONFIGURATION_Handle *cfg;
  char *dir;
  
  TALER_TESTING_cleanup_files (config_name);
  // TODO: auditor-specific clean-up here!
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_load (cfg,
                                 config_name))
  {
    GNUNET_break (0);
    GNUNET_CONFIGURATION_destroy (cfg);
    exit (77);
  }
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
  GNUNET_CONFIGURATION_destroy (cfg);
}


/**
 * Prepare launching an auditor and exchange.  Checks that the configured
 * port is available, runs taler-exchange-keyup, taler-auditor-exchange,
 * taler-auditor-sign and taler-exchange-dbinit.  Does NOT
 * launch the exchange process itself.
 *
 * @param config_filename configuration file to use
 * @param auditor_base_url[out] will be set to the auditor base url,
 *        if the config has any; otherwise it will be set to
 *        NULL.
 * @param exchange_base_url[out] will be set to the exchange base url,
 *        if the config has any; otherwise it will be set to
 *        NULL.
 * @return #GNUNET_OK on success, #GNUNET_NO if test should be
 *         skipped, #GNUNET_SYSERR on test failure
 */
int
TALER_TESTING_AUDITOR_prepare_auditor (const char *config_filename,
				       char **auditor_base_url,
				       char **exchange_base_url)
{
  struct GNUNET_OS_Process *proc;
  enum GNUNET_OS_ProcessStatusType type;
  unsigned long code;
  struct GNUNET_CONFIGURATION_Handle *cfg;
  char *test_home_dir;
  char *signed_keys_out;
  char *exchange_master_pub;

  proc = GNUNET_OS_start_process (GNUNET_NO,
                                  GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-exchange-keyup",
                                  "taler-exchange-keyup",
                                  "-c", config_filename,
                                  "-o", "auditor.in",
                                  NULL);
  if (NULL == proc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		"Failed to run `taler-exchange-keyup`,"
                " is your PATH correct?\n");
    return GNUNET_NO;
  }
  GNUNET_OS_process_wait (proc);
  GNUNET_OS_process_destroy (proc);

  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK != GNUNET_CONFIGURATION_load
    (cfg, config_filename))
    return GNUNET_SYSERR;

   if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "BASE_URL",
                                             exchange_base_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               "exchange",
                               "BASE_URL");
    *exchange_base_url = NULL;
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               "paths",
                                               "TALER_TEST_HOME",
                                               &test_home_dir))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "paths",
                               "TALER_TEST_HOME");
    GNUNET_CONFIGURATION_destroy (cfg);
    return GNUNET_SYSERR;
  }

  GNUNET_asprintf (&signed_keys_out,
                   "%s/.local/share/taler/auditors/auditor.out",
                   test_home_dir);
  GNUNET_free (test_home_dir);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "MASTER_PUBLIC_KEY",
                                             &exchange_master_pub))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "MASTER_PUBLIC_KEY");
    GNUNET_CONFIGURATION_destroy (cfg);
    return GNUNET_SYSERR;
  }

  GNUNET_CONFIGURATION_destroy (cfg);

  proc = GNUNET_OS_start_process (GNUNET_NO,
                                  GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-auditor-sign",
                                  "taler-auditor-sign",
                                  "-c", config_filename,
                                  "-u", "http://auditor/",
                                  "-m", exchange_master_pub,
                                  "-r", "auditor.in",
                                  "-o", signed_keys_out,
                                  NULL);
  if (NULL == proc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		"Failed to run `taler-auditor-sign`,"
                " is your PATH correct?\n");
    GNUNET_free (signed_keys_out);
    GNUNET_free (exchange_master_pub);
    return GNUNET_NO;
  }


  GNUNET_free (exchange_master_pub);
  GNUNET_free (signed_keys_out);
  GNUNET_OS_process_wait (proc);
  GNUNET_OS_process_destroy (proc);

  /* Reset exchange database.  */
  proc = GNUNET_OS_start_process (GNUNET_NO,
                                  GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-exchange-dbinit",
                                  "taler-exchange-dbinit",
                                  "-c", config_filename,
                                  "-r",
                                  NULL);
  if (NULL == proc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		"Failed to run `taler-exchange-dbinit`,"
                " is your PATH correct?\n");

    return GNUNET_NO;
  }
  if (GNUNET_SYSERR ==
      GNUNET_OS_process_wait_status (proc,
                                     &type,
                                     &code))
  {
    GNUNET_break (0);
    GNUNET_OS_process_destroy (proc);
    return GNUNET_SYSERR;
  }
  GNUNET_OS_process_destroy (proc);
  if ( (type == GNUNET_OS_PROCESS_EXITED) &&
       (0 != code) )
  {
    fprintf (stderr,
             "Failed to setup (exchange) database\n");
    return GNUNET_NO;
  }
  if ( (type != GNUNET_OS_PROCESS_EXITED) ||
       (0 != code) )
  {
    fprintf (stderr,
             "Unexpected error running"
             " `taler-exchange-dbinit'!\n");
    return GNUNET_SYSERR;
  }


  /* Reset auditor database.  */

  proc = GNUNET_OS_start_process (GNUNET_NO,
                                  GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-auditor-dbinit",
                                  "taler-auditor-dbinit",
                                  "-c", config_filename,
                                  "-r",
                                  NULL);
  if (NULL == proc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		"Failed to run `taler-auditor-dbinit`,"
                " is your PATH correct?\n");

    return GNUNET_NO;
  }
  if (GNUNET_SYSERR ==
      GNUNET_OS_process_wait_status (proc,
                                     &type,
                                     &code))
  {
    GNUNET_break (0);
    GNUNET_OS_process_destroy (proc);
    return GNUNET_SYSERR;
  }
  GNUNET_OS_process_destroy (proc);
  if ( (type == GNUNET_OS_PROCESS_EXITED) &&
       (0 != code) )
  {
    fprintf (stderr,
             "Failed to setup (auditor) database\n");
    return GNUNET_NO;
  }
  if ( (type != GNUNET_OS_PROCESS_EXITED) ||
       (0 != code) )
  {
    fprintf (stderr,
             "Unexpected error running"
             " `taler-auditor-dbinit'!\n");
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


/**
 * Wait for the exchange to have started. Waits for at
 * most 10s, after that returns 77 to indicate an error.
 *
 * @param base_url what URL should we expect the exchange
 *        to be running at
 * @return 0 on success
 */
int
TALER_TESTING_AUDITOR_wait_auditor_ready (const char *base_url)
{
  char *wget_cmd;
  unsigned int iter;

  GNUNET_asprintf (&wget_cmd,
                   "wget -q -t 1 -T 1 %sversion"
                   " -o /dev/null -O /dev/null",
                   base_url); // make sure ends with '/'
  /* give child time to start and bind against the socket */
  fprintf (stderr,
           "Waiting for `taler-auditor-httpd' to be ready\n");
  iter = 0;
  do
    {
      if (10 == iter)
      {
	fprintf (stderr,
		 "Failed to launch `taler-auditor-httpd' (or `wget')\n");
        GNUNET_free (wget_cmd);
	return 77;
      }
      fprintf (stderr, ".\n");
      sleep (1);
      iter++;
    }
  while (0 != system (wget_cmd));
  GNUNET_free (wget_cmd);
  return 0;
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
  GNUNET_break (GNUNET_OK ==
                GNUNET_OS_process_wait (exchanged));
  GNUNET_OS_process_destroy (exchanged);
  return result;
}


/* end of testing_auditor_api_helpers.c */
