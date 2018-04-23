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
 * @file exchange-lib/testing_api_helpers.c
 * @brief helper functions
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * Remove files from previous runs
 *
 * @param config_name configuration filename.
 */
void
TALER_TESTING_cleanup_files (const char *config_name)
{
  struct GNUNET_CONFIGURATION_Handle *cfg;
  char *dir;

  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_load (cfg,
                                 config_name))
  {
    GNUNET_break (0);
    GNUNET_CONFIGURATION_destroy (cfg);
    exit (77);
  }
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
  GNUNET_CONFIGURATION_destroy (cfg);
}


/**
 * Prepare launching an exchange.  Checks that the configured
 * port is available, runs taler-exchange-keyup,
 * taler-auditor-sign and taler-exchange-dbinit.  Does NOT
 * launch the exchange process itself.
 *
 * @param config_filename configuration file to use
 * @param base_url[out] will be set to the exchange base url,
 *        if the config has any; otherwise it will be set to
 *        NULL.
 * @return #GNUNET_OK on success, #GNUNET_NO if test should be
 *         skipped, #GNUNET_SYSERR on test failure
 */
int
TALER_TESTING_prepare_exchange (const char *config_filename,
                                char **base_url)
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
                                             base_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               "exchange",
                               "BASE_URL");
    *base_url = NULL;
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
 * Find denomination key matching the given amount.
 *
 * @param keys array of keys to search
 * @param amount coin value to look for
 * @return NULL if no matching key was found
 */
const struct TALER_EXCHANGE_DenomPublicKey *
TALER_TESTING_find_pk (const struct TALER_EXCHANGE_Keys *keys,
                       const struct TALER_Amount *amount)
{
  struct GNUNET_TIME_Absolute now;
  struct TALER_EXCHANGE_DenomPublicKey *pk;
  char *str;

  now = GNUNET_TIME_absolute_get ();
  for (unsigned int i=0;i<keys->num_denom_keys;i++)
  {
    pk = &keys->denom_keys[i];
    if ( (0 == TALER_amount_cmp (amount,
                                 &pk->value)) &&
         (now.abs_value_us >= pk->valid_from.abs_value_us) &&
         (now.abs_value_us <
          pk->withdraw_valid_until.abs_value_us) )
      return pk;
  }
  /* do 2nd pass to check if expiration times are to blame for
   * failure */
  str = TALER_amount_to_string (amount);
  for (unsigned int i=0;i<keys->num_denom_keys;i++)
  {
    pk = &keys->denom_keys[i];
    if ( (0 == TALER_amount_cmp (amount,
                                 &pk->value)) &&
         ( (now.abs_value_us < pk->valid_from.abs_value_us) ||
           (now.abs_value_us >
            pk->withdraw_valid_until.abs_value_us) ) )
    {
      GNUNET_log
        (GNUNET_ERROR_TYPE_WARNING,
         "Have denomination key for `%s', but with wrong"
         " expiration range %llu vs [%llu,%llu)\n",
         str,
         (unsigned long long) now.abs_value_us,
         (unsigned long long) pk->valid_from.abs_value_us,
         (unsigned long long)
           pk->withdraw_valid_until.abs_value_us);
      GNUNET_free (str);
      return NULL;
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "No denomination key for amount %s found\n",
              str);
  GNUNET_free (str);
  return NULL;
}


/**
 * Initialize scheduler loop and curl context for the testcase
 * including starting and stopping the exchange using the given
 * configuration file.
 *
 * @param main_cb routine containing all the commands to run.
 * @param main_cb_cls closure for @a main_cb, typically NULL.
 * @param config_file configuration file for the test-suite.
 *
 * @return FIXME: depends on what TALER_TESTING_setup returns.
 */
int
TALER_TESTING_setup_with_exchange (TALER_TESTING_Main main_cb,
                                   void *main_cb_cls,
                                   const char *config_filename)
{
  int result;
  unsigned int iter;
  struct GNUNET_OS_Process *exchanged;

  struct GNUNET_CONFIGURATION_Handle *cfg;
  unsigned long long port;

  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_load (cfg,
                                 config_filename))
    return GNUNET_NO;
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
    return GNUNET_NO;
  }

  GNUNET_CONFIGURATION_destroy (cfg);
  if (GNUNET_OK !=
      GNUNET_NETWORK_test_port_free (IPPROTO_TCP,
				     (uint16_t) port))
  {
    fprintf (stderr,
             "Required port %llu not available, skipping.\n",
	     port);
    return GNUNET_NO;
  }

  exchanged = GNUNET_OS_start_process (GNUNET_NO,
                                       GNUNET_OS_INHERIT_STD_ALL,
                                       NULL, NULL, NULL,
                                       "taler-exchange-httpd",
                                       "taler-exchange-httpd",
                                       "-c", config_filename,
                                       "-i",
                                       NULL);
  /* give child time to start and bind against the socket */
  fprintf (stderr,
           "Waiting for `taler-exchange-httpd' to be ready\n");
  iter = 0;
  do
    {
      if (10 == iter)
      {
	fprintf (stderr,
		 "Failed to launch `taler-exchange-httpd'"
                 " (or `wget')\n");
	GNUNET_OS_process_kill (exchanged,
				SIGTERM);
	GNUNET_OS_process_wait (exchanged);
	GNUNET_OS_process_destroy (exchanged);
	return 77;
      }
      fprintf (stderr, ".\n");
      sleep (1);
      iter++;
    }
  while (0 != system
    ("wget -q -t 1 -T 1 http://127.0.0.1:8081/keys"
     " -o /dev/null -O /dev/null"));

  result = TALER_TESTING_setup (main_cb,
                                main_cb_cls,
                                config_filename,
                                exchanged);
  GNUNET_break (0 ==
                GNUNET_OS_process_kill (exchanged,
                                        SIGTERM));
  GNUNET_break (GNUNET_OK ==
                GNUNET_OS_process_wait (exchanged));
  GNUNET_OS_process_destroy (exchanged);
  return result;
}


