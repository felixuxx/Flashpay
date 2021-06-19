/*
  This file is part of TALER
  Copyright (C) 2016--2020 Taler Systems SA

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
 * @file taler-exchange-wirewatch.c
 * @brief Process that watches for wire transfers to the exchange's bank account
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <pthread.h>
#include <microhttpd.h>
#include "taler_exchangedb_lib.h"
#include "taler_exchangedb_plugin.h"
#include "taler_json_lib.h"
#include "taler_bank_service.h"

#define DEBUG_LOGGING 0

/**
 * What is the initial batch size we use for credit history
 * requests with the bank.  See `batch_size` below.
 */
#define INITIAL_BATCH_SIZE 1024

/**
 * Information we keep for each supported account.
 */
struct WireAccount
{
  /**
   * Accounts are kept in a DLL.
   */
  struct WireAccount *next;

  /**
   * Plugins are kept in a DLL.
   */
  struct WireAccount *prev;

  /**
   * Name of the section that configures this account.
   */
  char *section_name;

  /**
   * Database session we are using for the current transaction.
   */
  struct TALER_EXCHANGEDB_Session *session;

  /**
   * Active request for history.
   */
  struct TALER_BANK_CreditHistoryHandle *hh;

  /**
   * Authentication data.
   */
  struct TALER_BANK_AuthenticationData auth;

  /**
   * Until when is processing this wire plugin delayed?
   */
  struct GNUNET_TIME_Absolute delayed_until;

  /**
   * Encoded offset in the wire transfer list from where
   * to start the next query with the bank.
   */
  uint64_t last_row_off;

  /**
   * Latest row offset seen in this transaction, becomes
   * the new #last_row_off upon commit.
   */
  uint64_t latest_row_off;

  /**
   * How many transactions do we retrieve per batch?
   */
  unsigned int batch_size;

  /**
   * How many transactions did we see in the current batch?
   */
  unsigned int current_batch_size;

  /**
   * Are we running from scratch and should re-process all transactions
   * for this account?
   */
  int reset_mode;

  /**
   * Should we delay the next request to the wire plugin a bit?  Set to
   * #GNUNET_NO if we actually did some work.
   */
  int delay;

  /**
   * Did we experience a soft failure during the current
   * transaction?
   */
  bool soft_fail;
};


/**
 * Head of list of loaded wire plugins.
 */
static struct WireAccount *wa_head;

/**
 * Tail of list of loaded wire plugins.
 */
static struct WireAccount *wa_tail;

/**
 * Wire account we are currently processing.  This would go away
 * if we ever start processing all accounts in parallel.
 */
static struct WireAccount *wa_pos;

/**
 * Handle to the context for interacting with the bank.
 */
static struct GNUNET_CURL_Context *ctx;

/**
 * Scheduler context for running the @e ctx.
 */
static struct GNUNET_CURL_RescheduleContext *rc;

/**
 * The exchange's configuration (global)
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our DB plugin.
 */
static struct TALER_EXCHANGEDB_Plugin *db_plugin;

/**
 * How long should we sleep when idle before trying to find more work?
 */
static struct GNUNET_TIME_Relative wirewatch_idle_sleep_interval;

/**
 * Value to return from main(). 0 on success, non-zero on
 * on serious errors.
 */
static enum
{
  GR_SUCCESS = 0,
  GR_DATABASE_SESSION_FAIL = 1,
  GR_DATABASE_TRANSACTION_BEGIN_FAIL = 2,
  GR_DATABASE_SELECT_LATEST_HARD_FAIL = 3,
  GR_BANK_REQUEST_HISTORY_FAIL = 4,
  GR_CONFIGURATION_INVALID = 5,
  GR_CMD_LINE_UTF8_ERROR = 6,
  GR_CMD_LINE_OPTIONS_WRONG = 7,
} global_ret;

/**
 * Are we run in testing mode and should only do one pass?
 */
static int test_mode;

/**
 * Are we running from scratch and should re-process all transactions?
 */
