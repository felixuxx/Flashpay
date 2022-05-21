/*
  This file is part of TALER
  Copyright (C) 2016--2022 Taler Systems SA

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


/**
 * How long to wait for an HTTP reply if there
 * are no transactions pending at the server?
 */
#define LONGPOLL_TIMEOUT GNUNET_TIME_UNIT_MINUTES

/**
 * What is the maximum batch size we use for credit history
 * requests with the bank.  See `batch_size` below.
 */
#define MAXIMUM_BATCH_SIZE 1024

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
   * Information about this account.
   */
  const struct TALER_EXCHANGEDB_AccountInfo *ai;

  /**
   * Active request for history.
   */
  struct TALER_BANK_CreditHistoryHandle *hh;

  /**
   * Until when is processing this wire plugin delayed?
   */
  struct GNUNET_TIME_Absolute delayed_until;

  /**
   * Encoded offset in the wire transfer list from where
   * to start the next query with the bank.
   */
  uint64_t batch_start;

  /**
   * Latest row offset seen in this transaction, becomes
   * the new #batch_start upon commit.
   */
  uint64_t latest_row_off;

  /**
   * Maximum row offset this transaction may yield. If we got the
   * maximum number of rows, we must not @e delay before running
   * the next transaction.
   */
  uint64_t max_row_off;

  /**
   * Offset where our current shard begins (inclusive).
   */
  uint64_t shard_start;

  /**
   * Offset where our current shard ends (exclusive).
   */
  uint64_t shard_end;

  /**
   * When did we start with the shard?
   */
  struct GNUNET_TIME_Absolute shard_start_time;

  /**
   * How long did we take to finish the last shard
   * for this account?
   */
  struct GNUNET_TIME_Relative shard_delay;

  /**
   * Name of our job in the shard table.
   */
  char *job_name;

  /**
   * How many transactions do we retrieve per batch?
   */
  unsigned int batch_size;

  /**
   * How much do we increment @e batch_size on success?
   */
  unsigned int batch_thresh;

  /**
   * Should we delay the next request to the wire plugin a bit?  Set to
   * false if we actually did some work.
   */
  bool delay;

  /**
   * Did we start a transaction yet?
   */
  bool started_transaction;

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
 * Also used for how long we wait to grab a shard before trying it again.
 * The value should be set to a bit above the average time it takes to
 * process a shard.
 */
static struct GNUNET_TIME_Relative wirewatch_idle_sleep_interval;

/**
 * Modulus to apply to group shards.  The shard size must ultimately be a
 * multiple of the batch size. Thus, if this is not a multiple of the
 * #MAXIMUM_BATCH_SIZE, the batch size will be set to the #shard_size.
 */
static unsigned int shard_size = MAXIMUM_BATCH_SIZE;

/**
 * How many workers should we plan our scheduling with?
 */
static unsigned int max_workers = 16;


/**
 * Value to return from main(). 0 on success, non-zero on
 * on serious errors.
 */
static int global_ret;

/**
 * Are we run in testing mode and should only do one pass?
 */
static int test_mode;

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
      enum GNUNET_DB_QueryStatus qs;

      if (NULL != wa->hh)
      {
        TALER_BANK_credit_history_cancel (wa->hh);
        wa->hh = NULL;
      }
      GNUNET_CONTAINER_DLL_remove (wa_head,
                                   wa_tail,
                                   wa);
      if (wa->started_transaction)
      {
        db_plugin->rollback (db_plugin->cls);
        wa->started_transaction = false;
      }
      qs = db_plugin->abort_shard (db_plugin->cls,
                                   wa->job_name,
                                   wa->shard_start,
                                   wa->shard_end);
      if (qs <= 0)
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Failed to abort work shard on shutdown\n");
      GNUNET_free (wa->job_name);
      GNUNET_free (wa);
    }
  }
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
  TALER_EXCHANGEDB_unload_accounts ();
  cfg = NULL;
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
  if (! ai->credit_enabled)
    return; /* not enabled for us, skip */
  wa = GNUNET_new (struct WireAccount);
  wa->ai = ai;
  GNUNET_asprintf (&wa->job_name,
                   "wirewatch-%s",
                   ai->section_name);
  wa->batch_size = MAXIMUM_BATCH_SIZE;
  if (0 != shard_size % wa->batch_size)
    wa->batch_size = shard_size;
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
static enum GNUNET_GenericReturnValue
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
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize DB subsystem\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_EXCHANGEDB_load_accounts (cfg,
                                      TALER_EXCHANGEDB_ALO_CREDIT
                                      | TALER_EXCHANGEDB_ALO_AUTHDATA))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "No wire accounts configured for credit!\n");
    TALER_EXCHANGEDB_plugin_unload (db_plugin);
    db_plugin = NULL;
    return GNUNET_SYSERR;
  }
  TALER_EXCHANGEDB_find_accounts (&add_account_cb,
                                  NULL);
  GNUNET_assert (NULL != wa_head);
  return GNUNET_OK;
}


