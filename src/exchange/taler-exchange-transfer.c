/*
  This file is part of TALER
  Copyright (C) 2016-2021 Taler Systems SA

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
 * What is the default batch size we use for credit history
 * requests with the bank.  See `batch_size` below.
 */
#define DEFAULT_BATCH_SIZE (4 * 1024)

/**
 * How often will we retry a request (given certain
 * HTTP status codes) before giving up?
 */
#define MAX_RETRIES 16

/**
 * Information about our work shard.
 */
struct Shard
{

  /**
   * Time when we started to work on this shard.
   */
  struct GNUNET_TIME_Absolute shard_start_time;

  /**
   * Offset the shard begins at.
   */
  uint64_t shard_start;

  /**
   * Exclusive offset where the shard ends.
   */
  uint64_t shard_end;

  /**
   * Offset where our current batch begins.
   */
  uint64_t batch_start;

  /**
   * Highest row processed in the current batch.
   */
  uint64_t batch_end;

};


/**
 * Data we keep to #run_transfers().  There is at most
 * one of these around at any given point in time.
 * Note that this limits parallelism, and we might want
 * to revise this decision at a later point.
 */
struct WirePrepareData
{

  /**
   * All transfers done in the same transaction
   * are kept in a DLL.
   */
  struct WirePrepareData *next;

  /**
   * All transfers done in the same transaction
   * are kept in a DLL.
   */
  struct WirePrepareData *prev;

  /**
   * Wire execution handle.
   */
  struct TALER_BANK_TransferHandle *eh;

  /**
   * Wire account used for this preparation.
   */
  const struct TALER_EXCHANGEDB_AccountInfo *wa;

  /**
   * Row ID of the transfer.
   */
  unsigned long long row_id;

  /**
   * Number of bytes allocated after this struct
   * with the prewire data.
   */
  size_t buf_size;

  /**
   * How often did we retry so far?
   */
  unsigned int retries;

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
 * If we are currently executing transfers, information about
 * the active transfers is here. Otherwise, this variable is NULL.
 */
static struct WirePrepareData *wpd_head;

/**
 * If we are currently executing transfers, information about
 * the active transfers is here. Otherwise, this variable is NULL.
 */
static struct WirePrepareData *wpd_tail;

/**
 * Information about our work shard.
 */
static struct Shard *shard;

/**
 * Handle to the context for interacting with the bank / wire gateway.
 */
static struct GNUNET_CURL_Context *ctx;

/**
 * Randomized back-off we use on serialization errors.
 */
static struct GNUNET_TIME_Relative serialization_delay;

/**
 * Scheduler context for running the @e ctx.
 */
static struct GNUNET_CURL_RescheduleContext *rc;

/**
 * Value to return from main(). 0 on success, non-zero on errors.
 */
static int global_ret;

/**
 * #GNUNET_YES if we are in test mode and should exit when idle.
 */
static int test_mode;

/**
 * How long should we sleep when idle before trying to find more work?
 * Also used for how long we wait to grab a shard before trying it again.
 * The value should be set to a bit above the average time it takes to
 * process a shard.
 */
static struct GNUNET_TIME_Relative transfer_idle_sleep_interval;

/**
 * How long did we take to finish the last shard?
 */
static struct GNUNET_TIME_Relative shard_delay;

/**
 * Size of the shards.
 */
static unsigned int shard_size = DEFAULT_BATCH_SIZE;

/**
 * How many workers should we plan our scheduling with?
 */
static unsigned int max_workers = 0;


/**
 * Clean up all active bank interactions.
 */
static void
cleanup_wpd (void)
{
  struct WirePrepareData *wpd;

  while (NULL != (wpd = wpd_head))
  {
    GNUNET_CONTAINER_DLL_remove (wpd_head,
                                 wpd_tail,
                                 wpd);
    if (NULL != wpd->eh)
    {
      TALER_BANK_transfer_cancel (wpd->eh);
      wpd->eh = NULL;
    }
    GNUNET_free (wpd);
  }
}


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
  cleanup_wpd ();
  GNUNET_free (shard);
  db_plugin->rollback (db_plugin->cls); /* just in case */
  TALER_EXCHANGEDB_plugin_unload (db_plugin);
  db_plugin = NULL;
  TALER_EXCHANGEDB_unload_accounts ();
  cfg = NULL;
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
}


