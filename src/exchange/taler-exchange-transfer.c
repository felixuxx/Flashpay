/*
  This file is part of TALER
  Copyright (C) 2016-2020 Taler Systems SA

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
 * @file taler-exchange-transfer.c
 * @brief Process that actually finalizes outgoing transfers with the wire gateway / bank
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
 * Data we keep to #run_transfers().  There is at most
 * one of these around at any given point in time.
 * Note that this limits parallelism, and we might want
 * to revise this decision at a later point.
 */
struct WirePrepareData
{

  /**
   * Database session for all of our transactions.
   */
  struct TALER_EXCHANGEDB_Session *session;

  /**
   * Wire execution handle.
   */
  struct TALER_BANK_TransferHandle *eh;

  /**
   * Wire account used for this preparation.
   */
  struct TALER_EXCHANGEDB_WireAccount *wa;

  /**
   * Row ID of the transfer.
   */
  unsigned long long row_id;

};


/**
 * The exchange's configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our database plugin.
 */
static struct TALER_EXCHANGEDB_Plugin *db_plugin;

/**
 * Next task to run, if any.
 */
static struct GNUNET_SCHEDULER_Task *task;

/**
 * If we are currently executing a transfer, information about
 * the active transfer is here. Otherwise, this variable is NULL.
 */
static struct WirePrepareData *wpd;

/**
 * Handle to the context for interacting with the bank / wire gateway.
 */
static struct GNUNET_CURL_Context *ctx;

/**
 * Scheduler context for running the @e ctx.
 */
static struct GNUNET_CURL_RescheduleContext *rc;

/**
 * How long should we sleep when idle before trying to find more work?
 */
static struct GNUNET_TIME_Relative aggregator_idle_sleep_interval;

/**
 * Value to return from main(). 0 on success, non-zero on errors.
 */
static enum
{
  GR_SUCCESS = 0,
  GR_WIRE_TRANSFER_FAILED = 1,
  GR_DATABASE_COMMIT_HARD_FAIL = 2,
  GR_INVARIANT_FAILURE = 3,
  GR_WIRE_ACCOUNT_NOT_CONFIGURED = 4,
  GR_WIRE_TRANSFER_BEGIN_FAIL = 5,
  GR_DATABASE_TRANSACTION_BEGIN_FAIL = 6,
  GR_DATABASE_SESSION_START_FAIL = 7,
  GR_CONFIGURATION_INVALID = 8,
  GR_CMD_LINE_UTF8_ERROR = 9,
  GR_CMD_LINE_OPTIONS_WRONG = 10,
  GR_DATABASE_FETCH_FAILURE = 11,
} global_ret;

/**
 * #GNUNET_YES if we are in test mode and should exit when idle.
 */
static int test_mode;


/**
 * We're being aborted with CTRL-C (or SIGTERM). Shut down.
 *
 * @param cls closure
 */
static void
shutdown_task (void *cls)
{
  (void) cls;
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
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Running shutdown\n");
  if (NULL != task)
  {
    GNUNET_SCHEDULER_cancel (task);
    task = NULL;
  }
  if (NULL != wpd)
  {
    if (NULL != wpd->eh)
    {
      TALER_BANK_transfer_cancel (wpd->eh);
      wpd->eh = NULL;
    }
    db_plugin->rollback (db_plugin->cls,
                         wpd->session);
    GNUNET_free (wpd);
    wpd = NULL;
  }
  TALER_EXCHANGEDB_plugin_unload (db_plugin);
  db_plugin = NULL;
  TALER_EXCHANGEDB_unload_accounts ();
  cfg = NULL;
}


/**
 * Parse the configuration for wirewatch.
 *
 * @return #GNUNET_OK on success
 */