static int reset_mode;

/**
 * Current task waiting for execution, if any.
 */
static struct GNUNET_SCHEDULER_Task *task;


/**
 * We're being aborted with CTRL-C (or SIGTERM). Shut down.
 *
 * @param cls closure
 */
static void
shutdown_task (void *cls)
{
  (void) cls;
  {
    struct WireAccount *wa;

    while (NULL != (wa = wa_head))
    {
      if (NULL != wa->hh)
      {
        TALER_BANK_credit_history_cancel (wa->hh);
        wa->hh = NULL;
      }
      GNUNET_CONTAINER_DLL_remove (wa_head,
                                   wa_tail,
                                   wa);
      TALER_BANK_auth_free (&wa->auth);
      GNUNET_free (wa->section_name);
      GNUNET_free (wa);
    }
  }
  wa_pos = NULL;

  if (NULL != ctx)
  {
    GNUNET_CURL_fini (ctx);
    ctx = NULL;
  }
  if (NULL != rc)
  {
    GNUNET_CURL_gnunet_rc_destroy (rc);
    rc = NULL;
  }
  if (NULL != task)
  {
    GNUNET_SCHEDULER_cancel (task);
    task = NULL;
  }
  TALER_EXCHANGEDB_plugin_unload (db_plugin);
  db_plugin = NULL;
}


/**
 * Function called with information about a wire account.  Adds the
 * account to our list (if it is enabled and we can load the plugin).
 *
 * @param cls closure, NULL
 * @param ai account information
 */
static void
add_account_cb (void *cls,
                const struct TALER_EXCHANGEDB_AccountInfo *ai)
{
  struct WireAccount *wa;

  (void) cls;
  if (GNUNET_YES != ai->credit_enabled)
    return; /* not enabled for us, skip */
  wa = GNUNET_new (struct WireAccount);
  wa->reset_mode = reset_mode;
  if (GNUNET_OK !=
      TALER_BANK_auth_parse_cfg (cfg,
                                 ai->section_name,
                                 &wa->auth))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "Failed to load account `%s'\n",
                ai->section_name);
    GNUNET_free (wa);
    return;
  }
  wa->section_name = GNUNET_strdup (ai->section_name);
  wa->batch_size = INITIAL_BATCH_SIZE;
  GNUNET_CONTAINER_DLL_insert (wa_head,
                               wa_tail,
                               wa);
}


/**
 * Parse configuration parameters for the exchange server into the
 * corresponding global variables.
 *
 * @return #GNUNET_OK on success
 */