/**
 * Parse the configuration for taler-exchange-transfer.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_transfer_config (void)
{
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           "exchange",
                                           "TRANSFER_IDLE_SLEEP_INTERVAL",
                                           &transfer_idle_sleep_interval))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "TRANSFER_IDLE_SLEEP_INTERVAL");
    return GNUNET_SYSERR;
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
  {
    serialization_delay = GNUNET_TIME_UNIT_ZERO;
    return qs;
  }
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


static void
run_transfers_delayed (void *cls)
{
  (void) cls;
  shard->shard_start_time = GNUNET_TIME_absolute_get ();
  run_transfers (NULL);
}


/**
 * Select shard to process.
 *
 * @param cls NULL
 */
static void
select_shard (void *cls);


/**
 * We are done with the current batch.  Commit
 * and move on.
 */
static void
batch_done (void)
{
  /* batch done */
  GNUNET_assert (NULL == wpd_head);
  switch (commit_or_warn ())
  {
  case GNUNET_DB_STATUS_SOFT_ERROR:
    /* try again */
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Serialization failure, trying again immediately!\n");
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_transfers,
                                     NULL);
    return;
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    shard->batch_start = shard->batch_end + 1;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Batch complete\n");
    /* continue with #run_transfers(), just to guard
       against the unlikely case that there are more. */
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_transfers,
                                     NULL);
    return;
  default:
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


/**
 * Function called with the result from the execute step.
 * On success, we mark the respective wire transfer as finished,
 * and in general we afterwards continue to #run_transfers(),
 * except for irrecoverable errors.
 *
 * @param cls `struct WirePrepareData` we are working on
 * @param tr transfer response
 */
