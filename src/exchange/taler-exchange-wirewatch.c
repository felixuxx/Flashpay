/*
  This file is part of TALER
  Copyright (C) 2016--2023 Taler Systems SA

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
 * Information about our account.
 */
static const struct TALER_EXCHANGEDB_AccountInfo *ai;

/**
 * Active request for history.
 */
static struct TALER_BANK_CreditHistoryHandle *hh;

/**
 * Set to true if the request for history did actually
 * return transaction items.
 */
static bool hh_returned_data;

/**
 * Set to true if the request for history did not
 * succeed because the account was unknown.
 */
static bool hh_account_404;

/**
 * When did we start the last @e hh request?
 */
static struct GNUNET_TIME_Absolute hh_start_time;

/**
 * Until when is processing this wire plugin delayed?
 */
static struct GNUNET_TIME_Absolute delayed_until;

/**
 * Encoded offset in the wire transfer list from where
 * to start the next query with the bank.
 */
static uint64_t batch_start;

/**
 * Latest row offset seen in this transaction, becomes
 * the new #batch_start upon commit.
 */
static uint64_t latest_row_off;

/**
 * Offset where our current shard begins (inclusive).
 */
static uint64_t shard_start;

/**
 * Offset where our current shard ends (exclusive).
 */
static uint64_t shard_end;

/**
 * When did we start with the shard?
 */
static struct GNUNET_TIME_Absolute shard_start_time;

/**
 * For how long did we lock the shard?
 */
static struct GNUNET_TIME_Absolute shard_end_time;

/**
 * How long did we take to finish the last shard
 * for this account?
 */
static struct GNUNET_TIME_Relative shard_delay;

/**
 * How long did we take to finish the last shard
 * for this account?
 */
static struct GNUNET_TIME_Relative longpoll_timeout;

/**
 * How long do we wait on 404.
 */
static struct GNUNET_TIME_Relative h404_backoff;

/**
 * Name of our job in the shard table.
 */
static char *job_name;

/**
 * How many transactions do we retrieve per batch?
 */
static unsigned int batch_size;

/**
 * How much do we increment @e batch_size on success?
 */
static unsigned int batch_thresh;

/**
 * Did work remain in the transaction queue? Set to true
 * if we did some work and thus there might be more.
 */
static bool progress;

/**
 * Did we start a transaction yet?
 */
static bool started_transaction;

/**
 * Is this shard still open for processing.
 */
static bool shard_open;

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
 * How long do we sleep on serialization conflicts?
 */
static struct GNUNET_TIME_Relative wirewatch_conflict_sleep_interval;

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
 * -e command-line option: exit on errors talking to the bank?
 */
static int exit_on_error;

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
 * Should we ignore if the bank does not know our bank
 * account?
 */
static int ignore_account_404;

/**
 * Current task waiting for execution, if any.
 */
static struct GNUNET_SCHEDULER_Task *task;

/**
 * Name of the configuration section with the account we should watch.
 */
static char *account_section;

/**
 * We're being aborted with CTRL-C (or SIGTERM). Shut down.
 *
 * @param cls closure
 */
static void
shutdown_task (void *cls)
{
  enum GNUNET_DB_QueryStatus qs;
  (void) cls;

  if (NULL != hh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "History request cancelled on shutdown\n");
    TALER_BANK_credit_history_cancel (hh);
    hh = NULL;
  }
  if (started_transaction)
  {
    db_plugin->rollback (db_plugin->cls);
    started_transaction = false;
  }
  if (shard_open)
  {
    qs = db_plugin->abort_shard (db_plugin->cls,
                                 job_name,
                                 shard_start,
                                 shard_end);
    if (qs <= 0)
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to abort work shard on shutdown\n");
  }
  GNUNET_free (job_name);
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
 * @param in_ai account information
 */
static void
add_account_cb (void *cls,
                const struct TALER_EXCHANGEDB_AccountInfo *in_ai)
{
  (void) cls;
  if (! in_ai->credit_enabled)
    return; /* not enabled for us, skip */
  if ( (NULL != account_section) &&
       (0 != strcasecmp (in_ai->section_name,
                         account_section)) )
    return; /* not enabled for us, skip */
  if (NULL != ai)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Multiple accounts enabled (%s and %s), use '-a' command-line option to select one!\n",
                ai->section_name,
                in_ai->section_name);
    GNUNET_SCHEDULER_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  ai = in_ai;
  GNUNET_asprintf (&job_name,
                   "wirewatch-%s",
                   ai->section_name);
  batch_size = MAXIMUM_BATCH_SIZE;
  if (0 != shard_size % batch_size)
    batch_size = shard_size;
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
    return GNUNET_SYSERR;
  }
  TALER_EXCHANGEDB_find_accounts (&add_account_cb,
                                  NULL);
  if (NULL == ai)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "No accounts enabled for credit!\n");
    GNUNET_SCHEDULER_shutdown ();
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Lock a shard and then begin to query for incoming wire transfers.
 *
 * @param cls NULL
 */