static int
parse_wirewatch_config (void)
{
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           "exchange",
                                           "AGGREGATOR_IDLE_SLEEP_INTERVAL",
                                           &aggregator_idle_sleep_interval))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "AGGREGATOR_IDLE_SLEEP_INTERVAL");
    return GNUNET_SYSERR;
  }
  if (NULL ==
      (db_plugin = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize DB subsystem\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_EXCHANGEDB_load_accounts (cfg))
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
 * @param session session to perform the commit for.
 * @return status of commit
 */
static enum GNUNET_DB_QueryStatus
commit_or_warn (struct TALER_EXCHANGEDB_Session *session)
{
  enum GNUNET_DB_QueryStatus qs;

  qs = db_plugin->commit (db_plugin->cls,
                          session);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    return qs;
  GNUNET_log ((GNUNET_DB_STATUS_SOFT_ERROR == qs)
              ? GNUNET_ERROR_TYPE_INFO
              : GNUNET_ERROR_TYPE_ERROR,
              "Failed to commit database transaction!\n");
  return qs;
}


/**
 * Execute the wire transfers that we have committed to
 * do.
 *
 * @param cls NULL
 */
static void
run_transfers (void *cls);


/**
 * Function called with the result from the execute step.
 * On success, we mark the respective wire transfer as finished,
 * and in general we afterwards continue to #run_transfers(),
 * except for irrecoverable errors.
 *
 * @param cls NULL
 * @param http_status_code #MHD_HTTP_OK on success
 * @param ec taler error code
 * @param row_id unique ID of the wire transfer in the bank's records
 * @param wire_timestamp when did the transfer happen
 */
static void
wire_confirm_cb (void *cls,
                 unsigned int http_status_code,
                 enum TALER_ErrorCode ec,
                 uint64_t row_id,
                 struct GNUNET_TIME_Absolute wire_timestamp)
{
  struct TALER_EXCHANGEDB_Session *session = wpd->session;
  enum GNUNET_DB_QueryStatus qs;

  (void) cls;
  (void) row_id;
  (void) wire_timestamp;
  wpd->eh = NULL;
  if (MHD_HTTP_OK != http_status_code)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Wire transaction failed: %u/%d\n",
                http_status_code,
                ec);
    db_plugin->rollback (db_plugin->cls,
                         session);
    global_ret = GR_WIRE_TRANSFER_FAILED;
    GNUNET_SCHEDULER_shutdown ();
    GNUNET_free (wpd);
    wpd = NULL;
    return;
  }
  qs = db_plugin->wire_prepare_data_mark_finished (db_plugin->cls,
                                                   session,
                                                   wpd->row_id);
  if (0 >= qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    db_plugin->rollback (db_plugin->cls,
                         session);
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    {
      /* try again */
      GNUNET_assert (NULL == task);
      task = GNUNET_SCHEDULER_add_now (&run_transfers,
                                       NULL);
    }
    else
    {
      global_ret = GR_DATABASE_COMMIT_HARD_FAIL;
      GNUNET_SCHEDULER_shutdown ();
    }
    GNUNET_free (wpd);
    wpd = NULL;
    return;
  }
  GNUNET_free (wpd);
  wpd = NULL;
  switch (commit_or_warn (session))
  {
  case GNUNET_DB_STATUS_SOFT_ERROR:
    /* try again */
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_transfers,
                                     NULL);
    return;
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    global_ret = GR_DATABASE_COMMIT_HARD_FAIL;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Wire transfer complete\n");
    /* continue with #run_transfers(), just to guard
       against the unlikely case that there are more. */
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_transfers,
                                     NULL);
    return;
  default:
    GNUNET_break (0);
    global_ret = GR_INVARIANT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


/**
 * Callback with data about a prepared transaction.  Triggers the respective
 * wire transfer using the prepared transaction data.
 *
 * @param cls NULL
 * @param rowid row identifier used to mark prepared transaction as done
 * @param wire_method wire method the preparation was done for
 * @param buf transaction data that was persisted, NULL on error
 * @param buf_size number of bytes in @a buf, 0 on error
 */
