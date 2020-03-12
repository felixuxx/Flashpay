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
 * @file taler-exchange-aggregator.c
 * @brief Process that aggregates outgoing transactions and executes them
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
   * Total amount to be transferred, before subtraction of @e wire_fee and rounding down.
   */
  struct TALER_Amount total_amount;

  /**
   * Final amount to be transferred (after fee and rounding down).
   */
  struct TALER_Amount final_amount;

  /**
   * Wire fee we charge for @e wp at @e execution_time.
   */
  struct TALER_Amount wire_fee;

  /**
   * Hash of @e wire.
   */
  struct GNUNET_HashCode h_wire;

  /**
   * Wire transfer identifier we use.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * Row ID of the transaction that started it all.
   */
  unsigned long long row_id;

  /**
   * The current time (which triggered the aggregation and
   * defines the wire fee).
   */
  struct GNUNET_TIME_Absolute execution_time;

  /**
   * Wire details of the merchant.
   */
  json_t *wire;

  /**
   * Exchange wire account to be used for the preparation and
   * eventual execution of the aggregate wire transfer.
   */
  struct TALER_EXCHANGEDB_WireAccount *wa;

  /**
   * Database session for all of our transactions.
   */
  struct TALER_EXCHANGEDB_Session *session;

  /**
   * Wire preparation handle.
   */
  struct TALER_BANK_PrepareHandle *ph;

  /**
   * Array of #TALER_EXCHANGEDB_MATCHING_DEPOSITS_LIMIT row_ids from the
   * aggregation.
   */
  unsigned long long *additional_rows;

  /**
   * Offset specifying how many @e additional_rows are in use.
   */
  unsigned int rows_offset;

  /**
   * Set to #GNUNET_YES if we have to abort due to failure.
   */
  int failed;

  /**
   * Set to #GNUNET_YES if we encountered a refund during #refund_by_coin_cb.
   * Used to wave the deposit fee.
   */
  int have_refund;
};


/**
 * Which currency is used by this exchange?
 */
static char *exchange_currency_string;

/**
 * What is the smallest unit we support for wire transfers?
 * We will need to round down to a multiple of this amount.
 */
static struct TALER_Amount currency_round_unit;

/**
 * What is the base URL of this exchange?  Used in the
 * wire transfer subjects to that merchants and governments
 * can ask for the list of aggregated deposits.
 */
static char *exchange_base_url;

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
 * Value to return from main(). #GNUNET_OK on success, #GNUNET_SYSERR
 * on serious errors.
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
 * @param cls NULL
 */
static void
run_aggregation (void *cls);


/**
 * Free data stored in @a au, but not @a au itself (stack allocated).
 *
 * @param au aggreation unit to clean up
 */
static void
cleanup_au (struct AggregationUnit *au)
{
  GNUNET_assert (NULL != au);
  GNUNET_free_non_null (au->additional_rows);
  if (NULL != au->wire)
    json_decref (au->wire);
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
static int
parse_wirewatch_config ()
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
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "taler",
                                             "CURRENCY",
                                             &exchange_currency_string))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler",
                               "CURRENCY");
    return GNUNET_SYSERR;
  }
  if (strlen (exchange_currency_string) >= TALER_CURRENCY_LEN)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Currency `%s' longer than the allowed limit of %u characters.",
                exchange_currency_string,
                (unsigned int) TALER_CURRENCY_LEN);
    return GNUNET_SYSERR;
  }

  if ( (GNUNET_OK !=
        TALER_config_get_amount (cfg,
                                 "taler",
                                 "CURRENCY_ROUND_UNIT",
                                 &currency_round_unit)) ||
       (0 != strcasecmp (exchange_currency_string,
                         currency_round_unit.currency)) ||
       ( (0 != currency_round_unit.fraction) &&
         (0 != currency_round_unit.value) ) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid value specified in section `TALER' under `CURRENCY_ROUND_UNIT'\n");
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
 * Callback invoked with information about refunds applicable
 * to a particular coin.  Subtract refunded amount(s) from
 * the aggregation unit's total amount.
 *
 * @param cls closure with a `struct AggregationUnit *`
 * @param amount_with_fee what was the refunded amount with the fee
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
refund_by_coin_cb (void *cls,
                   const struct TALER_Amount *amount_with_fee)
{
  struct AggregationUnit *aux = cls;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Aggregator subtracts applicable refund of amount %s\n",
              TALER_amount2s (amount_with_fee));
  aux->have_refund = GNUNET_YES;
  if (GNUNET_OK !=
      TALER_amount_subtract (&aux->total_amount,
                             &aux->total_amount,
                             amount_with_fee))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Function called with details about deposits that have been made,
 * with the goal of executing the corresponding wire transaction.
 *
 * @param cls a `struct AggregationUnit`
 * @param row_id identifies database entry
 * @param merchant_pub public key of the merchant
 * @param coin_pub public key of the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param deposit_fee amount the exchange gets to keep as transaction fees
 * @param h_contract_terms hash of the proposal data known to merchant and customer
 * @param wire_deadline by which the merchant adviced that he would like the
 *        wire transfer to be executed
 * @param wire wire details for the merchant
 * @return transaction status code,  #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT to continue to iterate
 */