/**
 * Lock a shard and then begin to query for incoming wire transfers.
 *
 * @param cls a `struct WireAccount` to operate on
 */
static void
lock_shard (void *cls);


/**
 * Continue with the credit history of the shard
 * reserved as @a wa.
 *
 * @param[in,out] cls `struct WireAccount *` account with shard to continue processing
 */
static void
continue_with_shard (void *cls);


/**
 * We encountered a serialization error.
 * Rollback the transaction and try again
 *
 * @param wa account we are transacting on
 */
static void
handle_soft_error (struct WireAccount *wa)
{
  db_plugin->rollback (db_plugin->cls);
  wa->started_transaction = false;
  if (1 < wa->batch_size)
  {
    wa->batch_thresh = wa->batch_size;
    wa->batch_size /= 2;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Reduced batch size to %llu due to serialization issue\n",
                (unsigned long long) wa->batch_size);
  }
  GNUNET_assert (NULL == task);
  /* Reset to beginning of transaction, and go again
     from there. */
  wa->latest_row_off = wa->batch_start;
  task = GNUNET_SCHEDULER_add_now (&continue_with_shard,
                                   wa);
}


/**
 * Schedule the #lock_shard() operation for
 * @a wa. If @a wa is NULL, start with #wa_head.
 *
 * @param wa account to schedule #lock_shard() for,
 *        possibly NULL (!).
 */
static void
schedule_transfers (struct WireAccount *wa)
{
  if (NULL == wa)
  {
    wa = wa_head;
    GNUNET_assert (NULL != wa);
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Will try to lock next shard of %s in %s\n",
              wa->job_name,
              GNUNET_STRINGS_relative_time_to_string (
                GNUNET_TIME_absolute_get_remaining (wa->delayed_until),
                GNUNET_YES));
  GNUNET_assert (NULL == task);
  task = GNUNET_SCHEDULER_add_at (wa->delayed_until,
                                  &lock_shard,
                                  wa);
}


/**
 * We are done with the work that is possible on @a wa right now (and the
 * transaction was committed, if there was one to commit). Move on to the next
 * account.
 *
 * @param wa wire account for which we completed a shard
 */
static void
account_completed (struct WireAccount *wa)
{
  GNUNET_assert (! wa->started_transaction);
  if ( (wa->batch_start + wa->batch_size ==
        wa->latest_row_off) &&
       (wa->batch_size < MAXIMUM_BATCH_SIZE) )
  {
    /* The current batch size worked without serialization
       issues, and we are allowed to grow. Do so slowly. */
    int delta;

    delta = ((int) wa->batch_thresh - (int) wa->batch_size) / 4;
    if (delta < 0)
      delta = -delta;
    wa->batch_size = GNUNET_MIN (MAXIMUM_BATCH_SIZE,
                                 wa->batch_size + delta + 1);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Increasing batch size to %llu\n",
                (unsigned long long) wa->batch_size);
  }

  if (wa->delay)
  {
    /* This account was finished, block this one for the
       #wirewatch_idle_sleep_interval and move on to the next one. */
    wa->delayed_until
      = GNUNET_TIME_relative_to_absolute (wirewatch_idle_sleep_interval);
    wa = wa->next;
  }
  schedule_transfers (wa);
}


/**
 * Check if we are finished with the current shard.  If so, update the
 * database, marking the shard as finished.
 *
 * @param wa wire account to commit for
 * @return true if we were indeed done with the shard
 */
static bool
check_shard_done (struct WireAccount *wa)
{
  enum GNUNET_DB_QueryStatus qs;

  if (wa->shard_end > wa->latest_row_off)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Shard %s (%llu,%llu] at %llu\n",
                wa->job_name,
                (unsigned long long) wa->shard_start,
                (unsigned long long) wa->shard_end,
                (unsigned long long) wa->latest_row_off);
    return false; /* actually, not done! */
  }
  /* shard is complete, mark this as well */
  qs = db_plugin->complete_shard (db_plugin->cls,
                                  wa->job_name,
                                  wa->shard_start,
                                  wa->shard_end);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    db_plugin->rollback (db_plugin->cls);
    GNUNET_SCHEDULER_shutdown ();
    return false;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Got DB soft error for complete_shard. Rolling back.\n");
    handle_soft_error (wa);
    return false;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_break (0);
    /* Not expected, but let's just continue */
    break;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    /* normal case */
    wa->shard_delay = GNUNET_TIME_absolute_get_duration (wa->shard_start_time);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Completed shard %s (%llu,%llu] after %s\n",
                wa->job_name,
                (unsigned long long) wa->shard_start,
                (unsigned long long) wa->shard_end,
                GNUNET_STRINGS_relative_time_to_string (wa->shard_delay,
                                                        GNUNET_YES));
    break;
  }
  return true;
}