static void
lock_shard (void *cls);


/**
 * Continue with the credit history of the shard.
 *
 * @param cls NULL
 */
static void
continue_with_shard (void *cls);


/**
 * We encountered a serialization error.  Rollback the transaction and try
 * again.
 */
static void
handle_soft_error (void)
{
  db_plugin->rollback (db_plugin->cls);
  started_transaction = false;
  if (1 < batch_size)
  {
    batch_thresh = batch_size;
    batch_size /= 2;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Reduced batch size to %llu due to serialization issue\n",
                (unsigned long long) batch_size);
  }
  /* Reset to beginning of transaction, and go again
     from there. */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Encountered soft error, resetting start point to batch start\n");
  latest_row_off = batch_start;
  GNUNET_assert (NULL == task);
  task = GNUNET_SCHEDULER_add_now (&continue_with_shard,
                                   NULL);
}


/**
 * Schedule the #lock_shard() operation.
 */
static void
schedule_transfers (void)
{
  if (shard_open)
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Will retry my shard (%llu,%llu] of %s in %s\n",
                (unsigned long long) shard_start,
                (unsigned long long) shard_end,
                job_name,
                GNUNET_STRINGS_relative_time_to_string (
                  GNUNET_TIME_absolute_get_remaining (delayed_until),
                  true));
  else
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Will try to lock next shard of %s in %s\n",
                job_name,
                GNUNET_STRINGS_relative_time_to_string (
                  GNUNET_TIME_absolute_get_remaining (delayed_until),
                  true));
  GNUNET_assert (NULL == task);
  task = GNUNET_SCHEDULER_add_at (delayed_until,
                                  &lock_shard,
                                  NULL);
}


/**
 * We are done with the work that is possible right now (and the transaction
 * was committed, if there was one to commit). Move on to the next shard.
 */
static void
transaction_completed (void)
{
  if ( (batch_start + batch_size ==
        latest_row_off) &&
       (batch_size < MAXIMUM_BATCH_SIZE) )
  {
    /* The current batch size worked without serialization
       issues, and we are allowed to grow. Do so slowly. */
    int delta;

    delta = ((int) batch_thresh - (int) batch_size) / 4;
    if (delta < 0)
      delta = -delta;
    batch_size = GNUNET_MIN (MAXIMUM_BATCH_SIZE,
                             batch_size + delta + 1);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Increasing batch size to %llu\n",
                (unsigned long long) batch_size);
  }

  if ( (! progress) && test_mode)
  {
    /* Transaction list was drained and we are in
       test mode. So we are done. */
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Transaction list drained and in test mode. Exiting\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (! (hh_returned_data || hh_account_404) )
  {
    /* Enforce long-polling delay even if the server ignored it
       and returned earlier */
    struct GNUNET_TIME_Relative latency;
    struct GNUNET_TIME_Relative left;

    latency = GNUNET_TIME_absolute_get_duration (hh_start_time);
    left = GNUNET_TIME_relative_subtract (longpoll_timeout,
                                          latency);
    if (! (test_mode ||
           GNUNET_TIME_relative_is_zero (left)) )
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Server did not respect long-polling, enforcing client-side by sleeping for %s\n",
                  GNUNET_TIME_relative2s (left,
                                          true));
    delayed_until = GNUNET_TIME_relative_to_absolute (left);
  }
  if (hh_account_404)
  {
    h404_backoff = GNUNET_TIME_STD_BACKOFF (h404_backoff);
    delayed_until = GNUNET_TIME_relative_to_absolute (
      h404_backoff);
  }
  else
  {
    h404_backoff = GNUNET_TIME_UNIT_ZERO;
  }
  if (test_mode)
    delayed_until = GNUNET_TIME_UNIT_ZERO_ABS;
  GNUNET_assert (NULL == task);
  schedule_transfers ();
}