static void
wire_prepare_cb (void *cls,
                 uint64_t rowid,
                 const char *wire_method,
                 const char *buf,
                 size_t buf_size)
{
  struct TALER_EXCHANGEDB_WireAccount *wa;

  (void) cls;
  if ( (NULL == wire_method) ||
       (NULL == buf) )
  {
    GNUNET_break (0);
    db_plugin->rollback (db_plugin->cls,
                         wpd->session);
    global_ret = GR_DATABASE_FETCH_FAILURE;
    goto cleanup;
  }
  wpd->row_id = rowid;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting wire transfer %llu\n",
              (unsigned long long) rowid);
  wpd->wa = TALER_EXCHANGEDB_find_account_by_method (wire_method);
  if (NULL == wpd->wa)
  {
    /* Should really never happen here, as when we get
       here the wire account should be in the cache. */
    GNUNET_break (0);
    db_plugin->rollback (db_plugin->cls,
                         wpd->session);
    global_ret = GR_WIRE_ACCOUNT_NOT_CONFIGURED;
    goto cleanup;
  }
  wa = wpd->wa;
  wpd->eh = TALER_BANK_transfer (ctx,
                                 &wa->auth,
                                 buf,
                                 buf_size,
                                 &wire_confirm_cb,
                                 NULL);
  if (NULL == wpd->eh)
  {
    GNUNET_break (0); /* Irrecoverable */
    db_plugin->rollback (db_plugin->cls,
                         wpd->session);
    global_ret = GR_WIRE_TRANSFER_BEGIN_FAIL;
    goto cleanup;
  }
  return;
cleanup:
  GNUNET_SCHEDULER_shutdown ();
  GNUNET_free (wpd);
  wpd = NULL;
}


/**
 * Execute the wire transfers that we have committed to
 * do.
 *
 * @param cls NULL
 */
static void
run_transfers (void *cls)
{
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_EXCHANGEDB_Session *session;

  (void) cls;
  task = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Checking for pending wire transfers\n");
  if (NULL == (session = db_plugin->get_session (db_plugin->cls)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain database session!\n");
    global_ret = GR_DATABASE_SESSION_START_FAIL;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_OK !=
      db_plugin->start (db_plugin->cls,
                        session,
                        "aggregator run transfer"))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to start database transaction!\n");
    global_ret = GR_DATABASE_TRANSACTION_BEGIN_FAIL;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  wpd = GNUNET_new (struct WirePrepareData);
  wpd->session = session;
  qs = db_plugin->wire_prepare_data_get (db_plugin->cls,
                                         session,
                                         &wire_prepare_cb,
                                         NULL);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
    return;  /* continued via continuation set in #wire_prepare_cb() */
  db_plugin->rollback (db_plugin->cls,
                       session);
  GNUNET_free (wpd);
  wpd = NULL;
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    global_ret = GR_DATABASE_COMMIT_HARD_FAIL;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    /* try again */
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_transfers,
                                     NULL);
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    /* no more prepared wire transfers, go sleep a bit! */
    GNUNET_assert (NULL == task);
    if (GNUNET_YES == test_mode)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "No more pending wire transfers, shutting down (because we are in test mode)\n");
      GNUNET_SCHEDULER_shutdown ();
    }
    else
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "No more pending wire transfers, going idle\n");
      task = GNUNET_SCHEDULER_add_delayed (aggregator_idle_sleep_interval,
                                           &run_transfers,
                                           NULL);
    }
    return;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    /* should be impossible */
    GNUNET_assert (0);
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
  if (GNUNET_OK != parse_wirewatch_config ())
  {
    cfg = NULL;
    global_ret = GR_CONFIGURATION_INVALID;
    return;
  }
  ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &rc);
  rc = GNUNET_CURL_gnunet_rc_create (ctx);
  if (NULL == ctx)
  {
    GNUNET_break (0);
    return;
  }

  GNUNET_assert (NULL == task);
  task = GNUNET_SCHEDULER_add_now (&run_transfers,
                                   NULL);
  GNUNET_SCHEDULER_add_shutdown (&shutdown_task,
                                 cls);
}


/**
 * The main function of the taler-exchange-transfer.
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
    GNUNET_GETOPT_option_timetravel ('T',
                                     "timetravel"),
    GNUNET_GETOPT_option_flag ('t',
                               "test",
                               "run in test mode and exit when idle",
                               &test_mode),
    GNUNET_GETOPT_option_version (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };

  if (GNUNET_OK !=
      GNUNET_STRINGS_get_utf8_args (argc, argv,
                                    &argc, &argv))
    return GR_CMD_LINE_UTF8_ERROR;
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc, argv,
                          "taler-exchange-transfer",
                          gettext_noop (
                            "background process that executes outgoing wire transfers"),
                          options,
                          &run, NULL))
  {
    GNUNET_free_nz ((void *) argv);
    return GR_CMD_LINE_OPTIONS_WRONG;
  }
  GNUNET_free_nz ((void *) argv);
  return global_ret;
}


/* end of taler-exchange-transfer.c */
