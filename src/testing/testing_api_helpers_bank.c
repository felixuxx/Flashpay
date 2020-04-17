/*
  This file is part of TALER
  Copyright (C) 2018-2020 Taler Systems SA

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
 * @file testing/testing_api_helpers_bank.c
 * @brief convenience functions for bank tests.
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_testing_lib.h"
#include "taler_fakebank_lib.h"

#define BANK_FAIL() \
  do {GNUNET_break (0); return NULL; } while (0)


/**
 * Runs the Fakebank by guessing / extracting the portnumber
 * from the base URL.
 *
 * @param bank_url bank's base URL.
 * @param currency currency the bank uses
 * @return the fakebank process handle, or NULL if any
 *         error occurs.
 */
struct TALER_FAKEBANK_Handle *
TALER_TESTING_run_fakebank (const char *bank_url,
                            const char *currency)
{
  const char *port;
  long pnum;
  struct TALER_FAKEBANK_Handle *fakebankd;

  port = strrchr (bank_url,
                  (unsigned char) ':');
  if (NULL == port)
    pnum = 80;
  else
    pnum = strtol (port + 1, NULL, 10);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting Fakebank on port %u (%s)\n",
              (unsigned int) pnum,
              bank_url);
  fakebankd = TALER_FAKEBANK_start ((uint16_t) pnum,
                                    currency);
  if (NULL == fakebankd)
  {
    GNUNET_break (0);
    return NULL;
  }
  return fakebankd;
}


/**
 * Look for substring in a programs' name.
 *
 * @param prog program's name to look into
 * @param marker chunk to find in @a prog
 * @return #GNUNET_YES if @a marker is present, otherwise #GNUNET_NO
 */
int
TALER_TESTING_has_in_name (const char *prog,
                           const char *marker)
{
  size_t name_pos;
  size_t pos;

  if (! prog || ! marker)
    return GNUNET_NO;

  pos = 0;
  name_pos = 0;
  while (prog[pos])
  {
    if ('/' == prog[pos])
      name_pos = pos + 1;
    pos++;
  }
  if (name_pos == pos)
    return GNUNET_YES;
  return (NULL != strstr (prog + name_pos, marker));
}


/**
 * Start the (nexus) bank process.  Assume the port
 * is available and the database is clean.  Use the "prepare
 * bank" function to do such tasks.  This function is also
 * responsible to create the exchange EBICS subscriber at
 * the nexus.
 *
 * @param config_filename configuration filename.  Used to 
 * @return the process, or NULL if the process could not
 *         be started.
 */
struct GNUNET_OS_Process *
TALER_TESTING_run_nexus (const struct TALER_TESTING_BankConfiguration *bc)
{
  struct GNUNET_OS_Process *bank_proc;
  unsigned int iter;
  char *curl_check_cmd;
  char *curl_cmd;
  char *post_body;
  char *register_url;

  bank_proc = GNUNET_OS_start_process
                (GNUNET_NO,
                GNUNET_OS_INHERIT_STD_NONE,
                NULL, NULL, NULL,
                "nexus",
                "nexus",
                NULL);
  if (NULL == bank_proc)
  {
    BANK_FAIL ();
  }
  GNUNET_asprintf (&curl_check_cmd,
                   "curl -s %s",
                   bc->exchange_auth.wire_gateway_url);

  /* give child time to start and bind against the socket */
  fprintf (stderr,
           "Waiting for `nexus' to be ready (via %s)\n", curl_check_cmd);
  iter = 0;
  do
  {
    if (10 == iter)
    {
      fprintf (
        stderr,
        "Failed to launch `nexus'\n");
      GNUNET_OS_process_kill (bank_proc,
                              SIGTERM);
      GNUNET_OS_process_wait (bank_proc);
      GNUNET_OS_process_destroy (bank_proc);
      GNUNET_free (curl_check_cmd);
      BANK_FAIL ();
    }
    fprintf (stderr, ".");
    sleep (1);
    iter++;
  }
  while (0 != system (curl_check_cmd));

  GNUNET_asprintf (&post_body,
                   "{ \
                   \"ebicsURL\": \"http://mock\", \
                   \"userID\": \"mock\", \
                   \"partnerID\": \"mock\", \
                   \"hostID\": \"mock\", \
                   \"password\": \"%s\"}",
                   bc->exchange_auth.details.basic.password);
  GNUNET_asprintf (&register_url,
                   "http://localhost:5001/ebics/%s/subscribers",
                   bc->exchange_auth.details.basic.username);
  GNUNET_asprintf (&curl_cmd,
                   "curl -d'%s' -H'Content-Type: application/json' %s",
                   post_body,
                   register_url);

  if (0 != system (curl_cmd))
  {
    GNUNET_free (curl_check_cmd);
    GNUNET_free (curl_cmd);
    GNUNET_free (post_body);
    GNUNET_free (register_url);
    BANK_FAIL (); // includes logging and return (!)
  }

  GNUNET_free (curl_check_cmd);
  GNUNET_free (curl_cmd);
  GNUNET_free (post_body);
  GNUNET_free (register_url);
  fprintf (stderr, "\n");

  return bank_proc;
}

