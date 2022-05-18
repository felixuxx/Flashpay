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
 * @file taler-exchange-aggregator.c
 * @brief Process that aggregates outgoing transactions and prepares their execution
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
 * Information about one aggregation process to be executed.  There is
 * at most one of these around at any given point in time.
 * Note that this limits parallelism, and we might want
 * to revise this decision at a later point.
 */
struct AggregationUnit
{
  /**
   * Public key of the merchant.
   */
  struct TALER_MerchantPublicKeyP merchant_pub;

  /**
   * Total amount to be transferred, before subtraction of @e fees.wire and rounding down.
   */
  struct TALER_Amount total_amount;

  /**
   * Final amount to be transferred (after fee and rounding down).
   */
  struct TALER_Amount final_amount;

  /**
   * Wire fee we charge for @e wp at @e execution_time.
   */
  struct TALER_WireFeeSet fees;

  /**
   * Wire transfer identifier we use.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * The current time (which triggered the aggregation and
   * defines the wire fee).
   */
  struct GNUNET_TIME_Timestamp execution_time;

  /**
   * Wire details of the merchant.
   */
  char *payto_uri;

  /**
   * Selected wire target for the aggregation.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Exchange wire account to be used for the preparation and
   * eventual execution of the aggregate wire transfer.
   */
  const struct TALER_EXCHANGEDB_AccountInfo *wa;

};


/**
 * Work shard we are processing.
 */
struct Shard
{

  /**
   * When did we start processing the shard?
   */
  struct GNUNET_TIME_Timestamp start_time;

  /**
   * Starting row of the shard.
   */
  uint32_t shard_start;

  /**
   * Inclusive end row of the shard.
   */
  uint32_t shard_end;

  /**
   * Number of starting points found in the shard.
   */
  uint64_t work_counter;

};


/**
 * What is the smallest unit we support for wire transfers?
 * We will need to round down to a multiple of this amount.
 */
static struct TALER_Amount currency_round_unit;

/**
 * What is the base URL of this exchange?  Used in the
 * wire transfer subjects so that merchants and governments
 * can ask for the list of aggregated deposits.
 */
static char *exchange_base_url;

/**
 * Set to #GNUNET_YES if this exchange does not support KYC checks
 * and thus deposits are to be aggregated regardless of the
 * KYC status of the target account.
 */
static int kyc_off;

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
 * How long should we sleep when idle before trying to find more work?
 */
static struct GNUNET_TIME_Relative aggregator_idle_sleep_interval;

/**
 * How big are the shards we are processing? Is an inclusive offset, so every
 * shard ranges from [X,X+shard_size) exclusive.  So a shard covers
 * shard_size slots.  The maximum value for shard_size is INT32_MAX+1.
 */
static uint32_t shard_size;

/**
 * Value to return from main(). 0 on success, non-zero on errors.
 */
static int global_ret;

/**
 * #GNUNET_YES if we are in test mode and should exit when idle.
 */
static int test_mode;


/**
 * Main work function that queries the DB and aggregates transactions
 * into larger wire transfers.
 *
 * @param cls a `struct Shard *`
 */
static void
run_aggregation (void *cls);


/**
 * Select a shard to work on.
 *
 * @param cls NULL
 */
static void
run_shard (void *cls);


/**
 * Free data stored in @a au, but not @a au itself (stack allocated).
 *
 * @param au aggregation unit to clean up
 */
static void
cleanup_au (struct AggregationUnit *au)
{
  GNUNET_assert (NULL != au);
  GNUNET_free (au->payto_uri);
  memset (au,
          0,
          sizeof (*au));
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
static enum GNUNET_GenericReturnValue
parse_wirewatch_config (void)
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
  if ( (GNUNET_OK !=
        TALER_config_get_amount (cfg,
                                 "taler",
                                 "CURRENCY_ROUND_UNIT",
                                 &currency_round_unit)) ||
       ( (0 != currency_round_unit.fraction) &&
         (0 != currency_round_unit.value) ) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Need non-zero value in section `TALER' under `CURRENCY_ROUND_UNIT'\n");
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
                                      TALER_EXCHANGEDB_ALO_DEBIT))
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
 * Release lock on shard @a s in the database.
 * On error, terminates this process.
 *
 * @param[in] s shard to free (and memory to release)
 */