static int
exchange_serve_process_config (void)
{
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           "exchange",
                                           "WIREWATCH_IDLE_SLEEP_INTERVAL",
                                           &wirewatch_idle_sleep_interval))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "WIREWATCH_IDLE_SLEEP_INTERVAL");
    return GNUNET_SYSERR;
  }
  if (NULL ==
      (db_plugin = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize DB subsystem\n");
    return GNUNET_SYSERR;
  }
  TALER_EXCHANGEDB_find_accounts (cfg,
                                  &add_account_cb,
                                  NULL);
  if (NULL == wa_head)
  {
    fprintf (stderr,
             "No wire accounts configured for credit!\n");
    TALER_EXCHANGEDB_plugin_unload (db_plugin);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Query for incoming wire transfers.
 *
 * @param cls NULL
 */
static void
find_transfers (void *cls);


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank for the transaction history.
 *
 * @param cls closure with the `struct WioreAccount *` we are processing
 * @param http_status HTTP status code from the server
 * @param ec taler error code
 * @param serial_id identification of the position at which we are querying
 * @param details details about the wire transfer
 * @param json raw JSON response
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to abort iteration
 */
static int
history_cb (void *cls,
            unsigned int http_status,
            enum TALER_ErrorCode ec,
            uint64_t serial_id,
            const struct TALER_BANK_CreditDetails *details,
            const json_t *json)
{
  struct WireAccount *wa = cls;
  struct TALER_EXCHANGEDB_Session *session = wa->session;
  enum GNUNET_DB_QueryStatus qs;

  (void) json;
  if (NULL == details)
  {
    wa->hh = NULL;
    if (TALER_EC_NONE != ec)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Error fetching history: ec=%u, http_status=%u\n",
                  (unsigned int) ec,
                  http_status);
    }
    if (wa->soft_fail)
    {
      /* no point to commit, transaction was already rolled
         back after we encountered a soft failure */
      wa->soft_fail = false;
      qs = GNUNET_DB_STATUS_SOFT_ERROR;
    }
    else
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "End of list. Committing progress!\n");
      qs = db_plugin->commit (db_plugin->cls,
                              session);
    }
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_SCHEDULER_shutdown ();
      return GNUNET_OK;
    }
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    {
      /* reduce transaction size to reduce rollback probability */
      if (2 > wa->batch_size)
      {
        wa->batch_size /= 2;
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Reduced batch size to %llu due to serialization issue\n",
                    (unsigned long long) wa->batch_size);
      }
      /* try again */
      GNUNET_assert (NULL == task);
      task = GNUNET_SCHEDULER_add_now (&find_transfers,
                                       NULL);
      return GNUNET_OK; /* will be ignored anyway */
    }
    GNUNET_break (0 <= qs);
    /* transaction success, update #last_row_off */
    wa->last_row_off = wa->latest_row_off;
    wa->latest_row_off = 0;   /* should not be needed */
    wa->session = NULL;   /* should not be needed */
    if (wa->batch_size < INITIAL_BATCH_SIZE)
    {
      wa->batch_size += 1;
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Increasing batch size to %llu\n",
                  (unsigned long long) wa->batch_size);
    }
    if ( (GNUNET_YES == wa->delay) &&
         (test_mode) &&
         (NULL == wa->next) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Shutdown due to test mode!\n");
      GNUNET_SCHEDULER_shutdown ();
      return GNUNET_OK;
    }
    if (GNUNET_YES == wa->delay)
    {
      wa->delayed_until
        = GNUNET_TIME_relative_to_absolute (wirewatch_idle_sleep_interval);
      wa_pos = wa_pos->next;
      if (NULL == wa_pos)
        wa_pos = wa_head;
      GNUNET_assert (NULL != wa_pos);
    }
    task = GNUNET_SCHEDULER_add_at (wa_pos->delayed_until,
                                    &find_transfers,
                                    NULL);
    return GNUNET_OK; /* will be ignored anyway */
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Adding wire transfer over %s with (hashed) subject `%s'\n",
              TALER_amount2s (&details->amount),
              TALER_B2S (&details->reserve_pub));

  /**
   * Debug block.
   */
#if DEBUG_LOGGING
  {
    /** Should be 53, give 80 just to be extra conservative (and aligned).  */
#define PUBSIZE 80
    char wtid_s[PUBSIZE];

    GNUNET_break (NULL !=
                  GNUNET_STRINGS_data_to_string (&details->reserve_pub,
                                                 sizeof (details->reserve_pub),
                                                 &wtid_s[0],
                                                 PUBSIZE));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Plain text subject (= reserve_pub): %s\n",
                wtid_s);
  }
#endif

  qs = db_plugin->reserves_in_insert (db_plugin->cls,
                                      session,
                                      &details->reserve_pub,
                                      &details->amount,
                                      details->execution_date,
                                      details->debit_account_url,
                                      wa->section_name,
                                      serial_id);
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    GNUNET_break (0);
    db_plugin->rollback (db_plugin->cls,
                         session);
    GNUNET_SCHEDULER_shutdown ();
    return GNUNET_SYSERR;
  }
  if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Got DB soft error for reserves_in_insert. Rolling back.\n");
    db_plugin->rollback (db_plugin->cls,
                         session);
    wa->soft_fail = true;
    return GNUNET_SYSERR;
  }
  wa->delay = GNUNET_NO;
  wa->latest_row_off = serial_id;
  return GNUNET_OK;
}


/**
 * Query for incoming wire transfers.
 *
 * @param cls NULL
 */
static void
find_transfers (void *cls)
{
  struct TALER_EXCHANGEDB_Session *session;
  enum GNUNET_DB_QueryStatus qs;

  (void) cls;
  task = NULL;
  if (NULL == (session = db_plugin->get_session (db_plugin->cls)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain database session!\n");
    global_ret = GR_DATABASE_SESSION_FAIL;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  db_plugin->preflight (db_plugin->cls,
                        session);
  if (GNUNET_OK !=
      db_plugin->start (db_plugin->cls,
                        session,
                        "wirewatch check for incoming wire transfers"))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to start database transaction!\n");
    global_ret = GR_DATABASE_TRANSACTION_BEGIN_FAIL;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (! wa_pos->reset_mode)
  {
    qs = db_plugin->get_latest_reserve_in_reference (db_plugin->cls,
                                                     session,
                                                     wa_pos->section_name,
                                                     &wa_pos->last_row_off);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to obtain starting point for montoring from database!\n");
      db_plugin->rollback (db_plugin->cls,
                           session);
      global_ret = GR_DATABASE_SELECT_LATEST_HARD_FAIL;
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    {
      /* try again */
      db_plugin->rollback (db_plugin->cls,
                           session);
      task = GNUNET_SCHEDULER_add_now (&find_transfers,
                                       NULL);
      return;
    }
    wa_pos->reset_mode = GNUNET_NO;
  }
  wa_pos->delay = GNUNET_YES;
  wa_pos->current_batch_size = 0; /* reset counter */
  wa_pos->session = session;
  wa_pos->hh = TALER_BANK_credit_history (ctx,
                                          &wa_pos->auth,
                                          wa_pos->last_row_off,
                                          wa_pos->batch_size,
                                          &history_cb,
                                          wa_pos);
  if (NULL == wa_pos->hh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to start request for account history!\n");
    db_plugin->rollback (db_plugin->cls,
                         session);
    global_ret = GR_BANK_REQUEST_HISTORY_FAIL;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
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
  if (GNUNET_OK !=
      exchange_serve_process_config ())
  {
    global_ret = GR_CONFIGURATION_INVALID;
    return;
  }
  wa_pos = wa_head;
  GNUNET_assert (NULL != wa_pos);
  task = GNUNET_SCHEDULER_add_now (&find_transfers,
                                   NULL);
  GNUNET_SCHEDULER_add_shutdown (&shutdown_task,
                                 cls);
  ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &rc);
  rc = GNUNET_CURL_gnunet_rc_create (ctx);
  if (NULL == ctx)
  {
    GNUNET_break (0);
    return;
  }
}


/**
 * The main function of taler-exchange-wirewatch
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, non-zero on error
 */
int
main (int argc,
      char *const *argv)
{
  struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_timetravel ('T',
                                     "timetravel"),
    GNUNET_GETOPT_option_flag ('t',
                               "test",
                               "run in test mode and exit when idle",
                               &test_mode),
    GNUNET_GETOPT_option_flag ('r',
                               "reset",
                               "start fresh with all transactions in the history",
                               &reset_mode),
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  if (GNUNET_OK !=
      GNUNET_STRINGS_get_utf8_args (argc, argv,
                                    &argc, &argv))
    return GR_CMD_LINE_UTF8_ERROR;
  ret = GNUNET_PROGRAM_run (
    argc, argv,
    "taler-exchange-wirewatch",
    gettext_noop (
      "background process that watches for incoming wire transfers from customers"),
    options,
    &run, NULL);
  GNUNET_free_nz ((void *) argv);
  if (GNUNET_SYSERR == ret)
    return GR_CMD_LINE_OPTIONS_WRONG;
  if (GNUNET_NO == ret)
    return 0;
  return global_ret;
}


/* end of taler-exchange-wirewatch.c */