static void
wire_confirm_cb (void *cls,
                 const struct TALER_BANK_TransferResponse *tr)
{
  struct WirePrepareData *wpd = cls;
  enum GNUNET_DB_QueryStatus qs;

  wpd->eh = NULL;
  switch (tr->http_status)
  {
  case MHD_HTTP_OK:
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Wire transfer %llu completed successfully\n",
                (unsigned long long) wpd->row_id);
    qs = db_plugin->wire_prepare_data_mark_finished (db_plugin->cls,
                                                     wpd->row_id);
    /* continued below */
    break;
  case MHD_HTTP_NOT_FOUND:
  case MHD_HTTP_CONFLICT:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Wire transaction %llu failed: %u/%d\n",
                (unsigned long long) wpd->row_id,
                tr->http_status,
                tr->ec);
    qs = db_plugin->wire_prepare_data_mark_failed (db_plugin->cls,
                                                   wpd->row_id);
    /* continued below */
    break;
  case 0:
  case MHD_HTTP_TOO_MANY_REQUESTS:
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
  case MHD_HTTP_BAD_GATEWAY:
  case MHD_HTTP_SERVICE_UNAVAILABLE:
  case MHD_HTTP_GATEWAY_TIMEOUT:
    wpd->retries++;
    if (wpd->retries < MAX_RETRIES)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Wire transfer %llu failed (%u), trying again\n",
                  (unsigned long long) wpd->row_id,
                  tr->http_status);
      wpd->eh = TALER_BANK_transfer (ctx,
                                     wpd->wa->auth,
                                     &wpd[1],
                                     wpd->buf_size,
                                     &wire_confirm_cb,
                                     wpd);
      return;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Wire transaction %llu failed: %u/%d\n",
                (unsigned long long) wpd->row_id,
                tr->http_status,
                tr->ec);
    cleanup_wpd ();
    db_plugin->rollback (db_plugin->cls);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Wire transfer %llu failed: %u/%d\n",
                (unsigned long long) wpd->row_id,
                tr->http_status,
                tr->ec);
    db_plugin->rollback (db_plugin->cls);
    cleanup_wpd ();
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  shard->batch_end = GNUNET_MAX (wpd->row_id,
                                 shard->batch_end);
  switch (qs)
  {
  case GNUNET_DB_STATUS_SOFT_ERROR:
    db_plugin->rollback (db_plugin->cls);
    cleanup_wpd ();
    GNUNET_assert (NULL == task);
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Serialization failure, trying again immediately!\n");
    task = GNUNET_SCHEDULER_add_now (&run_transfers,
                                     NULL);
    return;
  case GNUNET_DB_STATUS_HARD_ERROR:
    db_plugin->rollback (db_plugin->cls);
    cleanup_wpd ();
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    GNUNET_CONTAINER_DLL_remove (wpd_head,
                                 wpd_tail,
                                 wpd);
    GNUNET_free (wpd);
    break;
  }
  if (NULL != wpd_head)
    return; /* wait for other queries to complete */
  batch_done ();
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
  struct WirePrepareData *wpd;

  (void) cls;
  if ( (NULL != task) ||
       (EXIT_SUCCESS != global_ret) )
    return; /* current transaction was aborted */
  if (rowid >= shard->shard_end)
  {
    /* skip */
    shard->batch_end = shard->shard_end - 1;
    if (NULL != wpd_head)
      return;
    batch_done ();
    return;
  }
  if ( (NULL == wire_method) ||
       (NULL == buf) )
  {
    GNUNET_break (0);
    db_plugin->rollback (db_plugin->cls);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  wpd = GNUNET_malloc (sizeof (struct WirePrepareData)
                       + buf_size);
  GNUNET_memcpy (&wpd[1],
                 buf,
                 buf_size);
  wpd->buf_size = buf_size;
  wpd->row_id = rowid;
  GNUNET_CONTAINER_DLL_insert (wpd_head,
                               wpd_tail,
                               wpd);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting wire transfer %llu\n",
              (unsigned long long) rowid);
  wpd->wa = TALER_EXCHANGEDB_find_account_by_method (wire_method);
  if (NULL == wpd->wa)
  {
    /* Should really never happen here, as when we get
       here the wire account should be in the cache. */
    GNUNET_break (0);
    cleanup_wpd ();
    db_plugin->rollback (db_plugin->cls);
    global_ret = EXIT_NO_RESTART;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  wpd->eh = TALER_BANK_transfer (ctx,
                                 wpd->wa->auth,
                                 buf,
                                 buf_size,
                                 &wire_confirm_cb,
                                 wpd);
  if (NULL == wpd->eh)
  {
    GNUNET_break (0); /* Irrecoverable */
    cleanup_wpd ();
    db_plugin->rollback (db_plugin->cls);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
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
  int64_t limit;

  (void) cls;
  task = NULL;
  limit = shard->shard_end - shard->batch_start;
  if (0 >= limit)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Shard [%llu,%llu) completed\n",
                (unsigned long long) shard->shard_start,
                (unsigned long long) shard->batch_end);
    qs = db_plugin->complete_shard (db_plugin->cls,
                                    "transfer",
                                    shard->shard_start,
                                    shard->batch_end + 1);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_break (0);
      GNUNET_free (shard);
      GNUNET_SCHEDULER_shutdown ();
      return;
    case GNUNET_DB_STATUS_SOFT_ERROR:
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Got DB soft error for complete_shard. Rolling back.\n");
      GNUNET_free (shard);
      GNUNET_assert (NULL == task);
      task = GNUNET_SCHEDULER_add_now (&select_shard,
                                       NULL);
      return;
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      /* already existed, ok, let's just continue */
      break;
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      /* normal case */
      break;
    }
    shard_delay = GNUNET_TIME_absolute_get_duration (
      shard->shard_start_time);
    GNUNET_free (shard);
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&select_shard,
                                     NULL);
    return;
  }
  /* cap number of parallel connections to a reasonable
     limit for concurrent requests to the bank */
  limit = GNUNET_MIN (limit,
                      256);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Checking for %lld pending wire transfers [%llu-...)\n",
              (long long) limit,
              (unsigned long long) shard->batch_start);
  if (GNUNET_OK !=
      db_plugin->start_read_committed (db_plugin->cls,
                                       "aggregator run transfer"))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to start database transaction!\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  GNUNET_assert (NULL == task);
  qs = db_plugin->wire_prepare_data_get (db_plugin->cls,
                                         shard->batch_start,
                                         limit,
                                         &wire_prepare_cb,
                                         NULL);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    cleanup_wpd ();
    db_plugin->rollback (db_plugin->cls);
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    /* try again */
    db_plugin->rollback (db_plugin->cls);
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Serialization failure, trying again immediately!\n");
    cleanup_wpd ();
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_transfers,
                                     NULL);
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    /* no more prepared wire transfers, go sleep a bit! */
    db_plugin->rollback (db_plugin->cls);
    GNUNET_assert (NULL == wpd_head);
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
      GNUNET_assert (NULL == task);
      task = GNUNET_SCHEDULER_add_delayed (transfer_idle_sleep_interval,
                                           &run_transfers_delayed,
                                           NULL);
    }
    return;
  default:
    /* continued in wire_prepare_cb() */
    return;
  }
}