static enum GNUNET_DB_QueryStatus
deposit_cb (void *cls,
            uint64_t row_id,
            const struct TALER_MerchantPublicKeyP *merchant_pub,
            const struct TALER_CoinSpendPublicKeyP *coin_pub,
            const struct TALER_Amount *amount_with_fee,
            const struct TALER_Amount *deposit_fee,
            const struct GNUNET_HashCode *h_contract_terms,
            struct GNUNET_TIME_Absolute wire_deadline,
            const json_t *wire)
{
  struct AggregationUnit *au = cls;
  enum GNUNET_DB_QueryStatus qs;

  (void) cls;
  /* NOTE: potential optimization: use custom SQL API to not
     fetch this one: */
  (void) wire_deadline; /* already checked by SQL query */
  au->merchant_pub = *merchant_pub;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Aggregator processing payment %s with amount %s\n",
              TALER_B2S (coin_pub),
              TALER_amount2s (amount_with_fee));
  au->row_id = row_id;
  au->total_amount = *amount_with_fee;
  au->have_refund = GNUNET_NO;
  qs = db_plugin->select_refunds_by_coin (db_plugin->cls,
                                          au->session,
                                          coin_pub,
                                          &au->merchant_pub,
                                          h_contract_terms,
                                          &refund_by_coin_cb,
                                          au);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_NO == au->have_refund)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Non-refunded transaction, subtracting deposit fee %s\n",
                TALER_amount2s (deposit_fee));
    if (GNUNET_SYSERR ==
        TALER_amount_subtract (&au->total_amount,
                               amount_with_fee,
                               deposit_fee))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Fatally malformed record at row %llu over %s\n",
                  (unsigned long long) row_id,
                  TALER_amount2s (amount_with_fee));
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }

  GNUNET_assert (NULL == au->wire);
  if (NULL == (au->wire = json_incref ((json_t *) wire)))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_OK !=
      TALER_JSON_merchant_wire_signature_hash (wire,
                                               &au->h_wire))
  {
    GNUNET_break (0);
    json_decref (au->wire);
    au->wire = NULL;
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                              &au->wtid,
                              sizeof (au->wtid));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting aggregation under H(WTID)=%s, starting amount %s at %llu\n",
              TALER_B2S (&au->wtid),
              TALER_amount2s (amount_with_fee),
              (unsigned long long) row_id);
  {
    char *url;

    url = TALER_JSON_wire_to_payto (au->wire);
    au->wa = TALER_EXCHANGEDB_find_account_by_payto_uri (url);
    GNUNET_free (url);
  }
  if (NULL == au->wa)
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  /* make sure we have current fees */
  au->execution_time = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&au->execution_time);
  {
    struct TALER_EXCHANGEDB_AggregateFees *af;

    af = TALER_EXCHANGEDB_update_fees (cfg,
                                       db_plugin,
                                       au->wa,
                                       au->execution_time,
                                       au->session);
    if (NULL == af)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Could not get or persist wire fees. Aborting run.\n");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    au->wire_fee = af->wire_fee;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Aggregator starts aggregation for deposit %llu to %s with wire fee %s\n",
              (unsigned long long) row_id,
              TALER_B2S (&au->wtid),
              TALER_amount2s (&au->wire_fee));
  qs = db_plugin->insert_aggregation_tracking (db_plugin->cls,
                                               au->session,
                                               &au->wtid,
                                               row_id);
  if (qs <= 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Aggregator marks deposit %llu as done\n",
              (unsigned long long) row_id);
  qs = db_plugin->mark_deposit_done (db_plugin->cls,
                                     au->session,
                                     row_id);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  return qs;
}