/**
 * We got incoming transaction details from the bank. Add them
 * to the database.
 *
 * @param details array of transaction details
 * @param details_length length of the @a details array
 */
static void
process_reply (const struct TALER_BANK_CreditDetails *details,
               unsigned int details_length)
{
  enum GNUNET_DB_QueryStatus qs;
  bool shard_done;
  uint64_t lroff = latest_row_off;

  if (0 == details_length)
  {
    /* Server should have used 204, not 200! */
    GNUNET_break_op (0);
    transaction_completed ();
    return;
  }
  hh_returned_data = true;
  /* check serial IDs for range constraints */
  for (unsigned int i = 0; i<details_length; i++)
  {
    const struct TALER_BANK_CreditDetails *cd = &details[i];

    if (cd->serial_id < lroff)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Serial ID %llu not monotonic (got %llu before). Failing!\n",
                  (unsigned long long) cd->serial_id,
                  (unsigned long long) lroff);
      db_plugin->rollback (db_plugin->cls);
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
    if (cd->serial_id > shard_end)
    {
      /* we are *past* the current shard (likely because the serial_id of the
         shard_end happens to not exist in the DB). So commit and stop this
         iteration! */
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Serial ID %llu past shard end at %llu, ending iteration early!\n",
                  (unsigned long long) cd->serial_id,
                  (unsigned long long) shard_end);
      details_length = i;
      progress = true;
      lroff = cd->serial_id - 1;
      break;
    }
    lroff = cd->serial_id;
  }
  if (0 != details_length)
  {
    enum GNUNET_DB_QueryStatus qss[details_length];
    struct TALER_EXCHANGEDB_ReserveInInfo reserves[details_length];
    unsigned int j = 0;

    /* make compiler happy */
    memset (qss,
            0,
            sizeof (qss));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Importing %u transactions\n",
                details_length);
    for (unsigned int i = 0; i<details_length; i++)
    {
      const struct TALER_BANK_CreditDetails *cd = &details[i];

      switch (cd->type)
      {
      case TALER_BANK_CT_RESERVE:
        {
          struct TALER_EXCHANGEDB_ReserveInInfo *res = &reserves[j++];

          /* add to batch, do later */
          res->reserve_pub = &cd->details.reserve.reserve_pub;
          res->balance = &cd->amount;
          res->execution_time = cd->execution_date;
          res->sender_account_details = cd->debit_account_uri;
          res->exchange_account_name = ai->section_name;
          res->wire_reference = cd->serial_id;
        }
        break;
      case TALER_BANK_CT_KYCAUTH:
        {
          qs = db_plugin->kycauth_in_insert (
            db_plugin->cls,
            &cd->details.kycauth.account_pub,
            &cd->amount,
            cd->execution_date,
            cd->debit_account_uri,
            ai->section_name,
            cd->serial_id);
          switch (qs)
          {
          case GNUNET_DB_STATUS_HARD_ERROR:
            GNUNET_break (0);
            GNUNET_SCHEDULER_shutdown ();
            return;
          case GNUNET_DB_STATUS_SOFT_ERROR:
            GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                        "Got DB soft error for kycauth_in_insert (%u). Rolling back.\n",
                        i);
            handle_soft_error ();
            return;
          default:
            break;
          }
          break;
        }
      case TALER_BANK_CT_WAD:
        {
          qs = db_plugin->wad_in_insert (
            db_plugin->cls,
            &cd->details.wad.wad_id,
            cd->details.wad.origin_exchange_url,
            &cd->amount,
            cd->execution_date,
            cd->debit_account_uri,
            ai->section_name,
            cd->serial_id);
          switch (qs)
          {
          case GNUNET_DB_STATUS_HARD_ERROR:
            GNUNET_break (0);
            GNUNET_SCHEDULER_shutdown ();
            return;
          case GNUNET_DB_STATUS_SOFT_ERROR:
            GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                        "Got DB soft error for wad_in_insert (%u). Rolling back.\n",
                        i);
            handle_soft_error ();
            return;
          default:
            break;
          }

        }
      }
    }
    if (j > 0)
    {
      qs = db_plugin->reserves_in_insert (db_plugin->cls,
                                          reserves,
                                          j,
                                          qss);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        GNUNET_SCHEDULER_shutdown ();
        return;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Got DB soft error for reserves_in_insert (%u). Rolling back.\n",
                    details_length);
        handle_soft_error ();
        return;
      default:
        break;
      }
    }
    j = 0;
    for (unsigned int i = 0; i<details_length; i++)
    {
      const struct TALER_BANK_CreditDetails *cd = &details[i];

      if (TALER_BANK_CT_RESERVE != cd->type)
        continue;
      switch (qss[j++])
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        GNUNET_SCHEDULER_shutdown ();
        return;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Got DB soft error for batch_reserves_in_insert(%u). Rolling back.\n",
                    i);
        handle_soft_error ();
        return;
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
                    (unsigned long long) cd->serial_id,
                    job_name);
        break;
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Imported transaction %llu.\n",
                    (unsigned long long) cd->serial_id);
        /* normal case */
        progress = true;
        break;
      }
    }
  }

  latest_row_off = lroff;
  shard_done = (shard_end <= latest_row_off);
  if (shard_done)
  {
    /* shard is complete, mark this as well */
    qs = db_plugin->complete_shard (db_plugin->cls,
                                    job_name,
                                    shard_start,
                                    shard_end);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_break (0);
      GNUNET_SCHEDULER_shutdown ();
      return;
    case GNUNET_DB_STATUS_SOFT_ERROR:
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Got DB soft error for complete_shard. Rolling back.\n");
      handle_soft_error ();
      return;
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      GNUNET_break (0);
      /* Not expected, but let's just continue */
      break;
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      /* normal case */
      progress = true;
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Completed shard %s (%llu,%llu] after %s\n",
                  job_name,
                  (unsigned long long) shard_start,
                  (unsigned long long) shard_end,
                  GNUNET_STRINGS_relative_time_to_string (
                    GNUNET_TIME_absolute_get_duration (shard_start_time),
                    true));
      break;
    }
    shard_delay = GNUNET_TIME_absolute_get_duration (shard_start_time);
    shard_open = false;
    transaction_completed ();
    return;
  }
  GNUNET_assert (NULL == task);
  task = GNUNET_SCHEDULER_add_now (&continue_with_shard,
                                   NULL);
}


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank for the transaction history.
 *
 * @param cls NULL
 * @param reply response we got from the bank
 */