/**
 * Start the (Python) bank process.  Assume the port
 * is available and the database is clean.  Use the "prepare
 * bank" function to do such tasks.
 *
 * @param config_filename configuration filename.
 * @param bank_url base URL of the bank, used by `wget' to check
 *        that the bank was started right.
 * @return the process, or NULL if the process could not
 *         be started.
 */
struct GNUNET_OS_Process *
TALER_TESTING_run_bank (const char *config_filename,
                        const char *bank_url)
{
  struct GNUNET_OS_Process *bank_proc;
  unsigned int iter;
  char *wget_cmd;
  char *database;
  char *serve_cfg;
  char *serve_arg;
  struct GNUNET_CONFIGURATION_Handle *cfg;

  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_load (cfg,
                                 config_filename))
  {
    GNUNET_break (0);
    GNUNET_CONFIGURATION_destroy (cfg);
    exit (77);
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "bank",
                                             "database",
                                             &database))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               "bank",
                               "database");
    GNUNET_break (0);
    GNUNET_CONFIGURATION_destroy (cfg);
    exit (77);
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "bank",
                                             "serve",
                                             &serve_cfg))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               "bank",
                               "serve");
    GNUNET_break (0);
    GNUNET_CONFIGURATION_destroy (cfg);
    GNUNET_free (database);
    exit (77);
  }
  GNUNET_CONFIGURATION_destroy (cfg);

  serve_arg = "serve-http";
  if (0 != strcmp ("http", serve_cfg))
    serve_arg = "serve-uwsgi";
  GNUNET_free (serve_cfg);
  bank_proc = GNUNET_OS_start_process
                (GNUNET_NO,
                GNUNET_OS_INHERIT_STD_NONE,
                NULL, NULL, NULL,
                "taler-bank-manage-testing",
                "taler-bank-manage-testing",
                config_filename,
                database,
                serve_arg, NULL);
  GNUNET_free (database);
  if (NULL == bank_proc)
  {
    BANK_FAIL ();
  }

  GNUNET_asprintf (&wget_cmd,
                   "wget -q -t 2 -T 1 %s -o /dev/null -O /dev/null",
                   bank_url);

  /* give child time to start and bind against the socket */
  fprintf (stderr,
           "Waiting for `taler-bank-manage' to be ready (via %s)\n", wget_cmd);
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
      GNUNET_free (wget_cmd);
      BANK_FAIL ();
    }
    fprintf (stderr, ".");
    sleep (1);
    iter++;
  }
  while (0 != system (wget_cmd));
  GNUNET_free (wget_cmd);
  fprintf (stderr, "\n");

  return bank_proc;

}

/**
 * Prepare the Nexus execution.  Check if the port is available
 * and delete old database.
 *
 * @param config_filename configuration file name.
 * @param reset_db should we reset the bank's database
 * @param config_section section of the configuration with the exchange's account
 * @param[out] bc set to the bank's configuration data
 * @return the base url, or NULL upon errors.  Must be freed
 *         by the caller.
 */
