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
 * @file testing/testing_api_helpers_exchange.c
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
 * Run multiple taler-exchange-httpd processes in
 * parallel using GNU parallel?
 */
#define GNU_PARALLEL 0


void
TALER_TESTING_cleanup_files (const char *config_name)
{
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_parse_and_run (config_name,
                                          &TALER_TESTING_cleanup_files_cfg,
                                          NULL))
    exit (77);
}


/**
 * Remove @a option directory from @a section in @a cfg.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
remove_dir (const struct GNUNET_CONFIGURATION_Handle *cfg,
            const char *section,
            const char *option)
{
  char *dir;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               section,
                                               option,
                                               &dir))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               option);
    return GNUNET_SYSERR;
  }
  if (GNUNET_YES ==
      GNUNET_DISK_directory_test (dir,
                                  GNUNET_NO))
    GNUNET_break (GNUNET_OK ==
                  GNUNET_DISK_directory_remove (dir));
  GNUNET_free (dir);
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_TESTING_cleanup_files_cfg (void *cls,
                                 const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  char *dir;

  (void) cls;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               "exchange-offline",
                                               "SECM_TOFU_FILE",
                                               &dir))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange-offline",
                               "SECM_TOFU_FILE");
    return GNUNET_SYSERR;
  }
  if ( (0 != unlink (dir)) &&
       (ENOENT != errno) )
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "unlink",
                              dir);
    GNUNET_free (dir);
    return GNUNET_SYSERR;
  }
  GNUNET_free (dir);
  if (GNUNET_OK !=
      remove_dir (cfg,
                  "taler-exchange-secmod-eddsa",
                  "KEY_DIR"))
    return GNUNET_SYSERR;
  if (GNUNET_OK !=
      remove_dir (cfg,
                  "taler-exchange-secmod-rsa",
                  "KEY_DIR"))
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_TESTING_run_auditor_exchange (const char *config_filename,
                                    const char *exchange_master_pub,
                                    const char *exchange_base_url,
                                    int do_remove)
{
  struct GNUNET_OS_Process *proc;
  enum GNUNET_OS_ProcessStatusType type;
  unsigned long code;

  TALER_LOG_DEBUG ("Add exchange (%s,%s) to the auditor\n",
                   exchange_base_url,
                   exchange_master_pub);

  proc = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-auditor-exchange",
                                  "taler-auditor-exchange",
                                  "-c", config_filename,
                                  "-u", exchange_base_url,
                                  "-m", exchange_master_pub,
                                  (GNUNET_YES == do_remove)
                                  ? "-r"
                                  : NULL,
                                  NULL);
  if (NULL == proc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to run `taler-auditor-exchange`, is your PATH correct?\n");
    return GNUNET_SYSERR;
  }
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_OS_process_wait_status (proc,
                                                &type,
                                                &code));
  GNUNET_OS_process_destroy (proc);
  if ( (0 != code) ||
       (GNUNET_OS_PROCESS_EXITED != type) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "taler-auditor-exchange terminated with error (%d/%d)\n",
                (int) type,
                (int) code);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_TESTING_exchange_db_reset (const char *config_filename)
{
  struct GNUNET_OS_Process *proc;
  enum GNUNET_OS_ProcessStatusType type;
  unsigned long code;

  proc = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-exchange-dbinit",
                                  "taler-exchange-dbinit",
                                  "-c", config_filename,
                                  "-r",
                                  NULL);
  if (NULL == proc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to run `taler-exchange-dbinit`, is your PATH correct?\n");
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
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to setup (exchange) database, exit code %d\n",
                (int) code);
    return GNUNET_NO;
  }
  if ( (type != GNUNET_OS_PROCESS_EXITED) ||
       (0 != code) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected error (%d/%d) running `taler-exchange-dbinit'!\n",
                (int) type,
                (int) code);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_TESTING_auditor_db_reset (const char *config_filename)
{
  struct GNUNET_OS_Process *proc;
  enum GNUNET_OS_ProcessStatusType type;
  unsigned long code;

  proc = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-auditor-dbinit",
                                  "taler-auditor-dbinit",
                                  "-c", config_filename,
                                  "-R",
                                  NULL);
  if (NULL == proc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to run `taler-auditor-dbinit`, is your PATH correct?\n");
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
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to setup (auditor) database, exit code %d\n",
                (int) code);
    return GNUNET_NO;
  }
  if ( (type != GNUNET_OS_PROCESS_EXITED) ||
       (0 != code) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected error (%d/%d) running `taler-auditor-dbinit'!\n",
                (int) type,
                (int) code);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Type of closure for
 * #sign_keys_for_exchange.
 */