static void
release_shard (struct Shard *s)
{
  enum GNUNET_DB_QueryStatus qs;

  qs = db_plugin->release_revolving_shard (
    db_plugin->cls,
    "aggregator",
    s->shard_start,
    s->shard_end);
  GNUNET_free (s);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR != qs);
    GNUNET_break (0);
    GNUNET_SCHEDULER_shutdown ();
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    /* Strange, but let's just continue */
    break;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    /* normal case */
    break;
  }
}


static void
run_aggregation (void *cls)
{
  struct Shard *s = cls;
  struct AggregationUnit au_active;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_Amount trans;
  bool have_transient = true; /* squash compiler warning */

  task = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Checking for ready deposits to aggregate\n");
  /* make sure we have current fees */
  memset (&au_active,
          0,
          sizeof (au_active));
  au_active.execution_time = GNUNET_TIME_timestamp_get ();
  if (GNUNET_OK !=
      db_plugin->start_deferred_wire_out (db_plugin->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to start database transaction!\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    release_shard (s);
    return;
  }
  qs = db_plugin->get_ready_deposit (
    db_plugin->cls,
    s->shard_start,
    s->shard_end,
    kyc_off ? true : false,
    &au_active.merchant_pub,
    &au_active.payto_uri);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    cleanup_au (&au_active);
    db_plugin->rollback (db_plugin->cls);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to begin deposit iteration!\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    release_shard (s);
    return;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    cleanup_au (&au_active);
    db_plugin->rollback (db_plugin->cls);
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                     s);
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    {
      uint64_t counter = s->work_counter;
      struct GNUNET_TIME_Relative duration
        = GNUNET_TIME_absolute_get_duration (s->start_time.abs_time);

      cleanup_au (&au_active);
      db_plugin->rollback (db_plugin->cls);
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Completed shard [%u,%u] after %s with %llu deposits\n",
                  (unsigned int) s->shard_start,
                  (unsigned int) s->shard_end,
                  GNUNET_TIME_relative2s (duration,
                                          true),
                  (unsigned long long) counter);
      release_shard (s);
      if ( (GNUNET_YES == test_mode) &&
           (0 == counter) )
      {
        /* in test mode, shutdown after a shard is done with 0 work */
        GNUNET_SCHEDULER_shutdown ();
        return;
      }
      GNUNET_assert (NULL == task);
      /* If we ended up doing zero work, sleep a bit */
      if (0 == counter)
        task = GNUNET_SCHEDULER_add_delayed (aggregator_idle_sleep_interval,
                                             &run_shard,
                                             NULL);
      else
        task = GNUNET_SCHEDULER_add_now (&run_shard,
                                         NULL);
      return;
    }
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    s->work_counter++;
    /* continued below */
    break;
  }
  au_active.wa = TALER_EXCHANGEDB_find_account_by_payto_uri (
    au_active.payto_uri);
  if (NULL == au_active.wa)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "No exchange account configured for `%s', please fix your setup to continue!\n",
                au_active.payto_uri);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    db_plugin->rollback (db_plugin->cls);
    release_shard (s);
    return;
  }

  {
    struct GNUNET_TIME_Timestamp start_date;
    struct GNUNET_TIME_Timestamp end_date;
    struct TALER_MasterSignatureP master_sig;

    qs = db_plugin->get_wire_fee (db_plugin->cls,
                                  au_active.wa->method,
                                  au_active.execution_time,
                                  &start_date,
                                  &end_date,
                                  &au_active.fees,
                                  &master_sig);
    if (0 >= qs)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Could not get wire fees for %s at %s. Aborting run.\n",
                  au_active.wa->method,
                  GNUNET_TIME_timestamp2s (au_active.execution_time));
      global_ret = EXIT_FAILURE;
      GNUNET_SCHEDULER_shutdown ();
      db_plugin->rollback (db_plugin->cls);
      release_shard (s);
      return;
    }
  }


  /* Now try to find other deposits to aggregate */
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Found ready deposit for %s, aggregating by target %s\n",
              TALER_B2S (&au_active.merchant_pub),
              au_active.payto_uri);
  TALER_payto_hash (au_active.payto_uri,
                    &au_active.h_payto);

  qs = db_plugin->select_aggregation_transient (db_plugin->cls,
                                                &au_active.h_payto,
                                                au_active.wa->section_name,
                                                &au_active.wtid,
                                                &trans);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to lookup transient aggregates!\n");
    cleanup_au (&au_active);
    db_plugin->rollback (db_plugin->cls);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    release_shard (s);
    return;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    /* serializiability issue, try again */
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Serialization issue, trying again later!\n");
    db_plugin->rollback (db_plugin->cls);
    cleanup_au (&au_active);
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                     s);
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                                &au_active.wtid,
                                sizeof (au_active.wtid));
    have_transient = false;
    break;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    have_transient = true;
    break;
  }
  qs = db_plugin->aggregate (db_plugin->cls,
                             &au_active.h_payto,
                             &au_active.merchant_pub,
                             &au_active.wtid,
                             &au_active.total_amount);
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to execute aggregation!\n");
    cleanup_au (&au_active);
    db_plugin->rollback (db_plugin->cls);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    release_shard (s);
    return;
  }
  if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
  {
    /* serializiability issue, try again */
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Serialization issue, trying again later!\n");
    db_plugin->rollback (db_plugin->cls);
    cleanup_au (&au_active);
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                     s);
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Aggregation total is %s.\n",
              TALER_amount2s (&au_active.total_amount));

  /* Subtract wire transfer fee and round to the unit supported by the
     wire transfer method; Check if after rounding down, we still have
     an amount to transfer, and if not mark as 'tiny'. */
  if (have_transient)
    GNUNET_assert (0 <=
                   TALER_amount_add (&au_active.total_amount,
                                     &au_active.total_amount,
                                     &trans));
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Rounding aggregate of %s\n",
              TALER_amount2s (&au_active.total_amount));
  if ( (0 >=
        TALER_amount_subtract (&au_active.final_amount,
                               &au_active.total_amount,
                               &au_active.fees.wire)) ||
       (GNUNET_SYSERR ==
        TALER_amount_round_down (&au_active.final_amount,
                                 &currency_round_unit)) ||
       (TALER_amount_is_zero (&au_active.final_amount)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Aggregate value too low for transfer (%d/%s)\n",
                qs,
                TALER_amount2s (&au_active.final_amount));
    if (have_transient)
      qs = db_plugin->update_aggregation_transient (db_plugin->cls,
                                                    &au_active.h_payto,
                                                    &au_active.wtid,
                                                    &au_active.total_amount);
    else
      qs = db_plugin->create_aggregation_transient (db_plugin->cls,
                                                    &au_active.h_payto,
                                                    au_active.wa->section_name,
                                                    &au_active.wtid,
                                                    &au_active.total_amount);
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Serialization issue, trying again later!\n");
      db_plugin->rollback (db_plugin->cls);
      cleanup_au (&au_active);
      /* start again */
      GNUNET_assert (NULL == task);
      task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                       s);
      return;
    }
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_break (0);
      db_plugin->rollback (db_plugin->cls);
      cleanup_au (&au_active);
      global_ret = EXIT_FAILURE;
      GNUNET_SCHEDULER_shutdown ();
      release_shard (s);
      return;
    }
    /* commit */
    (void) commit_or_warn ();
    cleanup_au (&au_active);

    /* start again */
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                     s);
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Preparing wire transfer of %s to %s\n",
              TALER_amount2s (&au_active.final_amount),
              TALER_B2S (&au_active.merchant_pub));
  {
    void *buf;
    size_t buf_size;

    TALER_BANK_prepare_transfer (au_active.payto_uri,
                                 &au_active.final_amount,
                                 exchange_base_url,
                                 &au_active.wtid,
                                 &buf,
                                 &buf_size);
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Storing %u bytes of wire prepare data\n",
                (unsigned int) buf_size);
    /* Commit our intention to execute the wire transfer! */
    qs = db_plugin->wire_prepare_data_insert (db_plugin->cls,
                                              au_active.wa->method,
                                              buf,
                                              buf_size);
    GNUNET_free (buf);
  }
  /* Commit the WTID data to 'wire_out'  */
  if (qs >= 0)
    qs = db_plugin->store_wire_transfer_out (db_plugin->cls,
                                             au_active.execution_time,
                                             &au_active.wtid,
                                             &au_active.h_payto,
                                             au_active.wa->section_name,
                                             &au_active.final_amount);

  if ( (qs >= 0) &&
       have_transient)
    qs = db_plugin->delete_aggregation_transient (db_plugin->cls,
                                                  &au_active.h_payto,
                                                  &au_active.wtid);
  cleanup_au (&au_active);

  if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Serialization issue for prepared wire data; trying again later!\n");
    db_plugin->rollback (db_plugin->cls);
    /* start again */
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                     s);
    return;
  }
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    GNUNET_break (0);
    db_plugin->rollback (db_plugin->cls);
    /* die hard */
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    release_shard (s);
    return;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Stored wire transfer out instructions\n");

  /* Now we can finally commit the overall transaction, as we are
     again consistent if all of this passes. */
  switch (commit_or_warn ())
  {
  case GNUNET_DB_STATUS_SOFT_ERROR:
    /* try again */
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Commit issue for prepared wire data; trying again later!\n");
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                     s);
    return;
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    db_plugin->rollback (db_plugin->cls); /* just in case */
    release_shard (s);
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Preparation complete, going again\n");
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                     s);
    return;
  default:
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    db_plugin->rollback (db_plugin->cls); /* just in case */
    release_shard (s);
    return;
  }
}