/**
 * Select shard to process.
 *
 * @param cls NULL
 */
static void
select_shard (void *cls)
{
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_TIME_Relative delay;
  uint64_t start;
  uint64_t end;

  (void) cls;
  task = NULL;
  GNUNET_assert (NULL == wpd_head);
  if (GNUNET_SYSERR ==
      db_plugin->preflight (db_plugin->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain database connection!\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (0 == max_workers)
    delay = GNUNET_TIME_UNIT_ZERO;
  else
    delay.rel_value_us = GNUNET_CRYPTO_random_u64 (
      GNUNET_CRYPTO_QUALITY_WEAK,
      4 * GNUNET_TIME_relative_max (
        transfer_idle_sleep_interval,
        GNUNET_TIME_relative_multiply (shard_delay,
                                       max_workers)).rel_value_us);
  qs = db_plugin->begin_shard (db_plugin->cls,
                               "transfer",
                               delay,
                               shard_size,
                               &start,
                               &end);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain starting point for montoring from database!\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    /* try again */
    {
      serialization_delay = GNUNET_TIME_randomized_backoff (serialization_delay,
                                                            GNUNET_TIME_UNIT_SECONDS);
      GNUNET_assert (NULL == task);
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Serialization failure, trying again in %s!\n",
                  GNUNET_TIME_relative2s (serialization_delay,
                                          true));
      task = GNUNET_SCHEDULER_add_delayed (serialization_delay,
                                           &select_shard,
                                           NULL);
    }
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_break (0);
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_delayed (transfer_idle_sleep_interval,
                                         &select_shard,
                                         NULL);
    return;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    /* continued below */
    break;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting with shard [%llu,%llu)\n",
              (unsigned long long) start,
              (unsigned long long) end);
  shard = GNUNET_new (struct Shard);
  shard->shard_start_time = GNUNET_TIME_absolute_get ();
  shard->shard_start = start;
  shard->shard_end = end;
  shard->batch_start = start;
  GNUNET_assert (NULL == task);
  task = GNUNET_SCHEDULER_add_now (&run_transfers,
                                   NULL);
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
  if (GNUNET_OK != parse_transfer_config ())
  {
    cfg = NULL;
    global_ret = EXIT_NOTCONFIGURED;
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
  task = GNUNET_SCHEDULER_add_now (&select_shard,
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
    GNUNET_GETOPT_option_uint ('S',
                               "size",
                               "SIZE",
                               "Size to process per shard (default: 1024)",
                               &shard_size),
    GNUNET_GETOPT_option_timetravel ('T',
                                     "timetravel"),
    GNUNET_GETOPT_option_flag ('t',
                               "test",
                               "run in test mode and exit when idle",
                               &test_mode),
    GNUNET_GETOPT_option_uint ('w',
                               "workers",
                               "COUNT",
                               "Plan work load with up to COUNT worker processes (default: 16)",
                               &max_workers),
    GNUNET_GETOPT_option_version (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  TALER_OS_init ();
  ret = GNUNET_PROGRAM_run (
    argc, argv,
    "taler-exchange-transfer",
    gettext_noop (
      "background process that executes outgoing wire transfers"),
    options,
    &run, NULL);
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  return global_ret;
}


/* end of taler-exchange-transfer.c */
