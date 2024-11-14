/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-drain.c
 * @brief Process that drains exchange profits from the escrow account
 *        and puts them into some regular account of the exchange.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <pthread.h>
#include "taler_exchangedb_lib.h"
#include "taler_exchangedb_plugin.h"
#include "taler_json_lib.h"
#include "taler_bank_service.h"


/**
 * The exchange's configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our database plugin.
 */
static struct TALER_EXCHANGEDB_Plugin *db_plugin;

/**
 * Our master public key.
 */
static struct TALER_MasterPublicKeyP master_pub;

/**
 * Next task to run, if any.
 */
static struct GNUNET_SCHEDULER_Task *task;

/**
 * Base URL of this exchange.
 */
static char *exchange_base_url;

/**
 * Value to return from main(). 0 on success, non-zero on errors.
 */
static int global_ret;


/**
 * We're being aborted with CTRL-C (or SIGTERM). Shut down.
 *
 * @param cls closure
 */
static void
shutdown_task (void *cls)
{
  (void) cls;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Running shutdown\n");
  if (NULL != task)
  {
    GNUNET_SCHEDULER_cancel (task);
    task = NULL;
  }
  db_plugin->rollback (db_plugin->cls); /* just in case */
  TALER_EXCHANGEDB_plugin_unload (db_plugin);
  db_plugin = NULL;
  TALER_EXCHANGEDB_unload_accounts ();
  cfg = NULL;
}


/**
 * Parse the configuration for drain.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_drain_config (void)
{
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &exchange_base_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    return GNUNET_SYSERR;
  }

  {
    char *master_public_key_str;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "exchange",
                                               "MASTER_PUBLIC_KEY",
                                               &master_public_key_str))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "MASTER_PUBLIC_KEY");
      return GNUNET_SYSERR;
    }
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_public_key_from_string (master_public_key_str,
                                                    strlen (
                                                      master_public_key_str),
                                                    &master_pub.eddsa_pub))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "MASTER_PUBLIC_KEY",
                                 "invalid base32 encoding for a master public key");
      GNUNET_free (master_public_key_str);
      return GNUNET_SYSERR;
    }
    GNUNET_free (master_public_key_str);
  }
  if (NULL ==
      (db_plugin = TALER_EXCHANGEDB_plugin_load (cfg,
                                                 false)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize DB subsystem\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_EXCHANGEDB_load_accounts (cfg,
                                      TALER_EXCHANGEDB_ALO_DEBIT
                                      | TALER_EXCHANGEDB_ALO_AUTHDATA))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "No wire accounts configured for debit!\n");
    TALER_EXCHANGEDB_plugin_unload (db_plugin);
    db_plugin = NULL;
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Perform a database commit. If it fails, print a warning.
 *
 * @return status of commit
 */
static enum GNUNET_DB_QueryStatus
commit_or_warn (void)
{
  enum GNUNET_DB_QueryStatus qs;

  qs = db_plugin->commit (db_plugin->cls);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    return qs;
  GNUNET_log ((GNUNET_DB_STATUS_SOFT_ERROR == qs)
              ? GNUNET_ERROR_TYPE_INFO
              : GNUNET_ERROR_TYPE_ERROR,
              "Failed to commit database transaction!\n");
  return qs;
}


/**
 * Execute a wire drain.
 *
 * @param cls NULL
 */