/**
 * Select a shard to work on.
 *
 * @param cls NULL
 */
static void
run_shard (void *cls)
{
  struct Shard *s;
  enum GNUNET_DB_QueryStatus qs;

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
  s = GNUNET_new (struct Shard);
  s->start_time = GNUNET_TIME_timestamp_get ();
  qs = db_plugin->begin_revolving_shard (db_plugin->cls,
                                         "aggregator",
                                         shard_size,
                                         1U + INT32_MAX,
                                         &s->shard_start,
                                         &s->shard_end);
  if (0 >= qs)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    {
      static struct GNUNET_TIME_Relative delay;

      GNUNET_free (s);
      delay = GNUNET_TIME_randomized_backoff (delay,
                                              GNUNET_TIME_UNIT_SECONDS);
      task = GNUNET_SCHEDULER_add_delayed (delay,
                                           &run_shard,
                                           NULL);
      return;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to begin shard (%d)!\n",
                qs);
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting shard [%u:%u]!\n",
              (unsigned int) s->shard_start,
              (unsigned int) s->shard_end);
  task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                   s);
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
  unsigned long long ass;
  (void) cls;
  (void) args;
  (void) cfgfile;

  cfg = c;
  if (GNUNET_OK != parse_wirewatch_config ())
  {
    cfg = NULL;
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
                                             "exchange",
                                             "AGGREGATOR_SHARD_SIZE",
                                             &ass))
  {
    cfg = NULL;
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  if ( (0 == ass) ||
       (ass > INT32_MAX) )
    shard_size = 1U + INT32_MAX;
  else
    shard_size = (uint32_t) ass;
  GNUNET_assert (NULL == task);
  task = GNUNET_SCHEDULER_add_now (&run_shard,
                                   NULL);
  GNUNET_SCHEDULER_add_shutdown (&shutdown_task,
                                 cls);
}


/**
 * The main function of the taler-exchange-aggregator.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, non-zero on error, see #global_ret
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
    GNUNET_GETOPT_option_flag ('y',
                               "kyc-off",
                               "perform wire transfers without KYC checks",
                               &kyc_off),
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
    "taler-exchange-aggregator",
    gettext_noop (
      "background process that aggregates and executes wire transfers"),
    options,
    &run, NULL);
  GNUNET_free_nz ((void *) argv);
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  return global_ret;
}


/* end of taler-exchange-aggregator.c */