struct SignInfo
{
  /**
   * Members will be set to the exchange configuration.
   */
  struct TALER_TESTING_ExchangeConfiguration *ec;

  /**
   * Name of the configuration file to use.
   */
  const char *config_filename;

  /**
   * Did we reset the database?
   */
  int db_reset;
};


/**
 * Sign the keys for an exchange given configuration @a cfg.
 * The information to be signed must be in a file "auditor.in".
 *
 * @param[in,out] cls a `struct SignInfo` with further parameters
 * @param cfg configuration to use
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
sign_keys_for_exchange (void *cls,
                        const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  struct SignInfo *si = cls;
  char *exchange_master_pub;
  int ret;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &si->ec->exchange_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               "exchange",
                               "BASE_URL");
    si->ec->exchange_url = NULL;
    return GNUNET_NO;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "auditor",
                                             "BASE_URL",
                                             &si->ec->auditor_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               "auditor",
                               "BASE_URL");
    GNUNET_free (si->ec->exchange_url);
    si->ec->exchange_url = NULL;
    si->ec->auditor_url = NULL;
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "MASTER_PUBLIC_KEY",
                                             &exchange_master_pub))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "MASTER_PUBLIC_KEY");
    ret = GNUNET_SYSERR;
    goto fail;
  }
  if ( (GNUNET_OK !=
        TALER_TESTING_run_auditor_exchange (si->config_filename,
                                            exchange_master_pub,
                                            si->ec->exchange_url,
                                            GNUNET_NO)) &&
       (GNUNET_YES == si->db_reset) )
  {
    ret = GNUNET_NO;
    goto fail;
  }
  GNUNET_free (exchange_master_pub);
  return GNUNET_OK;
fail:
  GNUNET_free (si->ec->exchange_url);
  GNUNET_free (si->ec->auditor_url);
  si->ec->exchange_url = NULL;
  si->ec->auditor_url = NULL;
  return ret;
}


enum GNUNET_GenericReturnValue
TALER_TESTING_prepare_exchange (const char *config_filename,
                                int reset_db,
                                struct TALER_TESTING_ExchangeConfiguration *ec)
{
  struct SignInfo si = {
    .config_filename = config_filename,
    .ec = ec,
    .db_reset = reset_db
  };

  if (GNUNET_YES == reset_db)
  {
    if (GNUNET_OK !=
        TALER_TESTING_exchange_db_reset (config_filename))
      return GNUNET_NO;
    if (GNUNET_OK !=
        TALER_TESTING_auditor_db_reset (config_filename))
      return GNUNET_NO;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_parse_and_run (config_filename,
                                          &sign_keys_for_exchange,
                                          &si))
    return GNUNET_NO;
  return GNUNET_OK;
}


const struct TALER_EXCHANGE_DenomPublicKey *
TALER_TESTING_find_pk (const struct TALER_EXCHANGE_Keys *keys,
                       const struct TALER_Amount *amount)
{
  struct GNUNET_TIME_Timestamp now;
  struct TALER_EXCHANGE_DenomPublicKey *pk;
  char *str;

  now = GNUNET_TIME_timestamp_get ();
  for (unsigned int i = 0; i<keys->num_denom_keys; i++)
  {
    pk = &keys->denom_keys[i];
    if ( (0 == TALER_amount_cmp (amount,
                                 &pk->value)) &&
         (GNUNET_TIME_timestamp_cmp (now,
                                     >=,
                                     pk->valid_from)) &&
         (GNUNET_TIME_timestamp_cmp (now,
                                     <,
                                     pk->withdraw_valid_until)) )
      return pk;
  }
  /* do 2nd pass to check if expiration times are to blame for
   * failure */
  str = TALER_amount_to_string (amount);
  for (unsigned int i = 0; i<keys->num_denom_keys; i++)
  {
    pk = &keys->denom_keys[i];
    if ( (0 == TALER_amount_cmp (amount,
                                 &pk->value)) &&
         (GNUNET_TIME_timestamp_cmp (now,
                                     <,
                                     pk->valid_from) ||
          GNUNET_TIME_timestamp_cmp (now,
                                     >,
                                     pk->withdraw_valid_until) ) )
    {
      GNUNET_log
        (GNUNET_ERROR_TYPE_WARNING,
        "Have denomination key for `%s', but with wrong"
        " expiration range %llu vs [%llu,%llu)\n",
        str,
        (unsigned long long) now.abs_time.abs_value_us,
        (unsigned long long) pk->valid_from.abs_time.abs_value_us,
        (unsigned long long) pk->withdraw_valid_until.abs_time.abs_value_us);
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


int
TALER_TESTING_wait_exchange_ready (const char *base_url)
{
  char *wget_cmd;
  unsigned int iter;

  GNUNET_asprintf (&wget_cmd,
                   "wget -q -t 1 -T 1 %sseed -o /dev/null -O /dev/null",
                   base_url); // make sure ends with '/'
  /* give child time to start and bind against the socket */
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Waiting for `taler-exchange-httpd` service to be ready (check with: %s)\n",
              wget_cmd);
  iter = 0;
  do
  {
    if (10 == iter)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to launch `taler-exchange-httpd` service (or `wget')\n");
      GNUNET_free (wget_cmd);
      return 77;
    }
    sleep (1);
    iter++;
  }
  while (0 != system (wget_cmd));
  GNUNET_free (wget_cmd);
  return 0;
}


int
TALER_TESTING_wait_httpd_ready (const char *base_url)
{
  char *wget_cmd;
  unsigned int iter;

  GNUNET_asprintf (&wget_cmd,
                   "wget -q -t 1 -T 1 %s -o /dev/null -O /dev/null",
                   base_url); // make sure ends with '/'
  /* give child time to start and bind against the socket */
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Waiting for HTTP service to be ready (check with: %s)\n",
              wget_cmd);
  iter = 0;
  do
  {
    if (10 == iter)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to launch HTTP service (or `wget')\n");
      GNUNET_free (wget_cmd);
      return 77;
    }
    sleep (1);
    iter++;
  }
  while (0 != system (wget_cmd));
  GNUNET_free (wget_cmd);
  return 0;
}


/**
 * Wait for the auditor to have started. Waits for at
 * most 10s, after that returns 77 to indicate an error.
 *
 * @param base_url what URL should we expect the auditor
 *        to be running at
 * @return 0 on success
 */
int
TALER_TESTING_wait_auditor_ready (const char *base_url)
{
  char *wget_cmd;
  unsigned int iter;

  GNUNET_asprintf (&wget_cmd,
                   "wget -q -t 1 -T 1 %sversion -o /dev/null -O /dev/null",
                   base_url); // make sure ends with '/'
  /* give child time to start and bind against the socket */
  fprintf (stderr,
           "Waiting for `taler-auditor-httpd' to be ready at %s\n",
           base_url);
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


enum GNUNET_GenericReturnValue
TALER_TESTING_setup_with_exchange (TALER_TESTING_Main main_cb,
                                   void *main_cb_cls,
                                   const char *config_file)
{
  struct TALER_TESTING_SetupContext setup_ctx = {
    .config_filename = config_file,
    .main_cb = main_cb,
    .main_cb_cls = main_cb_cls
  };
  enum GNUNET_GenericReturnValue result;

  result =
    GNUNET_CONFIGURATION_parse_and_run (config_file,
                                        &TALER_TESTING_setup_with_exchange_cfg,
                                        &setup_ctx);
  if (GNUNET_OK != result)
    return result;
  return GNUNET_OK;
}


/**
 * Stop taler-exchange-crypto helpers.
 *
 * @param[in] helpers the process handles.
 */
static void
stop_helpers (struct GNUNET_OS_Process *helpers[3])
{
  for (unsigned int i = 0; i<3; i++)
  {
    if (NULL == helpers[i])
      continue;
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (helpers[i],
                                          SIGTERM));
    GNUNET_break (GNUNET_OK ==
                  GNUNET_OS_process_wait (helpers[i]));
    GNUNET_OS_process_destroy (helpers[i]);
  }
}


/**
 * Start taler-exchange-crypto helpers.
 *
 * @param config_filename configuration file to use
 * @param[out] helpers where to store the process handles.
 */
static enum GNUNET_GenericReturnValue
start_helpers (const char *config_filename,
               struct GNUNET_OS_Process *helpers[3])
{
  char *dir;
  const struct GNUNET_OS_ProjectData *pd;

  pd = GNUNET_OS_project_data_get ();
  GNUNET_OS_init (TALER_project_data_default ());
  dir = GNUNET_OS_installation_get_path (GNUNET_OS_IPK_BINDIR);
  GNUNET_OS_init (pd);
  if (NULL == dir)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  {
    char *fn;

    GNUNET_asprintf (&fn,
                     "%s/%s",
                     dir,
                     "taler-exchange-secmod-eddsa");
    helpers[0] = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                                          NULL, NULL, NULL,
                                          fn,
                                          "taler-exchange-secmod-eddsa",
                                          "-c", config_filename,
                                          "-L", "INFO",
                                          NULL);
    GNUNET_free (fn);
  }
  {
    char *fn;

    GNUNET_asprintf (&fn,
                     "%s/%s",
                     dir,
                     "taler-exchange-secmod-rsa");
    helpers[1] = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                                          NULL, NULL, NULL,
                                          fn,
                                          "taler-exchange-secmod-rsa",
                                          "-c", config_filename,
                                          "-L", "INFO",
                                          NULL);
    GNUNET_free (fn);
  }
  {
    char *fn;

    GNUNET_asprintf (&fn,
                     "%s/%s",
                     dir,
                     "taler-exchange-secmod-cs");
    helpers[2] = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                                          NULL, NULL, NULL,
                                          fn,
                                          "taler-exchange-secmod-cs",
                                          "-c", config_filename,
                                          "-L", "INFO",
                                          NULL);
    GNUNET_free (fn);
  }
  GNUNET_free (dir);
  if ( (NULL == helpers[0]) ||
       (NULL == helpers[1]) ||
       (NULL == helpers[2]) )
  {
    stop_helpers (helpers);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_TESTING_setup_with_exchange_cfg (
  void *cls,
  const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  const struct TALER_TESTING_SetupContext *setup_ctx = cls;
  struct GNUNET_OS_Process *exchanged;
  struct GNUNET_OS_Process *helpers[3];
  unsigned long long port;
  char *serve;
  char *base_url;
  int result;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "SERVE",
                                             &serve))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "SERVE");
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
      GNUNET_free (serve);
      return GNUNET_NO;
    }

    if (GNUNET_OK !=
        GNUNET_NETWORK_test_port_free (IPPROTO_TCP,
                                       (uint16_t) port))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Required port %llu not available, skipping.\n",
                  port);
      GNUNET_free (serve);
      return GNUNET_NO;
    }
  }
  GNUNET_free (serve);
  if (GNUNET_OK !=
      start_helpers (setup_ctx->config_filename,
                     helpers))
  {
    GNUNET_break (0);
    return 77;
  }
  exchanged = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                                       NULL, NULL, NULL,