int
TALER_TESTING_prepare_nexus (const char *config_filename,
                             int reset_db,
                             const char *config_section,
                             struct TALER_TESTING_BankConfiguration *bc)
{
  struct GNUNET_CONFIGURATION_Handle *cfg;
  unsigned long long port;
  struct GNUNET_OS_Process *dbreset_proc;
  enum GNUNET_OS_ProcessStatusType type;
  unsigned long code;
  char *database = NULL; // silence compiler
  char *exchange_payto_uri;

  cfg = GNUNET_CONFIGURATION_create ();

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_load (cfg, config_filename))
  {
    GNUNET_CONFIGURATION_destroy (cfg);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             config_section,
                                             "PAYTO_URI",
                                             &exchange_payto_uri))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               config_section,
                               "PAYTO_URI");
    GNUNET_CONFIGURATION_destroy (cfg);
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
                                             "bank",
                                             "HTTP_PORT",
                                             &port))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "bank",
                               "HTTP_PORT");
    GNUNET_CONFIGURATION_destroy (cfg);
    GNUNET_free (database);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      GNUNET_NETWORK_test_port_free (IPPROTO_TCP,
                                     (uint16_t) port))
  {
    fprintf (stderr,
             "Required port %llu not available, skipping.\n",
             port);
    GNUNET_break (0);
    GNUNET_free (database);
    GNUNET_CONFIGURATION_destroy (cfg);
    return GNUNET_SYSERR;
  }

  /* DB preparation */
  if (GNUNET_YES == reset_db)
  {
    if (NULL ==
        (dbreset_proc = GNUNET_OS_start_process (
           GNUNET_NO,
           GNUNET_OS_INHERIT_STD_NONE,
           NULL, NULL, NULL,
           "rm",
           "rm",
           "-f",
           "libeufin-nexus.sqlite3", NULL)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to invoke db-removal command.\n");
      GNUNET_free (database);
      GNUNET_CONFIGURATION_destroy (cfg);
      return GNUNET_SYSERR;
    }
    if (GNUNET_SYSERR ==
        GNUNET_OS_process_wait_status (dbreset_proc,
                                       &type,
                                       &code))
    {
      GNUNET_OS_process_destroy (dbreset_proc);
      GNUNET_break (0);
      GNUNET_CONFIGURATION_destroy (cfg);
      return GNUNET_SYSERR;
    }
    if ( (type == GNUNET_OS_PROCESS_EXITED) &&
         (0 != code) )
    {
      fprintf (stderr,
               "db-removal command was unsuccessful\n");
      GNUNET_break (0);
      GNUNET_CONFIGURATION_destroy (cfg);
      return GNUNET_SYSERR;
    }
    if ( (type != GNUNET_OS_PROCESS_EXITED) ||
         (0 != code) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Unexpected error running `rm libeufin-nexus.sqlite3'!\n");
      GNUNET_break (0);
      GNUNET_CONFIGURATION_destroy (cfg);
      return GNUNET_SYSERR;
    }
    GNUNET_OS_process_destroy (dbreset_proc);
  }
  if (GNUNET_OK !=
      TALER_BANK_auth_parse_cfg (cfg,
                                 config_section,
                                 &bc->exchange_auth))
  {
    GNUNET_break (0);
    GNUNET_CONFIGURATION_destroy (cfg);
    return GNUNET_SYSERR;
  }
  GNUNET_CONFIGURATION_destroy (cfg);
  bc->exchange_payto = exchange_payto_uri;
  bc->user42_payto = "payto://x-taler-bank/localhost/42";
  bc->user43_payto = "payto://x-taler-bank/localhost/43";
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Relying on nexus %s on port %u\n",
              bc->exchange_auth.wire_gateway_url,
              (unsigned int) port);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO, "exchange payto: %s\n",
              bc->exchange_payto);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO, "user42_payto: %s\n",
              bc->user42_payto);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO, "user42_payto: %s\n",
              bc->user43_payto);
  return GNUNET_OK;
}

/**
 * Prepare the bank execution.  Check if the port is available
 * and reset database.
 *
 * @param config_filename configuration file name.
 * @param reset_db should we reset the bank's database
 * @param config_section section of the configuration with the exchange's account
 * @param[out] bc set to the bank's configuration data
 * @return the base url, or NULL upon errors.  Must be freed
 *         by the caller.
 */
int
TALER_TESTING_prepare_bank (const char *config_filename,
                            int reset_db,
                            const char *config_section,
                            struct TALER_TESTING_BankConfiguration *bc)
{
  struct GNUNET_CONFIGURATION_Handle *cfg;
  unsigned long long port;
  struct GNUNET_OS_Process *dbreset_proc;
  enum GNUNET_OS_ProcessStatusType type;
  unsigned long code;
  char *database;
  char *exchange_payto_uri;

  cfg = GNUNET_CONFIGURATION_create ();

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_load (cfg, config_filename))
  {
    GNUNET_CONFIGURATION_destroy (cfg);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "bank",
                                             "DATABASE",
                                             &database))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "bank",
                               "DATABASE");
    GNUNET_CONFIGURATION_destroy (cfg);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             config_section,
                                             "PAYTO_URI",
                                             &exchange_payto_uri))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               config_section,
                               "PAYTO_URI");
    GNUNET_CONFIGURATION_destroy (cfg);
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
                                             "bank",
                                             "HTTP_PORT",
                                             &port))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "bank",
                               "HTTP_PORT");
    GNUNET_CONFIGURATION_destroy (cfg);
    GNUNET_free (database);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      GNUNET_NETWORK_test_port_free (IPPROTO_TCP,
                                     (uint16_t) port))
  {
    fprintf (stderr,
             "Required port %llu not available, skipping.\n",
             port);
    GNUNET_break (0);
    GNUNET_free (database);
    GNUNET_CONFIGURATION_destroy (cfg);
    return GNUNET_SYSERR;
  }

  /* DB preparation */
  if (GNUNET_YES == reset_db)
  {
    if (NULL ==
        (dbreset_proc = GNUNET_OS_start_process (
           GNUNET_NO,
           GNUNET_OS_INHERIT_STD_NONE,
           NULL, NULL, NULL,
           "taler-bank-manage",
           "taler-bank-manage",
           "-c", config_filename,
           "--with-db", database,
           "django",
           "flush",
           "--no-input", NULL)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to flush the bank db.\n");
      GNUNET_free (database);
      GNUNET_CONFIGURATION_destroy (cfg);
      return GNUNET_SYSERR;
    }
    GNUNET_free (database);

    if (GNUNET_SYSERR ==
        GNUNET_OS_process_wait_status (dbreset_proc,
                                       &type,
                                       &code))
    {
      GNUNET_OS_process_destroy (dbreset_proc);
      GNUNET_break (0);
      GNUNET_CONFIGURATION_destroy (cfg);
      return GNUNET_SYSERR;
    }
    if ( (type == GNUNET_OS_PROCESS_EXITED) &&
         (0 != code) )
    {
      fprintf (stderr,
               "Failed to setup database\n");
      GNUNET_break (0);
      GNUNET_CONFIGURATION_destroy (cfg);
      return GNUNET_SYSERR;
    }
    if ( (type != GNUNET_OS_PROCESS_EXITED) ||
         (0 != code) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Unexpected error running `taler-bank-manage django flush'!\n");
      GNUNET_break (0);
      GNUNET_CONFIGURATION_destroy (cfg);
      return GNUNET_SYSERR;
    }
    GNUNET_OS_process_destroy (dbreset_proc);
  }
  if (GNUNET_OK !=
      TALER_BANK_auth_parse_cfg (cfg,
                                 config_section,
                                 &bc->exchange_auth))
  {
    GNUNET_break (0);
    GNUNET_CONFIGURATION_destroy (cfg);
    return GNUNET_SYSERR;
  }
  GNUNET_CONFIGURATION_destroy (cfg);
  bc->exchange_payto = exchange_payto_uri;
  bc->user42_payto = "payto://x-taler-bank/localhost/42";
  bc->user43_payto = "payto://x-taler-bank/localhost/43";
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Using pybank %s on port %u\n",
              bc->exchange_auth.wire_gateway_url,
              (unsigned int) port);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO, "exchange payto: %s\n",
              bc->exchange_payto);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO, "user42_payto: %s\n",
              bc->user42_payto);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO, "user42_payto: %s\n",
              bc->user43_payto);
  return GNUNET_OK;
}