static void
history_cb (void *cls,
            const struct TALER_BANK_CreditHistoryResponse *reply)
{
  (void) cls;
  GNUNET_assert (NULL == task);
  hh = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "History request returned with HTTP status %u\n",
              reply->http_status);
  switch (reply->http_status)
  {
  case MHD_HTTP_OK:
    process_reply (reply->details.ok.details,
                   reply->details.ok.details_length);
    return;
  case MHD_HTTP_NO_CONTENT:
    transaction_completed ();
    return;
  case MHD_HTTP_NOT_FOUND:
    hh_account_404 = true;
    if (ignore_account_404)
    {
      transaction_completed ();
      return;
    }
    break;
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Error fetching history: %s (%u)\n",
                TALER_ErrorCode_get_hint (reply->ec),
                reply->http_status);
    break;
  }
  if (! exit_on_error)
  {
    transaction_completed ();
    return;
  }
  GNUNET_SCHEDULER_shutdown ();
}


static void
continue_with_shard (void *cls)
{
  unsigned int limit;

  (void) cls;
  task = NULL;
  GNUNET_assert (shard_end > latest_row_off);
  limit = GNUNET_MIN (batch_size,
                      shard_end - latest_row_off);
  GNUNET_assert (NULL == hh);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Requesting credit history starting from %llu\n",
              (unsigned long long) latest_row_off);
  hh_start_time = GNUNET_TIME_absolute_get ();
  hh_returned_data = false;
  hh_account_404 = false;
  hh = TALER_BANK_credit_history (ctx,
                                  ai->auth,
                                  latest_row_off,
                                  limit,
                                  test_mode
                                  ? GNUNET_TIME_UNIT_ZERO
                                  : longpoll_timeout,
                                  &history_cb,
                                  NULL);
  if (NULL == hh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to start request for account history!\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


/**
 * Reserve a shard for us to work on.
 *
 * @param cls NULL
 */
static void
lock_shard (void *cls)
{
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_TIME_Relative delay;
  uint64_t last_shard_start = shard_start;
  uint64_t last_shard_end = shard_end;

  (void) cls;
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
  if ( (shard_open) &&
       (GNUNET_TIME_absolute_is_future (shard_end_time)) )
  {
    progress = false;
    batch_start = latest_row_off;
    task = GNUNET_SCHEDULER_add_now (&continue_with_shard,
                                     NULL);
    return;
  }
  if (shard_open)
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Shard not completed in time, will try to re-acquire\n");
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
        GNUNET_TIME_relative_multiply (shard_delay,
                                       max_workers)).rel_value_us);
  shard_start_time = GNUNET_TIME_absolute_get ();
  qs = db_plugin->begin_shard (db_plugin->cls,
                               job_name,
                               delay,
                               shard_size,
                               &shard_start,
                               &shard_end);
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
      struct GNUNET_TIME_Relative rdelay;

      wirewatch_conflict_sleep_interval
        = GNUNET_TIME_STD_BACKOFF (wirewatch_conflict_sleep_interval);
      rdelay = GNUNET_TIME_randomize (wirewatch_conflict_sleep_interval);
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Serialization error tying to obtain shard %s, will try again in %s!\n",
                  job_name,
                  GNUNET_STRINGS_relative_time_to_string (rdelay,
                                                          true));