#if GNU_PARALLEL
                                       "parallel",
#endif
                                       "taler-exchange-httpd",
                                       "taler-exchange-httpd",
                                       "-L", "INFO",
                                       "-a", /* some tests may need timetravel */
                                       "-c", setup_ctx->config_filename,
#if GNU_PARALLEL
                                       "-r",
                                       ":::",
                                       "-",
                                       "-",
                                       "-",
                                       "-",
#endif
                                       NULL);
  if (NULL == exchanged)
  {
    GNUNET_break (0);
    stop_helpers (helpers);
    return 77;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &base_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    stop_helpers (helpers);
    return GNUNET_NO;
  }

  if (0 != TALER_TESTING_wait_exchange_ready (base_url))
  {
    GNUNET_free (base_url);
    stop_helpers (helpers);
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (exchanged,
                                          SIGTERM));
#if GNU_PARALLEL
    /* GNU Parallel kills on 2nd SIGTERM, need to give it a
       chance to process the 1st signal first... */
    sleep (1);
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (exchanged,
                                          SIGTERM));
#endif
    GNUNET_break (GNUNET_OK ==
                  GNUNET_OS_process_wait (exchanged));
    GNUNET_OS_process_destroy (exchanged);
    return 77;
  }
  GNUNET_free (base_url);

  /* NOTE: this call blocks.  */
  result = TALER_TESTING_setup (setup_ctx->main_cb,
                                setup_ctx->main_cb_cls,
                                cfg,
                                exchanged,
                                GNUNET_YES);
  GNUNET_break (0 ==
                GNUNET_OS_process_kill (exchanged,
                                        SIGTERM));