/**
 * Function called with details about another deposit we
 * can aggregate into an existing aggregation unit.
 *
 * @param cls a `struct AggregationUnit`
 * @param row_id identifies database entry
 * @param merchant_pub public key of the merchant
 * @param coin_pub public key of the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param deposit_fee amount the exchange gets to keep as transaction fees
 * @param h_contract_terms hash of the proposal data known to merchant and customer
 * @param wire_deadline by which the merchant adviced that he would like the
 *        wire transfer to be executed
 * @param wire wire details for the merchant
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
aggregate_cb (void *cls,
              uint64_t row_id,
              const struct TALER_MerchantPublicKeyP *merchant_pub,
              const struct TALER_CoinSpendPublicKeyP *coin_pub,
              const struct TALER_Amount *amount_with_fee,
              const struct TALER_Amount *deposit_fee,
              const struct GNUNET_HashCode *h_contract_terms,
              struct GNUNET_TIME_Absolute wire_deadline,
              const json_t *wire)
{
  struct AggregationUnit *au = cls;
  struct TALER_Amount delta;
  enum GNUNET_DB_QueryStatus qs;

  /* NOTE: potential optimization: use custom SQL API to not
     fetch these: */
  (void) wire_deadline; /* checked by SQL */
  (void) wire; /* must match */
  GNUNET_break (0 == GNUNET_memcmp (&au->merchant_pub,
                                    merchant_pub));

  if (au->rows_offset >= TALER_EXCHANGEDB_MATCHING_DEPOSITS_LIMIT)
  {
    /* Bug: we asked for at most #TALER_EXCHANGEDB_MATCHING_DEPOSITS_LIMIT results! */
    GNUNET_break (0);
    /* Skip this one, but keep going with the overall transaction */
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }

  /* compute contribution of this coin after fees */
  /* add to total */
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Adding transaction amount %s from row %llu to aggregation\n",
              TALER_amount2s (amount_with_fee),
              (unsigned long long) row_id);
  if (GNUNET_OK !=
      TALER_amount_add (&au->total_amount,
                        &au->total_amount,
                        amount_with_fee))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Overflow or currency incompatibility during aggregation at %llu\n",
                (unsigned long long) row_id);
    /* Skip this one, but keep going! */
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }
  au->have_refund = GNUNET_NO;
  qs = db_plugin->select_refunds_by_coin (db_plugin->cls,
                                          au->session,
                                          coin_pub,
                                          &au->merchant_pub,
                                          h_contract_terms,
                                          &refund_by_coin_cb,
                                          au);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_NO == au->have_refund)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Subtracting deposit fee %s for non-refunded coin\n",
                TALER_amount2s (deposit_fee));
    if (GNUNET_SYSERR ==
        TALER_amount_subtract (&delta,
                               &au->total_amount,
                               deposit_fee))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Fatally malformed record at %llu over amount %s\n",
                  (unsigned long long) row_id,
                  TALER_amount2s (&au->total_amount));
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    au->total_amount = delta;
  }

  if (NULL == au->additional_rows)
    au->additional_rows = GNUNET_new_array (
      TALER_EXCHANGEDB_MATCHING_DEPOSITS_LIMIT,
      unsigned long long);
  /* "append" to our list of rows */
  au->additional_rows[au->rows_offset++] = row_id;
  /* insert into aggregation tracking table */
  qs = db_plugin->insert_aggregation_tracking (db_plugin->cls,
                                               au->session,
                                               &au->wtid,
                                               row_id);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  qs = db_plugin->mark_deposit_done (db_plugin->cls,
                                     au->session,
                                     row_id);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Aggregator marked deposit %llu over %s as DONE\n",
              (unsigned long long) row_id,
              TALER_amount2s (&delta));
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
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
 * Main work function that queries the DB and aggregates transactions
 * into larger wire transfers.
 *
 * @param cls NULL
 */