/**
 * Prepare launching a fakebank.  Check that the configuration
 * file has the right option, and that the port is available.
 * If everything is OK, return the configuration data of the fakebank.
 *
 * @param config_filename configuration file to use
 * @param config_section which account to use (must match x-taler-bank)
 * @param[out] bc set to the bank's configuration data
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_prepare_fakebank (const char *config_filename,
                                const char *config_section,
                                struct TALER_TESTING_BankConfiguration *bc)
{
  struct GNUNET_CONFIGURATION_Handle *cfg;
  unsigned long long fakebank_port;
  char *exchange_payto_uri;

  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK != GNUNET_CONFIGURATION_load (cfg,
                                              config_filename))
    return GNUNET_SYSERR;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
                                             "BANK",
                                             "HTTP_PORT",
                                             &fakebank_port))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               "BANK",
                               "HTTP_PORT");
    GNUNET_CONFIGURATION_destroy (cfg);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             config_section,
                                             "PAYTO_URI",
                                             &exchange_payto_uri))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               config_section,
                               "PAYTO_URI");
    GNUNET_CONFIGURATION_destroy (cfg);
    return GNUNET_SYSERR;
  }
  {
    char *exchange_xtalerbank_account;

    exchange_xtalerbank_account
      = TALER_xtalerbank_account_from_payto (exchange_payto_uri);
    if (NULL == exchange_xtalerbank_account)
    {
      GNUNET_break (0);
      GNUNET_free (exchange_payto_uri);
      return GNUNET_SYSERR;
    }
    GNUNET_asprintf (&bc->exchange_auth.wire_gateway_url,
                     "http://localhost:%u/%s/",
                     (unsigned int) fakebank_port,
                     exchange_xtalerbank_account);
    GNUNET_free (exchange_xtalerbank_account);
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Using fakebank %s on port %u\n",
              bc->exchange_auth.wire_gateway_url,
              (unsigned int) fakebank_port);

  GNUNET_CONFIGURATION_destroy (cfg);
  if (GNUNET_OK !=
      TALER_TESTING_url_port_free (bc->exchange_auth.wire_gateway_url))
  {
    GNUNET_free (bc->exchange_auth.wire_gateway_url);
    bc->exchange_auth.wire_gateway_url = NULL;
    GNUNET_free (exchange_payto_uri);
    return GNUNET_SYSERR;
  }
  /* Now we know it's the fake bank, for purpose of authentication, we
   * don't have any auth. */
  bc->exchange_auth.method = TALER_BANK_AUTH_NONE;
  bc->exchange_payto = exchange_payto_uri;
  bc->user42_payto = "payto://x-taler-bank/localhost/42";
  bc->user43_payto = "payto://x-taler-bank/localhost/43";
  GNUNET_log (GNUNET_ERROR_TYPE_INFO, "exchange payto: %s\n",
              bc->exchange_payto);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO, "user42_payto: %s\n",
              bc->user42_payto);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO, "user42_payto: %s\n",
              bc->user43_payto);
  return GNUNET_OK;
}


/**
 * Allocate and return a piece of wire-details.  Combines
 * a @a payto -URL and adds some salt to create the JSON.
 *
 * @param payto payto://-URL to encapsulate
 * @return JSON describing the account, including the
 *         payto://-URL of the account, must be manually decref'd
 */
json_t *
TALER_TESTING_make_wire_details (const char *payto)
{
  return json_pack ("{s:s, s:s}",
                    "payto_uri", payto,
                    "salt",
                    "test-salt (must be constant for aggregation tests)");
}


/* end of testing_api_helpers_bank.c */