#if GNU_PARALLEL
  /* GNU Parallel kills on 2nd SIGTERM, need to give it a
     chance to process the 1st signal first... */
  sleep (1);
  GNUNET_break (0 ==
                GNUNET_OS_process_kill (exchanged,
                                        SIGTERM));
#endif
  GNUNET_break (GNUNET_OK ==
                GNUNET_OS_process_wait (exchanged));
  GNUNET_OS_process_destroy (exchanged);
  stop_helpers (helpers);
  return result;
}


enum GNUNET_GenericReturnValue
TALER_TESTING_setup_with_auditor_and_exchange_cfg (
  void *cls,
  const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  const struct TALER_TESTING_SetupContext *setup_ctx = cls;
  struct GNUNET_OS_Process *auditord;
  unsigned long long port;
  char *serve;
  char *base_url;
  int result;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "auditor",
                                             "SERVE",
                                             &serve))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "auditor",
                               "SERVE");
    return GNUNET_NO;
  }

  if (0 == strcmp ("tcp", serve))
  {
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_number (cfg,
                                               "auditor",
                                               "PORT",
                                               &port))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "auditor",
                                 "PORT");
      GNUNET_free (serve);
      return GNUNET_NO;
    }

    if (GNUNET_OK !=
        GNUNET_NETWORK_test_port_free (IPPROTO_TCP,
                                       (uint16_t) port))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Required port %llu not available, skipping.\n",
                  port);
      GNUNET_free (serve);
      return GNUNET_NO;
    }
  }
  GNUNET_free (serve);
  auditord = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                                      NULL, NULL, NULL,
                                      "taler-auditor-httpd",
                                      "taler-auditor-httpd",
                                      "-c", setup_ctx->config_filename,
                                      NULL);

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "auditor",
                                             "BASE_URL",
                                             &base_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "auditor",
                               "BASE_URL");
    return GNUNET_NO;
  }

  if (0 != TALER_TESTING_wait_auditor_ready (base_url))
  {
    GNUNET_free (base_url);
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (auditord,
                                          SIGTERM));
    GNUNET_break (GNUNET_OK ==
                  GNUNET_OS_process_wait (auditord));
    GNUNET_OS_process_destroy (auditord);
    return 77;
  }
  GNUNET_free (base_url);

  /* NOTE: this call blocks.  */
  result = TALER_TESTING_setup_with_exchange_cfg ((void *) setup_ctx,
                                                  cfg);
  GNUNET_break (0 ==
                GNUNET_OS_process_kill (auditord,
                                        SIGTERM));
  GNUNET_break (GNUNET_OK ==
                GNUNET_OS_process_wait (auditord));
  GNUNET_OS_process_destroy (auditord);
  return result;
}


enum GNUNET_GenericReturnValue
TALER_TESTING_setup_with_auditor_and_exchange (TALER_TESTING_Main main_cb,
                                               void *main_cb_cls,
                                               const char *config_file)
{
  struct TALER_TESTING_SetupContext setup_ctx = {
    .config_filename = config_file,
    .main_cb = main_cb,
    .main_cb_cls = main_cb_cls
  };

  return GNUNET_CONFIGURATION_parse_and_run (
    config_file,
    &TALER_TESTING_setup_with_auditor_and_exchange_cfg,
    &setup_ctx);
}


enum GNUNET_GenericReturnValue
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


/* end of testing_api_helpers_exchange.c */