/**
 * Test port in URL string for availability.
 */
int
TALER_TESTING_url_port_free (const char *url)
{
  const char *port;
  long pnum;

  port = strrchr (url,
                  (unsigned char) ':');
  if (NULL == port)
    pnum = 80;
  else
    pnum = strtol (port + 1, NULL, 10);
  if (GNUNET_OK !=
      GNUNET_NETWORK_test_port_free (IPPROTO_TCP,
				     pnum))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Port %u not available.\n",
                (unsigned int) pnum);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Allocate and return a piece of wire-details.  Combines
 * the @a account_no and the @a bank_url to a
 * @a payto://-URL and adds some salt to create the JSON.
 *
 * @param account_no account number
 * @param bank_url the bank_url
 * @return JSON describing the account, including the
 *         payto://-URL of the account, must be manually decref'd
 */
json_t *
TALER_TESTING_make_wire_details (unsigned long long account_no,
                                 const char *bank_url)
{
  char *payto;
  json_t *ret;

  GNUNET_asprintf (&payto,
                   "payto://x-taler-bank/%s/%llu",
                   bank_url,
                   account_no);
  ret = json_pack ("{s:s, s:s}",
                   "url", payto,
                   "salt", "test-salt (must be constant for aggregation tests)");
  GNUNET_free (payto);
  return ret;
}


/**
 * Prepare launching a fakebank.  Check that the configuration
 * file has the right option, and that the port is available.
 * If everything is OK, return the configured URL of the fakebank.
 *
 * @param config_filename configuration file to use
 * @param config_section which account to use (must match x-taler-bank)
 * @return NULL on error, fakebank URL otherwise
 */
char *
TALER_TESTING_prepare_fakebank (const char *config_filename,
                                const char *config_section)
{
  struct GNUNET_CONFIGURATION_Handle *cfg;
  char *payto_url;
  char *fakebank_url;
  const char *start;
  const char *end;

  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK != GNUNET_CONFIGURATION_load (cfg,
                                              config_filename))
    return NULL;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             config_section,
                                             "URL",
                                             &payto_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               config_section,
                               "URL");
    GNUNET_CONFIGURATION_destroy (cfg);
    return NULL;
  }
  GNUNET_CONFIGURATION_destroy (cfg);
  if (0 != strncasecmp (payto_url,
                        "payto://x-taler-bank/",
                        strlen ("payto://x-taler-bank/")))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_WARNING,
                               config_section,
                               "URL",
                               "expected `x-taler-bank' payto://-URL");
    GNUNET_CONFIGURATION_destroy (cfg);
    GNUNET_free (payto_url);
    return NULL;
  }
  start = &payto_url [strlen ("payto://x-taler-bank/")];
  end = strchr (start,
                (unsigned char) '/');
  if (NULL == end)
    end = &start[strlen (start)];
  fakebank_url = GNUNET_strndup (start,
                                 end - start);
  GNUNET_free (payto_url);
  if (GNUNET_OK !=
      TALER_TESTING_url_port_free (fakebank_url))
  {
    GNUNET_free (fakebank_url);
    return NULL;
  }
  return fakebank_url;
}

/* end of testing_api_helpers.c */