static void
run_aggregation (void *cls)
{
  struct AggregationUnit au_active;
  struct TALER_EXCHANGEDB_Session *session;
  enum GNUNET_DB_QueryStatus qs;
  const struct GNUNET_SCHEDULER_TaskContext *tc;
  void *buf;
  size_t buf_size;

  (void) cls;
  task = NULL;
  tc = GNUNET_SCHEDULER_get_task_context ();
  if (0 != (tc->reason & GNUNET_SCHEDULER_REASON_SHUTDOWN))
    return;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Checking for ready deposits to aggregate\n");
  if (NULL == (session = db_plugin->get_session (db_plugin->cls)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain database session!\n");
    global_ret = GNUNET_SYSERR;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_OK !=
      db_plugin->start_deferred_wire_out (db_plugin->cls,
                                          session))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to start database transaction!\n");
    global_ret = GNUNET_SYSERR;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  memset (&au_active,
          0,
          sizeof (au_active));
  au_active.session = session;
  qs = db_plugin->get_ready_deposit (db_plugin->cls,
                                     session,
                                     &deposit_cb,
                                     &au_active);
  if (0 >= qs)
  {
    cleanup_au (&au_active);
    db_plugin->rollback (db_plugin->cls,
                         session);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to execute deposit iteration!\n");
      global_ret = GNUNET_SYSERR;
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    {
      /* should re-try immediately */
      GNUNET_assert (NULL == task);
      task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                       NULL);
      return;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "No more ready deposits, going to sleep\n");
    if (GNUNET_YES == test_mode)
    {
      /* in test mode, shutdown if we end up being idle */
      GNUNET_SCHEDULER_shutdown ();
    }
    else
    {
      /* nothing to do, sleep for a minute and try again */
      GNUNET_assert (NULL == task);
      task = GNUNET_SCHEDULER_add_delayed (aggregator_idle_sleep_interval,
                                           &run_aggregation,
                                           NULL);
    }
    return;
  }

  /* Now try to find other deposits to aggregate */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Found ready deposit for %s, aggregating\n",
              TALER_B2S (&au_active.merchant_pub));
  qs = db_plugin->iterate_matching_deposits (db_plugin->cls,
                                             session,
                                             &au_active.h_wire,
                                             &au_active.merchant_pub,
                                             &aggregate_cb,
                                             &au_active,
                                             TALER_EXCHANGEDB_MATCHING_DEPOSITS_LIMIT);
  if ( (GNUNET_DB_STATUS_HARD_ERROR == qs) ||
       (GNUNET_YES == au_active.failed) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to execute deposit iteration!\n");
    cleanup_au (&au_active);
    db_plugin->rollback (db_plugin->cls,
                         session);
    global_ret = GNUNET_SYSERR;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
  {
    /* serializiability issue, try again */
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Serialization issue, trying again later!\n");
    db_plugin->rollback (db_plugin->cls,
                         session);
    cleanup_au (&au_active);
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                     NULL);
    return;
  }

  /* Subtract wire transfer fee and round to the unit supported by the
     wire transfer method; Check if after rounding down, we still have
     an amount to transfer, and if not mark as 'tiny'. */
  if ( (GNUNET_OK !=
        TALER_amount_subtract (&au_active.final_amount,
                               &au_active.total_amount,
                               &au_active.wire_fee)) ||
       (GNUNET_SYSERR ==
        TALER_amount_round_down (&au_active.final_amount,
                                 &currency_round_unit)) ||
       ( (0 == au_active.final_amount.value) &&
         (0 == au_active.final_amount.fraction) ) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Aggregate value too low for transfer (%d/%s)\n",
                qs,
                TALER_amount2s (&au_active.final_amount));
    /* Rollback ongoing transaction, as we will not use the respective
       WTID and thus need to remove the tracking data */
    db_plugin->rollback (db_plugin->cls,
                         session);

    /* There were results, just the value was too low.  Start another
       transaction to mark all* of the selected deposits as minor! */
    if (GNUNET_OK !=
        db_plugin->start (db_plugin->cls,
                          session,
                          "aggregator mark tiny transactions"))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to start database transaction!\n");
      global_ret = GNUNET_SYSERR;
      cleanup_au (&au_active);
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
    /* Mark transactions by row_id as minor */
    qs = db_plugin->mark_deposit_tiny (db_plugin->cls,
                                       session,
                                       au_active.row_id);
    if (0 <= qs)
    {
      for (unsigned int i = 0; i<au_active.rows_offset; i++)
      {
        qs = db_plugin->mark_deposit_tiny (db_plugin->cls,
                                           session,
                                           au_active.additional_rows[i]);
        if (0 > qs)
          break;
      }
    }
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Serialization issue, trying again later!\n");
      db_plugin->rollback (db_plugin->cls,
                           session);
      cleanup_au (&au_active);
      /* start again */
      GNUNET_assert (NULL == task);
      task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                       NULL);
      return;
    }
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      db_plugin->rollback (db_plugin->cls,
                           session);
      cleanup_au (&au_active);
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
    /* commit */
    (void) commit_or_warn (session);
    cleanup_au (&au_active);

    /* start again */
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                     NULL);
    return;
  }
  {
    char *amount_s;

    amount_s = TALER_amount_to_string (&au_active.final_amount);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Preparing wire transfer of %s to %s\n",
                amount_s,
                TALER_B2S (&au_active.merchant_pub));
    GNUNET_free (amount_s);
  }
  {
    char *url;

    url = TALER_JSON_wire_to_payto (au_active.wire);
    TALER_BANK_prepare_transfer (url,
                                 &au_active.final_amount,
                                 exchange_base_url,
                                 &au_active.wtid,
                                 &buf,
                                 &buf_size);
    GNUNET_free (url);
  }
  GNUNET_free_non_null (au_active.additional_rows);
  au_active.additional_rows = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Storing %u bytes of wire prepare data\n",
              (unsigned int) buf_size);
  /* Commit our intention to execute the wire transfer! */
  qs = db_plugin->wire_prepare_data_insert (db_plugin->cls,
                                            session,
                                            au_active.wa->method,
                                            buf,
                                            buf_size);
  GNUNET_free (buf);
  /* Commit the WTID data to 'wire_out' to finally satisfy aggregation
     table constraints */
  if (qs >= 0)
    qs = db_plugin->store_wire_transfer_out (db_plugin->cls,
                                             session,
                                             au_active.execution_time,
                                             &au_active.wtid,
                                             au_active.wire,
                                             au_active.wa->section_name,
                                             &au_active.final_amount);
  cleanup_au (&au_active);

  if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Serialization issue for prepared wire data; trying again later!\n");
    db_plugin->rollback (db_plugin->cls,
                         session);
    /* start again */
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                     NULL);
    return;
  }
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    GNUNET_break (0);
    db_plugin->rollback (db_plugin->cls,
                         session);
    /* die hard */
    global_ret = GNUNET_SYSERR;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Stored wire transfer out instructions\n");

  /* Now we can finally commit the overall transaction, as we are
     again consistent if all of this passes. */
  switch (commit_or_warn (session))
  {
  case GNUNET_DB_STATUS_SOFT_ERROR:
    /* try again */
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Commit issue for prepared wire data; trying again later!\n");
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                     NULL);
    return;
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    global_ret = GNUNET_SYSERR;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Preparation complete, going again\n");
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                     NULL);
    return;
  default:
    GNUNET_break (0);
    global_ret = GNUNET_SYSERR;
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
  if (GNUNET_OK != parse_wirewatch_config ())
  {
    cfg = NULL;
    global_ret = 1;
    return;
  }
  GNUNET_assert (NULL == task);
  task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                   NULL);
  GNUNET_SCHEDULER_add_shutdown (&shutdown_task,
                                 cls);
}


/**
 * The main function of the taler-exchange-aggregator.
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

  if (GNUNET_OK != GNUNET_STRINGS_get_utf8_args (argc, argv,
                                                 &argc, &argv))
    return 2;
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc, argv,
                          "taler-exchange-aggregator",
                          gettext_noop (
                            "background process that aggregates and executes wire transfers"),
                          options,
                          &run, NULL))
  {
    GNUNET_free ((void *) argv);
    return 1;
  }
  GNUNET_free ((void *) argv);
  return global_ret;
}


/* end of taler-exchange-aggregator.c */