#if 1
      if (GNUNET_TIME_relative_cmp (rdelay,
                                    >,
                                    GNUNET_TIME_UNIT_SECONDS))
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Delay would have been for %s\n",
                    GNUNET_TIME_relative2s (rdelay,
                                            true));
      rdelay = GNUNET_TIME_relative_min (rdelay,
                                         GNUNET_TIME_UNIT_SECONDS);
#endif
      delayed_until = GNUNET_TIME_relative_to_absolute (rdelay);
    }
    GNUNET_assert (NULL == task);
    schedule_transfers ();
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "No shard available, will try again for %s in %s!\n",
                job_name,
                GNUNET_STRINGS_relative_time_to_string (
                  wirewatch_idle_sleep_interval,
                  true));
    delayed_until = GNUNET_TIME_relative_to_absolute (
      wirewatch_idle_sleep_interval);
    shard_open = false;
    GNUNET_assert (NULL == task);
    schedule_transfers ();
    return;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    /* continued below */
    wirewatch_conflict_sleep_interval = GNUNET_TIME_UNIT_ZERO;
    break;
  }
  shard_end_time = GNUNET_TIME_relative_to_absolute (delay);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting with shard %s at (%llu,%llu] locked for %s\n",
              job_name,
              (unsigned long long) shard_start,
              (unsigned long long) shard_end,
              GNUNET_STRINGS_relative_time_to_string (delay,
                                                      true));
  progress = false;
  batch_start = shard_start;
  if ( (shard_open) &&
       (shard_start == last_shard_start) &&
       (shard_end == last_shard_end) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Continuing from %llu\n",
                (unsigned long long) latest_row_off);
    GNUNET_break (latest_row_off >= batch_start); /* resume where we left things */
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Resetting shard start to original start point (%d)\n",
                shard_open ? 1 : 0);
    latest_row_off = batch_start;
  }
  shard_open = true;
  task = GNUNET_SCHEDULER_add_now (&continue_with_shard,
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
  GNUNET_SCHEDULER_add_shutdown (&shutdown_task,
                                 cls);
  if (GNUNET_OK !=
      exchange_serve_process_config ())
  {
    global_ret = EXIT_NOTCONFIGURED;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &rc);
  if (NULL == ctx)
  {
    GNUNET_break (0);
    GNUNET_SCHEDULER_shutdown ();
    global_ret = EXIT_NO_RESTART;
    return;
  }
  rc = GNUNET_CURL_gnunet_rc_create (ctx);
  schedule_transfers ();
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
    GNUNET_GETOPT_option_string ('a',
                                 "account",
                                 "SECTION_NAME",
                                 "name of the configuration section with the account we should watch (needed if more than one is enabled for crediting)",
                                 &account_section),
    GNUNET_GETOPT_option_flag ('e',
                               "exit-on-error",
                               "terminate wirewatch if we failed to download information from the bank",
                               &exit_on_error),
    GNUNET_GETOPT_option_relative_time ('f',
                                        "longpoll-timeout",
                                        "DELAY",
                                        "what is the timeout when asking the bank about new transactions, specify with unit (e.g. --longpoll-timeout=30s)",
                                        &longpoll_timeout),
    GNUNET_GETOPT_option_flag ('I',
                               "ignore-not-found",
                               "continue, even if the bank account of the exchange was not found",
                               &ignore_account_404),
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

  longpoll_timeout = LONGPOLL_TIMEOUT;
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