static void
run_drain (void *cls)
{
  enum GNUNET_DB_QueryStatus qs;
  uint64_t serial;
  struct TALER_WireTransferIdentifierRawP wtid;
  char *account_section;
  struct TALER_FullPayto payto_uri;
  struct GNUNET_TIME_Timestamp request_timestamp;
  struct TALER_Amount amount;
  struct TALER_MasterSignatureP master_sig;

  (void) cls;
  task = NULL;
  if (GNUNET_OK !=
      db_plugin->start (db_plugin->cls,
                        "run drain"))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to start database transaction!\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  qs = db_plugin->profit_drains_get_pending (db_plugin->cls,
                                             &serial,
                                             &wtid,
                                             &account_section,
                                             &payto_uri,
                                             &request_timestamp,
                                             &amount,
                                             &master_sig);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    db_plugin->rollback (db_plugin->cls);
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    db_plugin->rollback (db_plugin->cls);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Serialization failure on simple SELECT!?\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    /* no profit drains, finished */
    db_plugin->rollback (db_plugin->cls);
    GNUNET_assert (NULL == task);
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "No profit drains pending. Exiting.\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  default:
    /* continued below */
    break;
  }
  /* Check signature (again, this is a critical operation!) */
  if (GNUNET_OK !=
      TALER_exchange_offline_profit_drain_verify (
        &wtid,
        request_timestamp,
        &amount,
        account_section,
        payto_uri,
        &master_pub,
        &master_sig))
  {
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    db_plugin->rollback (db_plugin->cls);
    GNUNET_assert (NULL == task);
    GNUNET_SCHEDULER_shutdown ();
    return;
  }

  /* Display data for manual human check */
  fprintf (stdout,
           "Critical operation. MANUAL CHECK REQUIRED.\n");
  fprintf (stdout,
           "We will wire %s to `%s'\n based on instructions from %s.\n",
           TALER_amount2s (&amount),
           payto_uri.full_payto,
           GNUNET_TIME_timestamp2s (request_timestamp));
  fprintf (stdout,
           "Press ENTER to confirm, CTRL-D to abort.\n");
  while (1)
  {
    int key;

    key = getchar ();
    if (EOF == key)
    {
      fprintf (stdout,
               "Transfer aborted.\n"
               "Re-run 'taler-exchange-drain' to try it again.\n"
               "Contact Taler Systems SA to cancel it for good.\n"
               "Exiting.\n");
      db_plugin->rollback (db_plugin->cls);
      GNUNET_free (payto_uri.full_payto);
      GNUNET_assert (NULL == task);
      GNUNET_SCHEDULER_shutdown ();
      global_ret = EXIT_FAILURE;
      return;
    }
    if ('\n' == key)
      break;
  }

  /* Note: account_section ignored for now, we
     might want to use it here in the future... */
  (void) account_section;
  {
    char *method;
    void *buf;
    size_t buf_size;

    TALER_BANK_prepare_transfer (payto_uri,
                                 &amount,
                                 exchange_base_url,
                                 &wtid,
                                 &buf,
                                 &buf_size);
    method = TALER_payto_get_method (payto_uri.full_payto);
    qs = db_plugin->wire_prepare_data_insert (db_plugin->cls,
                                              method,
                                              buf,
                                              buf_size);
    GNUNET_free (method);
    GNUNET_free (buf);
  }
  GNUNET_free (payto_uri.full_payto);
  qs = db_plugin->profit_drains_set_finished (db_plugin->cls,
                                              serial);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    db_plugin->rollback (db_plugin->cls);
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    db_plugin->rollback (db_plugin->cls);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed: database serialization issue\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    db_plugin->rollback (db_plugin->cls);
    GNUNET_assert (NULL == task);
    GNUNET_break (0);
    GNUNET_SCHEDULER_shutdown ();
    return;
  default:
    /* continued below */
    break;
  }
  /* commit transaction + report success + exit */
  if (0 >= commit_or_warn ())
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "Profit drain triggered. Exiting.\n");
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * First task.
 *
 * @param cls closure, NULL
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be NULL!)
 * @param c configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *c)
{
  (void) cls;
  (void) args;
  (void) cfgfile;

  cfg = c;
  if (GNUNET_OK != parse_drain_config ())
  {
    cfg = NULL;
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  if (GNUNET_SYSERR ==
      db_plugin->preflight (db_plugin->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain database connection!\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  GNUNET_assert (NULL == task);
  task = GNUNET_SCHEDULER_add_now (&run_drain,
                                   NULL);
  GNUNET_SCHEDULER_add_shutdown (&shutdown_task,
                                 cls);
}


/**
 * The main function of the taler-exchange-drain.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_version (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  ret = GNUNET_PROGRAM_run (
    TALER_EXCHANGE_project_data (),
    argc, argv,
    "taler-exchange-drain",
    gettext_noop (
      "process that executes a single profit drain"),
    options,
    &run, NULL);
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  return global_ret;
}


/* end of taler-exchange-drain.c */