/**
 * We are finished with the current transaction, try
 * to commit and then schedule the next iteration.
 *
 * @param wa wire account to commit for
 */
static void
do_commit (struct WireAccount *wa)
{
  enum GNUNET_DB_QueryStatus qs;
  bool shard_done;

  shard_done = check_shard_done (wa);
  wa->started_transaction = false;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Committing %s progress (%llu,%llu] at %llu\n (%s)",
              wa->job_name,
              (unsigned long long) wa->shard_start,
              (unsigned long long) wa->shard_end,
              (unsigned long long) wa->latest_row_off,
              shard_done
              ? "shard done"
              : "shard incomplete");
  qs = db_plugin->commit (db_plugin->cls);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    GNUNET_SCHEDULER_shutdown ();
    return;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    /* reduce transaction size to reduce rollback probability */
    handle_soft_error (wa);
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    /* normal case */
    break;
  }
  if (shard_done)
    account_completed (wa);
  else
    continue_with_shard (wa);
}


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
static enum GNUNET_GenericReturnValue
history_cb (void *cls,
            unsigned int http_status,
            enum TALER_ErrorCode ec,
            uint64_t serial_id,
            const struct TALER_BANK_CreditDetails *details,
            const json_t *json)
{
  struct WireAccount *wa = cls;
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
    else
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "History response complete\n");
    }
    if (wa->started_transaction)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "End of list. Committing progress on %s of (%llu,%llu]!\n",
                  wa->job_name,
                  (unsigned long long) wa->batch_start,
                  (unsigned long long) wa->latest_row_off);
      do_commit (wa);
      return GNUNET_OK; /* will be ignored anyway */
    }
    /* We did not even start a transaction. */
    if ( (wa->delay) &&
         (test_mode) &&
         (NULL == wa->next) )
    {
      /* We exit on idle */
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Shutdown due to test mode!\n");
      GNUNET_SCHEDULER_shutdown ();
      return GNUNET_OK;
    }
    account_completed (wa);
    return GNUNET_OK; /* will be ignored anyway */
  }

  /* We did get 'details' from the bank. Do sanity checks before inserting. */
  if (serial_id < wa->latest_row_off)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Serial ID %llu not monotonic (got %llu before). Failing!\n",
                (unsigned long long) serial_id,
                (unsigned long long) wa->latest_row_off);
    GNUNET_SCHEDULER_shutdown ();
    wa->hh = NULL;
    return GNUNET_SYSERR;
  }
  /* If we got 'limit' transactions back from the bank,
     we should not introduce any delay before the next
     call. */
  if (serial_id >= wa->max_row_off)
    wa->delay = false;
  if (serial_id > wa->shard_end)
  {
    /* we are *past* the current shard (likely because the serial_id of the
       shard_end happens to not exist in the DB). So commit and stop this
       iteration! */
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Serial ID %llu past shard end at %llu, ending iteration early!\n",
                (unsigned long long) serial_id,
                (unsigned long long) wa->shard_end);
    wa->latest_row_off = serial_id - 1; /* excluding serial_id! */
    wa->hh = NULL;
    if (wa->started_transaction)
    {
      do_commit (wa);
    }
    else
    {
      if (check_shard_done (wa))
        account_completed (wa);
      else
        continue_with_shard (wa);
    }
    return GNUNET_SYSERR;
  }
  if (! wa->started_transaction)
  {
    if (GNUNET_OK !=
        db_plugin->start_read_committed (db_plugin->cls,
                                         "wirewatch check for incoming wire transfers"))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to start database transaction!\n");
      global_ret = EXIT_FAILURE;
      GNUNET_SCHEDULER_shutdown ();
      wa->hh = NULL;
      return GNUNET_SYSERR;
    }
    wa->started_transaction = true;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Adding wire transfer over %s with (hashed) subject `%s'\n",
              TALER_amount2s (&details->amount),
              TALER_B2S (&details->reserve_pub));
  /* FIXME-PERFORMANCE: Consider using Postgres multi-valued insert here,
     for up to 15x speed-up according to
     https://dba.stackexchange.com/questions/224989/multi-row-insert-vs-transactional-single-row-inserts#225006
     (Note: this may require changing both the
     plugin API as well as modifying how this function is called.) */
  qs = db_plugin->reserves_in_insert (db_plugin->cls,
                                      &details->reserve_pub,
                                      &details->amount,
                                      details->execution_date,
                                      details->debit_account_uri,
                                      wa->ai->section_name,
                                      serial_id);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    db_plugin->rollback (db_plugin->cls);
    wa->started_transaction = false;
    GNUNET_SCHEDULER_shutdown ();
    wa->hh = NULL;
    return GNUNET_SYSERR;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Got DB soft error for reserves_in_insert. Rolling back.\n");
    handle_soft_error (wa);
    wa->hh = NULL;
    return GNUNET_SYSERR;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    /* Either wirewatch was freshly started after the system was
       shutdown and we're going over an incomplete shard again
       after being restarted, or the shard lock period was too
       short (number of workers set incorrectly?) and a 2nd
       wirewatcher has been stealing our work while we are still
       at it. */
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Attempted to import transaction %llu (%s) twice. "
                "This should happen rarely (if not, ask for support).\n",
                (unsigned long long) serial_id,
                wa->job_name);
    /* already existed, ok, let's just continue */
    break;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    /* normal case */
    break;
  }
  wa->latest_row_off = serial_id;
  return GNUNET_OK;
}


static void
continue_with_shard (void *cls)
{
  struct WireAccount *wa = cls;
  unsigned int limit;

  limit = GNUNET_MIN (wa->batch_size,
                      wa->shard_end - wa->latest_row_off);
  wa->max_row_off = wa->latest_row_off + limit;
  GNUNET_assert (NULL == wa->hh);
  wa->hh = TALER_BANK_credit_history (ctx,
                                      wa->ai->auth,
                                      wa->latest_row_off,
                                      limit,
                                      test_mode
                                      ? GNUNET_TIME_UNIT_ZERO
                                      : LONGPOLL_TIMEOUT,
                                      &history_cb,
                                      wa);
  if (NULL == wa->hh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to start request for account history!\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


static void
lock_shard (void *cls)
{
  struct WireAccount *wa = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_TIME_Relative delay;

  task = NULL;
  if (GNUNET_SYSERR ==
      db_plugin->preflight (db_plugin->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain database connection!\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  /* How long we lock a shard depends on the number of
     workers expected, and how long we usually took to
     process a shard. */
  if (0 == max_workers)
    delay = GNUNET_TIME_UNIT_ZERO;
  else
    delay.rel_value_us = GNUNET_CRYPTO_random_u64 (
      GNUNET_CRYPTO_QUALITY_WEAK,
      4 * GNUNET_TIME_relative_max (
        wirewatch_idle_sleep_interval,
        GNUNET_TIME_relative_multiply (wa->shard_delay,
                                       max_workers)).rel_value_us);
  wa->shard_start_time = GNUNET_TIME_absolute_get ();
  qs = db_plugin->begin_shard (db_plugin->cls,
                               wa->job_name,
                               delay,
                               shard_size,
                               &wa->shard_start,
                               &wa->shard_end);
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
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Serialization error tying to obtain shard %s, will try again in %s!\n",
                wa->job_name,
                GNUNET_STRINGS_relative_time_to_string (
                  wirewatch_idle_sleep_interval,
                  GNUNET_YES));
    wa->delayed_until = GNUNET_TIME_relative_to_absolute (
      wirewatch_idle_sleep_interval);
    schedule_transfers (wa->next);
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "No shard available, will try again for %s in %s!\n",
                wa->job_name,
                GNUNET_STRINGS_relative_time_to_string (
                  wirewatch_idle_sleep_interval,
                  GNUNET_YES));
    wa->delayed_until = GNUNET_TIME_relative_to_absolute (
      wirewatch_idle_sleep_interval);
    schedule_transfers (wa->next);
    return;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    /* continued below */
    break;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting with shard %s at (%llu,%llu] locked for %s\n",
              wa->job_name,
              (unsigned long long) wa->shard_start,
              (unsigned long long) wa->shard_end,
              GNUNET_STRINGS_relative_time_to_string (delay,
                                                      GNUNET_YES));
  wa->delay = true; /* default is to delay, unless
                       we find out that we're really busy */
  wa->batch_start = wa->shard_start;
  wa->latest_row_off = wa->batch_start;
  continue_with_shard (wa);
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
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  GNUNET_SCHEDULER_add_shutdown (&shutdown_task,
                                 cls);
  ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &rc);
  if (NULL == ctx)
  {
    GNUNET_break (0);
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  rc = GNUNET_CURL_gnunet_rc_create (ctx);
  task = GNUNET_SCHEDULER_add_now (&lock_shard,
                                   wa_head);
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

  if (GNUNET_OK !=
      GNUNET_STRINGS_get_utf8_args (argc, argv,
                                    &argc, &argv))
    return EXIT_INVALIDARGUMENT;
  TALER_OS_init ();
  ret = GNUNET_PROGRAM_run (
    argc, argv,
    "taler-exchange-wirewatch",
    gettext_noop (
      "background process that watches for incoming wire transfers from customers"),
    options,
    &run, NULL);
  GNUNET_free_nz ((void *) argv);
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  return global_ret;
}


/* end of taler-exchange-wirewatch.c */
