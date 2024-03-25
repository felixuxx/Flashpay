/*
  This file is part of TALER
  Copyright (C) 2017-2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file auditor/taler-helper-auditor-wire.c
 * @brief audits that wire transfers match those from an exchange database.
 * @author Christian Grothoff
 *
 * - First, this auditor verifies that 'reserves_in' actually matches
 *   the incoming wire transfers from the bank.
 * - Second, we check that the outgoing wire transfers match those
 *   given in the 'wire_out' and 'reserve_closures' tables
 * - Finally, we check that all wire transfers that should have been made,
 *   were actually made
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_auditordb_plugin.h"
#include "taler_exchangedb_lib.h"
#include "taler_json_lib.h"
#include "taler_bank_service.h"
#include "taler_signatures.h"
#include "report-lib.h"


/**
 * How much time do we allow the aggregator to lag behind?  If
 * wire transfers should have been made more than #GRACE_PERIOD
 * before, we issue warnings.
 */
#define GRACE_PERIOD GNUNET_TIME_UNIT_HOURS

/**
 * How much do we allow the bank and the exchange to disagree about
 * timestamps? Should be sufficiently large to avoid bogus reports from deltas
 * created by imperfect clock synchronization and network delay.
 */
#define TIME_TOLERANCE GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MINUTES, \
                                                      15)


/**
 * Run in test mode. Exit when idle instead of
 * going to sleep and waiting for more work.
 *
 * FIXME: not yet implemented!
 */
static int test_mode;

struct TALER_AUDITORDB_WireAccountProgressPoint
{
  uint64_t last_reserve_in_serial_id;
  uint64_t last_wire_out_serial_id;
};

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
   * Account details.
   */
  const struct TALER_EXCHANGEDB_AccountInfo *ai;

  /**
   * Active wire request for the transaction history.
   */
  struct TALER_BANK_CreditHistoryHandle *chh;

  /**
   * Active wire request for the transaction history.
   */
  struct TALER_BANK_DebitHistoryHandle *dhh;

  /**
   * Progress point for this account.
   */
  struct TALER_AUDITORDB_WireAccountProgressPoint pp;

  /**
   * Initial progress point for this account.
   */
  struct TALER_AUDITORDB_WireAccountProgressPoint start_pp;

  /**
   * Where we are in the inbound transaction history.
   */
  uint64_t wire_off_in;

  /**
   * Where we are in the outbound transaction history.
   */
  uint64_t wire_off_out;

  /**
   * Label under which we store our pp's reserve_in_serial_id.
   */
  char *label_reserve_in_serial_id;

  /**
   * Label under which we store our pp's reserve_in_serial_id.
   */
  char *label_wire_out_serial_id;

  /**
   * Label under which we store our wire_off_in.
   */
  char *label_wire_off_in;

  /**
   * Label under which we store our wire_off_out.
   */
  char *label_wire_off_out;

  /**
   * Return value when we got this account's progress point.
   */
  enum GNUNET_DB_QueryStatus qsx;
};


/**
 * Information we track for a reserve being closed.
 */
struct ReserveClosure
{
  /**
   * Row in the reserves_closed table for this action.
   */
  uint64_t rowid;

  /**
   * When was the reserve closed?
   */
  struct GNUNET_TIME_Timestamp execution_date;

  /**
   * Amount transferred (amount remaining minus fee).
   */
  struct TALER_Amount amount;

  /**
   * Target account where the money was sent.
   */
  char *receiver_account;

  /**
   * Wire transfer subject used.
   */
  struct TALER_WireTransferIdentifierRawP wtid;
};


/**
 * Map from H(wtid,receiver_account) to `struct ReserveClosure` entries.
 */
static struct GNUNET_CONTAINER_MultiHashMap *reserve_closures;

/**
 * Return value from main().
 */
static int global_ret;

/**
 * Map with information about incoming wire transfers.
 * Maps hashes of the wire offsets to `struct ReserveInInfo`s.
 */
static struct GNUNET_CONTAINER_MultiHashMap *in_map;

/**
 * Map with information about outgoing wire transfers.
 * Maps hashes of the wire subjects (in binary encoding)
 * to `struct ReserveOutInfo`s.
 */
static struct GNUNET_CONTAINER_MultiHashMap *out_map;

/**
 * Head of list of wire accounts we still need to look at.
 */
static struct WireAccount *wa_head;

/**
 * Tail of list of wire accounts we still need to look at.
 */
static struct WireAccount *wa_tail;

/**
 * Query status for the incremental processing status in the auditordb.
 * Return value from our call to the "get_wire_auditor_progress" function.
 */
static enum GNUNET_DB_QueryStatus qsx_gwap;

/**
 * Last reserve_in / wire_out serial IDs seen.
 */
static TALER_ARL_DEF_PP (wire_reserve_close_id);
static TALER_ARL_DEF_PP (wire_batch_deposit_id);
static TALER_ARL_DEF_PP (wire_aggregation_id);

/**
 * Array of reports about row inconsistencies in wire_out table.
 */
static json_t *report_wire_out_inconsistencies;

/**
 * Array of reports about row inconsistencies in reserves_in table.
 */
static json_t *report_reserve_in_inconsistencies;

/**
 * Array of reports about wrong bank account being recorded for
 * incoming wire transfers.
 */
static json_t *report_misattribution_in_inconsistencies;

/**
 * Array of reports about row inconsistencies.
 */
static json_t *report_row_inconsistencies;

/**
 * Array of reports about inconsistencies in the database about
 * the incoming wire transfers (exchange is not exactly to blame).
 */
static json_t *report_wire_format_inconsistencies;

/**
 * Array of reports about minor row inconsistencies.
 */
static json_t *report_row_minor_inconsistencies;

/**
 * Array of reports about lagging transactions from deposits.
 */
static json_t *report_lags;

/**
 * Array of reports about lagging transactions from deposits due to missing KYC.
 */
static json_t *report_kyc_lags;

/**
 * Array of reports about lagging transactions from deposits due to pending or frozen AML decisions.
 */
static json_t *report_aml_lags;

/**
 * Array of reports about lagging transactions from reserve closures.
 */
static json_t *report_closure_lags;

/**
 * Array of per-account progress data.
 */
static json_t *report_account_progress;

/**
 * Amount that is considered "tiny"
 */
static struct TALER_Amount tiny_amount;

/**
 * Total amount that was transferred too much from the exchange.
 */
static struct TALER_Amount total_bad_amount_out_plus;

/**
 * Total amount that was transferred too little from the exchange.
 */
static struct TALER_Amount total_bad_amount_out_minus;

/**
 * Total amount that was transferred too much to the exchange.
 */
static struct TALER_Amount total_bad_amount_in_plus;

/**
 * Total amount that was transferred too little to the exchange.
 */
static struct TALER_Amount total_bad_amount_in_minus;

/**
 * Total amount where the exchange has the wrong sender account
 * for incoming funds and may thus wire funds to the wrong
 * destination when closing the reserve.
 */
static struct TALER_Amount total_misattribution_in;

/**
 * Total amount which the exchange did not transfer in time.
 */
static struct TALER_Amount total_amount_lag;

/**
 * Total amount of reserve closures which the exchange did not transfer in time.
 */
static struct TALER_Amount total_closure_amount_lag;

/**
 * Total amount affected by wire format trouble.s
 */
static struct TALER_Amount total_wire_format_amount;

/**
 * Total amount credited to exchange accounts.
 */
static struct TALER_Amount total_wire_in;

/**
 * Total amount debited to exchange accounts.
 */
static struct TALER_Amount total_wire_out;

/**
 * Total amount of profits drained.
 */
static TALER_ARL_DEF_AB (total_drained);

/**
 * Final balance at the end of this iteration.
 */
static TALER_ARL_DEF_AB (final_balance);

/**
 * Starting balance at the beginning of this iteration.
 */
static struct TALER_Amount start_balance;

/**
 * True if #start_balance was initialized.
 */
static bool had_start_balance;

/**
 * Amount of zero in our currency.
 */
static struct TALER_Amount zero;

/**
 * Handle to the context for interacting with the bank.
 */
static struct GNUNET_CURL_Context *ctx;

/**
 * Scheduler context for running the @e ctx.
 */
static struct GNUNET_CURL_RescheduleContext *rc;

/**
 * Should we run checks that only work for exchange-internal audits?
 */
static int internal_checks;

/**
 * Should we ignore if the bank does not know our bank
 * account?
 */
static int ignore_account_404;

/* *****************************   Shutdown   **************************** */

/**
 * Entry in map with wire information we expect to obtain from the
 * bank later.
 */
struct ReserveInInfo
{

  /**
   * Hash of expected row offset.
   */
  struct GNUNET_HashCode row_off_hash;

  /**
   * Expected details about the wire transfer.
   * The member "account_url" is to be allocated
   * at the end of this struct!
   */
  struct TALER_BANK_CreditDetails details;

  /**
   * RowID in reserves_in table.
   */
  uint64_t rowid;

};


/**
 * Entry in map with wire information we expect to obtain from the
 * #TALER_ARL_edb later.
 */
struct ReserveOutInfo
{

  /**
   * Hash of the wire transfer subject.
   */
  struct GNUNET_HashCode subject_hash;

  /**
   * Expected details about the wire transfer.
   */
  struct TALER_BANK_DebitDetails details;

};


/**
 * Free entry in #in_map.
 *
 * @param cls NULL
 * @param key unused key
 * @param value the `struct ReserveInInfo` to free
 * @return #GNUNET_OK
 */
static enum GNUNET_GenericReturnValue
free_rii (void *cls,
          const struct GNUNET_HashCode *key,
          void *value)
{
  struct ReserveInInfo *rii = value;

  (void) cls;
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CONTAINER_multihashmap_remove (in_map,
                                                       key,
                                                       rii));
  GNUNET_free (rii);
  return GNUNET_OK;
}


/**
 * Free entry in #out_map.
 *
 * @param cls NULL
 * @param key unused key
 * @param value the `struct ReserveOutInfo` to free
 * @return #GNUNET_OK
 */
static enum GNUNET_GenericReturnValue
free_roi (void *cls,
          const struct GNUNET_HashCode *key,
          void *value)
{
  struct ReserveOutInfo *roi = value;

  (void) cls;
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CONTAINER_multihashmap_remove (out_map,
                                                       key,
                                                       roi));
  GNUNET_free (roi);
  return GNUNET_OK;
}


/**
 * Free entry in #reserve_closures.
 *
 * @param cls NULL
 * @param key unused key
 * @param value the `struct ReserveClosure` to free
 * @return #GNUNET_OK
 */
static enum GNUNET_GenericReturnValue
free_rc (void *cls,
         const struct GNUNET_HashCode *key,
         void *value)
{
  struct ReserveClosure *rc = value;

  (void) cls;
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CONTAINER_multihashmap_remove (reserve_closures,
                                                       key,
                                                       rc));
  GNUNET_free (rc->receiver_account);
  GNUNET_free (rc);
  return GNUNET_OK;
}


/**
 * Task run on shutdown.
 *
 * @param cls NULL
 */
static void
do_shutdown (void *cls)
{
  struct WireAccount *wa;

  (void) cls;
  if (NULL != report_row_inconsistencies)
  {
    GNUNET_assert (NULL != report_row_minor_inconsistencies);
    TALER_ARL_done (
      GNUNET_JSON_PACK (
        /* Tested in test-auditor.sh #11, #15, #20 */
        GNUNET_JSON_pack_array_steal ("wire_out_amount_inconsistencies",
                                      report_wire_out_inconsistencies),
        TALER_JSON_pack_amount ("total_wire_out_delta_plus",
                                &total_bad_amount_out_plus),
        /* Tested in test-auditor.sh #11, #15, #19 */
        TALER_JSON_pack_amount ("total_wire_out_delta_minus",
                                &total_bad_amount_out_minus),
        /* Tested in test-auditor.sh #2 */
        GNUNET_JSON_pack_array_steal ("reserve_in_amount_inconsistencies",
                                      report_reserve_in_inconsistencies),
        /* Tested in test-auditor.sh #2 */
        TALER_JSON_pack_amount ("total_wire_in_delta_plus",
                                &total_bad_amount_in_plus),
        /* Tested in test-auditor.sh #3 */
        TALER_JSON_pack_amount ("total_wire_in_delta_minus",
                                &total_bad_amount_in_minus),
        /* Tested in test-auditor.sh #9 */
        GNUNET_JSON_pack_array_steal ("misattribution_in_inconsistencies",
                                      report_misattribution_in_inconsistencies),
        /* Tested in test-auditor.sh #9 */
        TALER_JSON_pack_amount ("total_misattribution_in",
                                &total_misattribution_in),
        GNUNET_JSON_pack_array_steal ("row_inconsistencies",
                                      report_row_inconsistencies),
        /* Tested in test-auditor.sh #10/#17 */
        GNUNET_JSON_pack_array_steal ("row_minor_inconsistencies",
                                      report_row_minor_inconsistencies),
        /* Tested in test-auditor.sh #19 */
        TALER_JSON_pack_amount ("total_wire_format_amount",
                                &total_wire_format_amount),
        /* Tested in test-auditor.sh #19 */
        GNUNET_JSON_pack_array_steal ("wire_format_inconsistencies",
                                      report_wire_format_inconsistencies),
        TALER_JSON_pack_amount ("total_wire_in",
                                &total_wire_in),
        TALER_JSON_pack_amount ("total_wire_out",
                                &total_wire_out),
        TALER_JSON_pack_amount ("total_drained",
                                &TALER_ARL_USE_AB (total_drained)),
        TALER_JSON_pack_amount ("final_balance",
                                &TALER_ARL_USE_AB (final_balance)),
        /* Tested in test-auditor.sh #1 */
        TALER_JSON_pack_amount ("total_amount_lag",
                                &total_amount_lag),
        /* Tested in test-auditor.sh #1 */
        GNUNET_JSON_pack_array_steal ("lag_details",
                                      report_lags),
        GNUNET_JSON_pack_array_steal ("lag_aml_details",
                                      report_aml_lags),
        GNUNET_JSON_pack_array_steal ("lag_kyc_details",
                                      report_kyc_lags),
        /* Tested in test-auditor.sh #22 */
        TALER_JSON_pack_amount ("total_closure_amount_lag",
                                &total_closure_amount_lag),
        /* Tested in test-auditor.sh #22 */
        GNUNET_JSON_pack_array_steal ("reserve_lag_details",
                                      report_closure_lags),
        TALER_JSON_pack_time_abs_human ("wire_auditor_start_time",
                                        start_time),
        TALER_JSON_pack_time_abs_human ("wire_auditor_end_time",
                                        GNUNET_TIME_absolute_get ()),
        GNUNET_JSON_pack_uint64 ("start_pp_reserve_close_id",
                                 0 /* no longer supported */),
        GNUNET_JSON_pack_uint64 ("end_pp_reserve_close_id",
                                 TALER_ARL_USE_PP (wire_reserve_close_id)),
        GNUNET_JSON_pack_uint64 ("start_pp_last_batch_deposit_id",
                                 0 /* no longer supported */),
        GNUNET_JSON_pack_uint64 ("end_pp_last_batch_deposit_id",
                                 TALER_ARL_USE_PP (wire_batch_deposit_id)),
        GNUNET_JSON_pack_uint64 ("start_pp_last_aggregation_serial_id",
                                 0 /* no longer supported */),
        GNUNET_JSON_pack_uint64 ("end_pp_last_aggregation_serial_id",
                                 TALER_ARL_USE_PP (wire_aggregation_id)),
        GNUNET_JSON_pack_array_steal ("account_progress",
                                      report_account_progress)));
    report_wire_out_inconsistencies = NULL;
    report_reserve_in_inconsistencies = NULL;
    report_row_inconsistencies = NULL;
    report_row_minor_inconsistencies = NULL;
    report_misattribution_in_inconsistencies = NULL;
    report_lags = NULL;
    report_kyc_lags = NULL;
    report_aml_lags = NULL;
    report_closure_lags = NULL;
    report_account_progress = NULL;
    report_wire_format_inconsistencies = NULL;
  }
  else
  {
    TALER_ARL_done (NULL);
  }
  if (NULL != reserve_closures)
  {
    GNUNET_CONTAINER_multihashmap_iterate (reserve_closures,
                                           &free_rc,
                                           NULL);
    GNUNET_CONTAINER_multihashmap_destroy (reserve_closures);
    reserve_closures = NULL;
  }
  if (NULL != in_map)
  {
    GNUNET_CONTAINER_multihashmap_iterate (in_map,
                                           &free_rii,
                                           NULL);
    GNUNET_CONTAINER_multihashmap_destroy (in_map);
    in_map = NULL;
  }
  if (NULL != out_map)
  {
    GNUNET_CONTAINER_multihashmap_iterate (out_map,
                                           &free_roi,
                                           NULL);
    GNUNET_CONTAINER_multihashmap_destroy (out_map);
    out_map = NULL;
  }
  while (NULL != (wa = wa_head))
  {
    if (NULL != wa->dhh)
    {
      TALER_BANK_debit_history_cancel (wa->dhh);
      wa->dhh = NULL;
    }
    if (NULL != wa->chh)
    {
      TALER_BANK_credit_history_cancel (wa->chh);
      wa->chh = NULL;
    }
    GNUNET_CONTAINER_DLL_remove (wa_head,
                                 wa_tail,
                                 wa);
    GNUNET_free (wa->label_reserve_in_serial_id);
    GNUNET_free (wa->label_wire_out_serial_id);
    GNUNET_free (wa->label_wire_off_in);
    GNUNET_free (wa->label_wire_off_out);
    GNUNET_free (wa);
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
  TALER_EXCHANGEDB_unload_accounts ();
  TALER_ARL_cfg = NULL;
}


/**
 * Detect any entries in #reserve_closures that were not yet
 * observed on the wire transfer side and update the progress
 * point accordingly.
 *
 * @param cls NULL
 * @param key unused key
 * @param value the `struct ReserveClosure` to free
 * @return #GNUNET_OK
 */
static enum GNUNET_GenericReturnValue
check_pending_rc (void *cls,
                  const struct GNUNET_HashCode *key,
                  void *value)
{
  struct ReserveClosure *rc = value;

  (void) cls;
  (void) key;
  TALER_ARL_amount_add (&total_closure_amount_lag,
                        &total_closure_amount_lag,
                        &rc->amount);
  if ( (0 != rc->amount.value) ||
       (0 != rc->amount.fraction) )
    TALER_ARL_report (
      report_closure_lags,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("row",
                                 rc->rowid),
        TALER_JSON_pack_amount ("amount",
                                &rc->amount),
        TALER_JSON_pack_time_abs_human ("deadline",
                                        rc->execution_date.abs_time),
        GNUNET_JSON_pack_data_auto ("wtid",
                                    &rc->wtid),
        GNUNET_JSON_pack_string ("account",
                                 rc->receiver_account)));
  TALER_ARL_USE_PP (wire_reserve_close_id)
    = GNUNET_MIN (TALER_ARL_USE_PP (wire_reserve_close_id),
                  rc->rowid);
  return GNUNET_OK;
}


/**
 * Compute the key under which a reserve closure for a given
 * @a receiver_account and @a wtid would be stored.
 *
 * @param receiver_account payto://-URI of the account
 * @param wtid wire transfer identifier used
 * @param[out] key set to the key
 */
static void
hash_rc (const char *receiver_account,
         const struct TALER_WireTransferIdentifierRawP *wtid,
         struct GNUNET_HashCode *key)
{
  size_t slen = strlen (receiver_account);
  char buf[sizeof (struct TALER_WireTransferIdentifierRawP) + slen];

  GNUNET_memcpy (buf,
                 wtid,
                 sizeof (*wtid));
  GNUNET_memcpy (&buf[sizeof (*wtid)],
                 receiver_account,
                 slen);
  GNUNET_CRYPTO_hash (buf,
                      sizeof (buf),
                      key);
}


/**
 * Commit the transaction, checkpointing our progress in the auditor DB.
 *
 * @param qs transaction status so far
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
commit (enum GNUNET_DB_QueryStatus qs)
{
  if (qs >= 0)
  {
    if (had_start_balance)
    {
      struct TALER_Amount sum;

      TALER_ARL_amount_add (&sum,
                            &total_wire_in,
                            &start_balance);
      TALER_ARL_amount_subtract (&TALER_ARL_USE_AB (final_balance),
                                 &sum,
                                 &total_wire_out);
      qs = TALER_ARL_adb->update_balance (
        TALER_ARL_adb->cls,
        TALER_ARL_SET_AB (total_drained),
        TALER_ARL_SET_AB (final_balance),
        NULL);
    }
    else
    {
      TALER_ARL_amount_subtract (&TALER_ARL_USE_AB (final_balance),
                                 &total_wire_in,
                                 &total_wire_out);
      qs = TALER_ARL_adb->insert_balance (
        TALER_ARL_adb->cls,
        TALER_ARL_SET_AB (total_drained),
        TALER_ARL_SET_AB (final_balance),
        NULL);
    }
  }
  else
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (TALER_ARL_currency,
                                          &TALER_ARL_USE_AB (final_balance)));
  }
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Serialization issue, not recording progress\n");
    else
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Hard error, not recording progress\n");
    TALER_ARL_adb->rollback (TALER_ARL_adb->cls);
    TALER_ARL_edb->rollback (TALER_ARL_edb->cls);
    return qs;
  }
  for (struct WireAccount *wa = wa_head;
       NULL != wa;
       wa = wa->next)
  {
    GNUNET_assert (
      0 ==
      json_array_append_new (
        report_account_progress,
        GNUNET_JSON_PACK (
          GNUNET_JSON_pack_string ("account",
                                   wa->ai->section_name),
          GNUNET_JSON_pack_uint64 ("start_reserve_in",
                                   wa->start_pp.last_reserve_in_serial_id),
          GNUNET_JSON_pack_uint64 ("end_reserve_in",
                                   wa->pp.last_reserve_in_serial_id),
          GNUNET_JSON_pack_uint64 ("start_wire_out",
                                   wa->start_pp.last_wire_out_serial_id),
          GNUNET_JSON_pack_uint64 ("end_wire_out",
                                   wa->pp.last_wire_out_serial_id))));
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == wa->qsx)
      qs = TALER_ARL_adb->update_auditor_progress (
        TALER_ARL_adb->cls,
        wa->label_reserve_in_serial_id,
        wa->pp.last_reserve_in_serial_id,
        wa->label_wire_out_serial_id,
        wa->pp.last_wire_out_serial_id,
        wa->label_wire_off_in,
        wa->wire_off_in,
        wa->label_wire_off_out,
        wa->wire_off_out,
        NULL);
    else
      qs = TALER_ARL_adb->insert_auditor_progress (
        TALER_ARL_adb->cls,
        wa->label_reserve_in_serial_id,
        wa->pp.last_reserve_in_serial_id,
        wa->label_wire_out_serial_id,
        wa->pp.last_wire_out_serial_id,
        wa->label_wire_off_in,
        wa->wire_off_in,
        wa->label_wire_off_out,
        wa->wire_off_out,
        NULL);
    if (0 >= qs)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Failed to update auditor DB, not recording progress\n");
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return qs;
    }
  }
  GNUNET_CONTAINER_multihashmap_iterate (reserve_closures,
                                         &check_pending_rc,
                                         NULL);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qsx_gwap)
    qs = TALER_ARL_adb->update_auditor_progress (
      TALER_ARL_adb->cls,
      TALER_ARL_SET_PP (wire_reserve_close_id),
      TALER_ARL_SET_PP (wire_batch_deposit_id),
      TALER_ARL_SET_PP (wire_aggregation_id),
      NULL);
  else
    qs = TALER_ARL_adb->insert_auditor_progress (
      TALER_ARL_adb->cls,
      TALER_ARL_SET_PP (wire_reserve_close_id),
      TALER_ARL_SET_PP (wire_batch_deposit_id),
      TALER_ARL_SET_PP (wire_aggregation_id),
      NULL);
  if (0 >= qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Concluded audit step at %llu/%llu\n",
              (unsigned long long) TALER_ARL_USE_PP (wire_aggregation_id),
              (unsigned long long) TALER_ARL_USE_PP (wire_batch_deposit_id));

  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    qs = TALER_ARL_edb->commit (TALER_ARL_edb->cls);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Exchange DB commit failed, rolling back transaction\n");
      TALER_ARL_adb->rollback (TALER_ARL_adb->cls);
    }
    else
    {
      qs = TALER_ARL_adb->commit (TALER_ARL_adb->cls);
      if (0 > qs)
      {
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Auditor DB commit failed!\n");
      }
    }
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Processing failed, rolling back transaction\n");
    TALER_ARL_adb->rollback (TALER_ARL_adb->cls);
    TALER_ARL_edb->rollback (TALER_ARL_edb->cls);
  }
  return qs;
}


/* ***************************** Analyze required transfers ************************ */

/**
 * Closure for import_wire_missing_cb().
 */
struct ImportMissingWireContext
{
  /**
   * Set to maximum row ID encountered.
   */
  uint64_t max_batch_deposit_uuid;

  /**
   * Set to database errors in callback.
   */
  enum GNUNET_DB_QueryStatus err;
};


/**
 * Function called on deposits that need to be checked for their
 * wire transfer.
 *
 * @param cls closure, points to a `struct ImportMissingWireContext`
 * @param batch_deposit_serial_id serial of the entry in the batch deposits table
 * @param total_amount value of the missing deposits, including fee
 * @param wire_target_h_payto where should the funds be wired
 * @param deadline what was the earliest requested wire transfer deadline
 */
static void
import_wire_missing_cb (void *cls,
                        uint64_t batch_deposit_serial_id,
                        const struct TALER_Amount *total_amount,
                        const struct TALER_PaytoHashP *wire_target_h_payto,
                        struct GNUNET_TIME_Timestamp deadline)
{
  struct ImportMissingWireContext *wc = cls;
  enum GNUNET_DB_QueryStatus qs;

  if (wc->err < 0)
    return; /* already failed */
  GNUNET_assert (batch_deposit_serial_id > wc->max_batch_deposit_uuid);
  wc->max_batch_deposit_uuid = batch_deposit_serial_id;
  qs = TALER_ARL_adb->insert_pending_deposit (
    TALER_ARL_adb->cls,
    batch_deposit_serial_id,
    wire_target_h_payto,
    total_amount,
    deadline);
  if (qs < 0)
    wc->err = qs;
}


/**
 * Information about a delayed wire transfer and the possible
 * reasons for the delay.
 */
struct ReasonDetail
{
  /**
   * Total amount that should have been transferred.
   */
  struct TALER_Amount total_amount;

  /**
   * Earliest deadline for an expected transfer to the account.
   */
  struct GNUNET_TIME_Timestamp deadline;

  /**
   * Target account, NULL if even that is not known (due to
   * exchange lacking required entry in wire_targets table).
   */
  char *payto_uri;

  /**
   * Reasons due to pending KYC requests.
   */
  char *kyc_pending;

  /**
   * AML decision state for the target account.
   */
  enum TALER_AmlDecisionState status;

  /**
   * Current AML threshold for the account, may be an invalid account if the
   * default threshold applies.
   */
  struct TALER_Amount aml_limit;
};

/**
 * Closure for report_wire_missing_cb().
 */
struct ReportMissingWireContext
{
  /**
   * Map from wire_target_h_payto to `struct ReasonDetail`.
   */
  struct GNUNET_CONTAINER_MultiShortmap *map;

  /**
   * Set to database errors in callback.
   */
  enum GNUNET_DB_QueryStatus err;
};


/**
 * Closure for #clear_finished_transfer_cb().
 */
struct AggregationContext
{
  /**
   * Set to maximum row ID encountered.
   */
  uint64_t max_aggregation_serial;

  /**
   * Set to database errors in callback.
   */
  enum GNUNET_DB_QueryStatus err;
};


/**
 * Free memory allocated in @a value.
 *
 * @param cls unused
 * @param key unused
 * @param value must be a `struct ReasonDetail`
 * @return #GNUNET_YES if we should continue to
 *         iterate,
 *         #GNUNET_NO if not.
 */
static enum GNUNET_GenericReturnValue
free_report_entry (void *cls,
                   const struct GNUNET_ShortHashCode *key,
                   void *value)
{
  struct ReasonDetail *rd = value;

  GNUNET_free (rd->kyc_pending);
  GNUNET_free (rd->payto_uri);
  GNUNET_free (rd);
  return GNUNET_YES;
}


/**
 * We had an entry in our map of wire transfers that
 * should have been performed. Generate report.
 *
 * @param cls unused
 * @param key unused
 * @param value must be a `struct ReasonDetail`
 * @return #GNUNET_YES if we should continue to
 *         iterate,
 *         #GNUNET_NO if not.
 */
static enum GNUNET_GenericReturnValue
generate_report (void *cls,
                 const struct GNUNET_ShortHashCode *key,
                 void *value)
{
  struct ReasonDetail *rd = value;

  /* For now, we simplify and only check that the
     amount was tiny */
  if (0 > TALER_amount_cmp (&rd->total_amount,
                            &tiny_amount))
    return free_report_entry (cls,
                              key,
                              value); /* acceptable, amount was tiny */
  // TODO: maybe split total_amount_lag up by category below?
  TALER_ARL_amount_add (&total_amount_lag,
                        &total_amount_lag,
                        &rd->total_amount);
  if (NULL != rd->kyc_pending)
  {
    json_t *rep;

    rep = GNUNET_JSON_PACK (
      TALER_JSON_pack_amount ("total_amount",
                              &rd->total_amount),
      TALER_JSON_pack_time_abs_human ("deadline",
                                      rd->deadline.abs_time),
      GNUNET_JSON_pack_string ("kyc_pending",
                               rd->kyc_pending),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_string ("account",
                                 rd->payto_uri)));
    TALER_ARL_report (report_kyc_lags,
                      rep);
  }
  else if (TALER_AML_NORMAL != rd->status)
  {
    const char *sstatus = "<undefined>";
    json_t *rep;

    switch (rd->status)
    {
    case TALER_AML_NORMAL:
      GNUNET_assert (0);
      break;
    case TALER_AML_PENDING:
      sstatus = "pending";
      break;
    case TALER_AML_FROZEN:
      sstatus = "frozen";
      break;
    }
    rep = GNUNET_JSON_PACK (
      TALER_JSON_pack_amount ("total_amount",
                              &rd->total_amount),
      GNUNET_JSON_pack_allow_null (
        TALER_JSON_pack_amount ("aml_limit",
                                TALER_amount_is_valid (&rd->aml_limit)
                              ? &rd->aml_limit
                              : NULL)),
      TALER_JSON_pack_time_abs_human ("deadline",
                                      rd->deadline.abs_time),
      GNUNET_JSON_pack_string ("aml_status",
                               sstatus),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_string ("account",
                                 rd->payto_uri)));
    TALER_ARL_report (report_aml_lags,
                      rep);
  }
  else
  {
    json_t *rep;

    rep = GNUNET_JSON_PACK (
      TALER_JSON_pack_amount ("total_amount",
                              &rd->total_amount),
      TALER_JSON_pack_time_abs_human ("deadline",
                                      rd->deadline.abs_time),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_string ("account",
                                 rd->payto_uri)));
    TALER_ARL_report (report_lags,
                      rep);
  }

  return free_report_entry (cls,
                            key,
                            value);
}


/**
 * Function called on deposits that are past their due date
 * and have not yet seen a wire transfer.
 *
 * @param cls closure, points to a `struct ReportMissingWireContext`
 * @param batch_deposit_serial_id row in the database for which the wire transfer is missing
 * @param total_amount value of the missing deposits, including fee
 * @param wire_target_h_payto hash of payto-URI where the funds should have been wired
 * @param deadline what was the earliest requested wire transfer deadline
 */
static void
report_wire_missing_cb (void *cls,
                        uint64_t batch_deposit_serial_id,
                        const struct TALER_Amount *total_amount,
                        const struct TALER_PaytoHashP *wire_target_h_payto,
                        struct GNUNET_TIME_Timestamp deadline)
{
  struct ReportMissingWireContext *rc = cls;
  struct ReasonDetail *rd;

  rd = GNUNET_CONTAINER_multishortmap_get (rc->map,
                                           &wire_target_h_payto->hash);
  if (NULL == rd)
  {
    rd = GNUNET_new (struct ReasonDetail);
    GNUNET_assert (GNUNET_YES ==
                   GNUNET_CONTAINER_multishortmap_put (
                     rc->map,
                     &wire_target_h_payto->hash,
                     rd,
                     GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
    rc->err = TALER_ARL_edb->select_justification_for_missing_wire (
      TALER_ARL_edb->cls,
      wire_target_h_payto,
      &rd->payto_uri,
      &rd->kyc_pending,
      &rd->status,
      &rd->aml_limit);
    rd->total_amount = *total_amount;
    rd->deadline = deadline;
  }
  else
  {
    TALER_ARL_amount_add (&rd->total_amount,
                          &rd->total_amount,
                          total_amount);
    rd->deadline = GNUNET_TIME_timestamp_min (rd->deadline,
                                              deadline);
  }
}


/**
 * Function called on aggregations that were done for
 * a (batch) deposit.
 *
 * @param cls closure
 * @param tracking_serial_id where in the table are we
 * @param batch_deposit_serial_id which batch deposit was aggregated
 */
static void
clear_finished_transfer_cb (
  void *cls,
  uint64_t tracking_serial_id,
  uint64_t batch_deposit_serial_id)
{
  struct AggregationContext *ac = cls;
  enum GNUNET_DB_QueryStatus qs;

  if (0 > ac->err)
    return; /* already failed */
  GNUNET_assert (ac->max_aggregation_serial < tracking_serial_id);
  ac->max_aggregation_serial = tracking_serial_id;
  qs = TALER_ARL_adb->delete_pending_deposit (
    TALER_ARL_adb->cls,
    batch_deposit_serial_id);
  if (0 == qs)
  {
    /* Aggregated something twice or other error, report! */
    GNUNET_break (0);
    // FIXME: report more nicely!
  }
  if (0 > qs)
    ac->err = qs;
}


/**
 * Checks that all wire transfers that should have happened
 * (based on deposits) have indeed happened.
 */
static void
check_for_required_transfers (void)
{
  struct ImportMissingWireContext wc = {
    .max_batch_deposit_uuid = TALER_ARL_USE_PP (wire_batch_deposit_id),
    .err = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT
  };
  struct GNUNET_TIME_Absolute deadline;
  enum GNUNET_DB_QueryStatus qs;
  struct ReportMissingWireContext rc = {
    .err = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT
  };
  struct AggregationContext ac = {
    .max_aggregation_serial = TALER_ARL_USE_PP (wire_aggregation_id),
    .err = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT
  };

  qs = TALER_ARL_edb->select_batch_deposits_missing_wire (
    TALER_ARL_edb->cls,
    TALER_ARL_USE_PP (wire_batch_deposit_id),
    &import_wire_missing_cb,
    &wc);
  if ( (0 > qs) || (0 > wc.err) )
  {
    GNUNET_break (0);
    GNUNET_break ( (GNUNET_DB_STATUS_SOFT_ERROR == qs) ||
                   (GNUNET_DB_STATUS_SOFT_ERROR == wc.err) );
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  TALER_ARL_USE_PP (wire_batch_deposit_id) = wc.max_batch_deposit_uuid;
  qs = TALER_ARL_edb->select_aggregations_above_serial (
    TALER_ARL_edb->cls,
    TALER_ARL_USE_PP (wire_aggregation_id),
    &clear_finished_transfer_cb,
    &ac);
  if ( (0 > qs) || (0 > ac.err) )
  {
    GNUNET_break (0);
    GNUNET_break ( (GNUNET_DB_STATUS_SOFT_ERROR == qs) ||
                   (GNUNET_DB_STATUS_SOFT_ERROR == ac.err) );
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  TALER_ARL_USE_PP (wire_aggregation_id) = ac.max_aggregation_serial;
  /* Subtract #GRACE_PERIOD, so we can be a bit behind in processing
     without immediately raising undue concern */
  deadline = GNUNET_TIME_absolute_subtract (GNUNET_TIME_absolute_get (),
                                            GRACE_PERIOD);
  rc.map = GNUNET_CONTAINER_multishortmap_create (1024,
                                                  GNUNET_NO);
  qs = TALER_ARL_adb->select_pending_deposits (
    TALER_ARL_adb->cls,
    deadline,
    &report_wire_missing_cb,
    &rc);
  if ( (0 > qs) || (0 > rc.err) )
  {
    GNUNET_break (0);
    GNUNET_break ( (GNUNET_DB_STATUS_SOFT_ERROR == qs) ||
                   (GNUNET_DB_STATUS_SOFT_ERROR == rc.err) );
    GNUNET_CONTAINER_multishortmap_iterate (rc.map,
                                            &free_report_entry,
                                            NULL);
    GNUNET_CONTAINER_multishortmap_destroy (rc.map);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  GNUNET_CONTAINER_multishortmap_iterate (rc.map,
                                          &generate_report,
                                          NULL);
  GNUNET_CONTAINER_multishortmap_destroy (rc.map);
  /* conclude with success */
  commit (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT);
  GNUNET_SCHEDULER_shutdown ();
}


/* ***************************** Analyze reserves_out ************************ */

/**
 * Clean up after processing wire out data.
 */
static void
conclude_wire_out (void)
{
  GNUNET_CONTAINER_multihashmap_destroy (out_map);
  out_map = NULL;
  check_for_required_transfers ();
}


/**
 * Check that @a want is within #TIME_TOLERANCE of @a have.
 * Otherwise report an inconsistency in row @a rowid of @a table.
 *
 * @param table where is the inconsistency (if any)
 * @param rowid what is the row
 * @param want what is the expected time
 * @param have what is the time we got
 */
static void
check_time_difference (const char *table,
                       uint64_t rowid,
                       struct GNUNET_TIME_Timestamp want,
                       struct GNUNET_TIME_Timestamp have)
{
  struct GNUNET_TIME_Relative delta;
  char *details;

  if (GNUNET_TIME_timestamp_cmp (have, >, want))
    delta = GNUNET_TIME_absolute_get_difference (want.abs_time,
                                                 have.abs_time);
  else
    delta = GNUNET_TIME_absolute_get_difference (have.abs_time,
                                                 want.abs_time);
  if (GNUNET_TIME_relative_cmp (delta,
                                <=,
                                TIME_TOLERANCE))
    return;

  GNUNET_asprintf (&details,
                   "execution date mismatch (%s)",
                   GNUNET_TIME_relative2s (delta,
                                           true));
  TALER_ARL_report (report_row_minor_inconsistencies,
                    GNUNET_JSON_PACK (
                      GNUNET_JSON_pack_string ("table",
                                               table),
                      GNUNET_JSON_pack_uint64 ("row",
                                               rowid),
                      GNUNET_JSON_pack_string ("diagnostic",
                                               details)));
  GNUNET_free (details);
}


/**
 * Function called with details about outgoing wire transfers
 * as claimed by the exchange DB.
 *
 * @param cls a `struct WireAccount`
 * @param rowid unique serial ID for the refresh session in our DB
 * @param date timestamp of the transfer (roughly)
 * @param wtid wire transfer subject
 * @param payto_uri wire transfer details of the receiver
 * @param amount amount that was wired
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
wire_out_cb (void *cls,
             uint64_t rowid,
             struct GNUNET_TIME_Timestamp date,
             const struct TALER_WireTransferIdentifierRawP *wtid,
             const char *payto_uri,
             const struct TALER_Amount *amount)
{
  struct WireAccount *wa = cls;
  struct GNUNET_HashCode key;
  struct ReserveOutInfo *roi;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Exchange wire OUT at %s of %s with WTID %s\n",
              GNUNET_TIME_timestamp2s (date),
              TALER_amount2s (amount),
              TALER_B2S (wtid));
  TALER_ARL_amount_add (&total_wire_out,
                        &total_wire_out,
                        amount);
  GNUNET_CRYPTO_hash (wtid,
                      sizeof (struct TALER_WireTransferIdentifierRawP),
                      &key);
  roi = GNUNET_CONTAINER_multihashmap_get (out_map,
                                           &key);
  if (NULL == roi)
  {
    /* Wire transfer was not made (yet) at all (but would have been
       justified), so the entire amount is missing / still to be done.
       This is moderately harmless, it might just be that the aggregator
       has not yet fully caught up with the transfers it should do. */
    TALER_ARL_report (
      report_wire_out_inconsistencies,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("row",
                                 rowid),
        TALER_JSON_pack_amount ("amount_wired",
                                &zero),
        TALER_JSON_pack_amount ("amount_justified",
                                amount),
        GNUNET_JSON_pack_data_auto ("wtid",
                                    wtid),
        TALER_JSON_pack_time_abs_human ("timestamp",
                                        date.abs_time),
        GNUNET_JSON_pack_string ("diagnostic",
                                 "wire transfer not made (yet?)"),
        GNUNET_JSON_pack_string ("account_section",
                                 wa->ai->section_name)));
    TALER_ARL_amount_add (&total_bad_amount_out_minus,
                          &total_bad_amount_out_minus,
                          amount);
    if (TALER_ARL_do_abort ())
      return GNUNET_SYSERR;
    return GNUNET_OK;
  }
  if (0 != strcasecmp (payto_uri,
                       roi->details.credit_account_uri))
  {
    /* Destination bank account is wrong in actual wire transfer, so
       we should count the wire transfer as entirely spurious, and
       additionally consider the justified wire transfer as missing. */
    TALER_ARL_report (
      report_wire_out_inconsistencies,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("row",
                                 rowid),
        TALER_JSON_pack_amount ("amount_wired",
                                &roi->details.amount),
        TALER_JSON_pack_amount ("amount_justified",
                                &zero),
        GNUNET_JSON_pack_data_auto ("wtid",
                                    wtid),
        TALER_JSON_pack_time_abs_human ("timestamp",
                                        date.abs_time),
        GNUNET_JSON_pack_string ("diagnostic",
                                 "receiver account mismatch"),
        GNUNET_JSON_pack_string ("target",
                                 payto_uri),
        GNUNET_JSON_pack_string ("account_section",
                                 wa->ai->section_name)));
    TALER_ARL_amount_add (&total_bad_amount_out_plus,
                          &total_bad_amount_out_plus,
                          &roi->details.amount);
    TALER_ARL_report (
      report_wire_out_inconsistencies,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("row",
                                 rowid),
        TALER_JSON_pack_amount ("amount_wired",
                                &zero),
        TALER_JSON_pack_amount ("amount_justified",
                                amount),
        GNUNET_JSON_pack_data_auto ("wtid",
                                    wtid),
        TALER_JSON_pack_time_abs_human ("timestamp",
                                        date.abs_time),
        GNUNET_JSON_pack_string ("diagnostic",
                                 "receiver account mismatch"),
        GNUNET_JSON_pack_string ("target",
                                 roi->details.
                                 credit_account_uri),
        GNUNET_JSON_pack_string ("account_section",
                                 wa->ai->section_name)));
    TALER_ARL_amount_add (&total_bad_amount_out_minus,
                          &total_bad_amount_out_minus,
                          amount);
    goto cleanup;
  }
  if (0 != TALER_amount_cmp (&roi->details.amount,
                             amount))
  {
    TALER_ARL_report (
      report_wire_out_inconsistencies,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("row",
                                 rowid),
        TALER_JSON_pack_amount ("amount_justified",
                                amount),
        TALER_JSON_pack_amount ("amount_wired",
                                &roi->details.amount),
        GNUNET_JSON_pack_data_auto ("wtid",
                                    wtid),
        TALER_JSON_pack_time_abs_human ("timestamp",
                                        date.abs_time),
        GNUNET_JSON_pack_string ("diagnostic",
                                 "wire amount does not match"),
        GNUNET_JSON_pack_string ("account_section",
                                 wa->ai->section_name)));
    if (0 < TALER_amount_cmp (amount,
                              &roi->details.amount))
    {
      /* amount > roi->details.amount: wire transfer was smaller than it should have been */
      struct TALER_Amount delta;

      TALER_ARL_amount_subtract (&delta,
                                 amount,
                                 &roi->details.amount);
      TALER_ARL_amount_add (&total_bad_amount_out_minus,
                            &total_bad_amount_out_minus,
                            &delta);
    }
    else
    {
      /* roi->details.amount < amount: wire transfer was larger than it should have been */
      struct TALER_Amount delta;

      TALER_ARL_amount_subtract (&delta,
                                 &roi->details.amount,
                                 amount);
      TALER_ARL_amount_add (&total_bad_amount_out_plus,
                            &total_bad_amount_out_plus,
                            &delta);
    }
    goto cleanup;
  }

  check_time_difference ("wire_out",
                         rowid,
                         date,
                         roi->details.execution_date);
cleanup:
  GNUNET_assert (GNUNET_OK ==
                 free_roi (NULL,
                           &key,
                           roi));
  wa->pp.last_wire_out_serial_id = rowid + 1;
  if (TALER_ARL_do_abort ())
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


/**
 * Closure for #check_rc_matches
 */
struct CheckMatchContext
{

  /**
   * Reserve operation looking for a match
   */
  const struct ReserveOutInfo *roi;

  /**
   * Set to true if we found a match.
   */
  bool found;
};


/**
 * Check if any of the reserve closures match the given wire transfer.
 *
 * @param[in,out] cls a `struct CheckMatchContext`
 * @param key key of @a value in #reserve_closures
 * @param value a `struct ReserveClosure`
 */
static enum GNUNET_GenericReturnValue
check_rc_matches (void *cls,
                  const struct GNUNET_HashCode *key,
                  void *value)
{
  struct CheckMatchContext *ctx = cls;
  struct ReserveClosure *rc = value;

  if ( (0 == GNUNET_memcmp (&ctx->roi->details.wtid,
                            &rc->wtid)) &&
       (0 == strcasecmp (rc->receiver_account,
                         ctx->roi->details.credit_account_uri)) &&
       (0 == TALER_amount_cmp (&rc->amount,
                               &ctx->roi->details.amount)) )
  {
    check_time_difference ("reserves_closures",
                           rc->rowid,
                           rc->execution_date,
                           ctx->roi->details.execution_date);
    ctx->found = true;
    free_rc (NULL,
             key,
             rc);
    return GNUNET_NO;
  }
  return GNUNET_OK;
}


/**
 * Check whether the given transfer was justified by a reserve closure or
 * profit drain. If not, complain that we failed to match an entry from
 * #out_map.  This means a wire transfer was made without proper
 * justification.
 *
 * @param cls a `struct WireAccount`
 * @param key unused key
 * @param value the `struct ReserveOutInfo` to report
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
complain_out_not_found (void *cls,
                        const struct GNUNET_HashCode *key,
                        void *value)
{
  struct WireAccount *wa = cls;
  struct ReserveOutInfo *roi = value;
  struct GNUNET_HashCode rkey;
  struct CheckMatchContext ctx = {
    .roi = roi,
    .found = false
  };

  (void) key;
  hash_rc (roi->details.credit_account_uri,
           &roi->details.wtid,
           &rkey);
  GNUNET_CONTAINER_multihashmap_get_multiple (reserve_closures,
                                              &rkey,
                                              &check_rc_matches,
                                              &ctx);
  if (ctx.found)
    return GNUNET_OK;
  /* check for profit drain */
  {
    enum GNUNET_DB_QueryStatus qs;
    uint64_t serial;
    char *account_section;
    char *payto_uri;
    struct GNUNET_TIME_Timestamp request_timestamp;
    struct TALER_Amount amount;
    struct TALER_MasterSignatureP master_sig;

    qs = TALER_ARL_edb->get_drain_profit (TALER_ARL_edb->cls,
                                          &roi->details.wtid,
                                          &serial,
                                          &account_section,
                                          &payto_uri,
                                          &request_timestamp,
                                          &amount,
                                          &master_sig);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_break (0);
      global_ret = EXIT_FAILURE;
      GNUNET_SCHEDULER_shutdown ();
      return GNUNET_SYSERR;
    case GNUNET_DB_STATUS_SOFT_ERROR:
      /* should fail on commit later ... */
      GNUNET_break (0);
      return GNUNET_NO;
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      /* not a profit drain */
      break;
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Profit drain of %s to %s found!\n",
                  TALER_amount2s (&amount),
                  payto_uri);
      if (GNUNET_OK !=
          TALER_exchange_offline_profit_drain_verify (
            &roi->details.wtid,
            request_timestamp,
            &amount,
            account_section,
            payto_uri,
            &TALER_ARL_master_pub,
            &master_sig))
      {
        GNUNET_break (0);
        TALER_ARL_report (report_row_inconsistencies,
                          GNUNET_JSON_PACK (
                            GNUNET_JSON_pack_string ("table",
                                                     "profit_drains"),
                            GNUNET_JSON_pack_uint64 ("row",
                                                     serial),
                            GNUNET_JSON_pack_data_auto ("id",
                                                        &roi->details.wtid),
                            GNUNET_JSON_pack_string ("diagnostic",
                                                     "invalid signature")));
        TALER_ARL_amount_add (&total_bad_amount_out_plus,
                              &total_bad_amount_out_plus,
                              &amount);
      }
      else if (0 !=
               strcasecmp (payto_uri,
                           roi->details.credit_account_uri))
      {
        TALER_ARL_report (
          report_wire_out_inconsistencies,
          GNUNET_JSON_PACK (
            GNUNET_JSON_pack_uint64 ("row",
                                     serial),
            TALER_JSON_pack_amount ("amount_wired",
                                    &roi->details.amount),
            TALER_JSON_pack_amount ("amount_wired",
                                    &amount),
            GNUNET_JSON_pack_data_auto ("wtid",
                                        &roi->details.wtid),
            TALER_JSON_pack_time_abs_human ("timestamp",
                                            roi->details.execution_date.abs_time),
            GNUNET_JSON_pack_string ("account",
                                     wa->ai->section_name),
            GNUNET_JSON_pack_string ("diagnostic",
                                     "wrong target account")));
        TALER_ARL_amount_add (&total_bad_amount_out_plus,
                              &total_bad_amount_out_plus,
                              &amount);
      }
      else if (0 !=
               TALER_amount_cmp (&amount,
                                 &roi->details.amount))
      {
        TALER_ARL_report (
          report_wire_out_inconsistencies,
          GNUNET_JSON_PACK (
            GNUNET_JSON_pack_uint64 ("row",
                                     serial),
            TALER_JSON_pack_amount ("amount_justified",
                                    &roi->details.amount),
            TALER_JSON_pack_amount ("amount_wired",
                                    &amount),
            GNUNET_JSON_pack_data_auto ("wtid",
                                        &roi->details.wtid),
            TALER_JSON_pack_time_abs_human ("timestamp",
                                            roi->details.execution_date.abs_time),
            GNUNET_JSON_pack_string ("account",
                                     wa->ai->section_name),
            GNUNET_JSON_pack_string ("diagnostic",
                                     "profit drain amount incorrect")));
        TALER_ARL_amount_add (&total_bad_amount_out_minus,
                              &total_bad_amount_out_minus,
                              &roi->details.amount);
        TALER_ARL_amount_add (&total_bad_amount_out_plus,
                              &total_bad_amount_out_plus,
                              &amount);
      }
      GNUNET_free (account_section);
      GNUNET_free (payto_uri);
      /* profit drain was correct */
      TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_drained),
                            &TALER_ARL_USE_AB (total_drained),
                            &amount);
      return GNUNET_OK;
    }
  }

  TALER_ARL_report (
    report_wire_out_inconsistencies,
    GNUNET_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("row",
                               0),
      TALER_JSON_pack_amount ("amount_wired",
                              &roi->details.amount),
      TALER_JSON_pack_amount ("amount_justified",
                              &zero),
      GNUNET_JSON_pack_data_auto ("wtid",
                                  &roi->details.wtid),
      TALER_JSON_pack_time_abs_human ("timestamp",
                                      roi->details.execution_date.abs_time),
      GNUNET_JSON_pack_string ("account_section",
                               wa->ai->section_name),
      GNUNET_JSON_pack_string ("diagnostic",
                               "justification for wire transfer not found")));
  TALER_ARL_amount_add (&total_bad_amount_out_plus,
                        &total_bad_amount_out_plus,
                        &roi->details.amount);
  return GNUNET_OK;
}


/**
 * Main function for processing 'reserves_out' data.  We start by going over
 * the DEBIT transactions this time, and then verify that all of them are
 * justified by 'reserves_out'.
 *
 * @param cls `struct WireAccount` with a wire account list to process
 */
static void
process_debits (void *cls);


/**
 * Go over the "wire_out" table of the exchange and
 * verify that all wire outs are in that table.
 *
 * @param wa wire account we are processing
 */
static void
check_exchange_wire_out (struct WireAccount *wa)
{
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_assert (NULL == wa->dhh);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Analyzing exchange's wire OUT table for account `%s'\n",
              wa->ai->section_name);
  qs = TALER_ARL_edb->select_wire_out_above_serial_id_by_account (
    TALER_ARL_edb->cls,
    wa->ai->section_name,
    wa->pp.last_wire_out_serial_id,
    &wire_out_cb,
    wa);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  GNUNET_CONTAINER_multihashmap_iterate (out_map,
                                         &complain_out_not_found,
                                         wa);
  /* clean up */
  GNUNET_CONTAINER_multihashmap_iterate (out_map,
                                         &free_roi,
                                         NULL);
  process_debits (wa->next);
}


/**
 * This function is called for all transactions that
 * are debited from the exchange's account (outgoing
 * transactions).
 *
 * @param cls `struct WireAccount` with current wire account to process
 * @param dhr HTTP response details
 */
static void
history_debit_cb (void *cls,
                  const struct TALER_BANK_DebitHistoryResponse *dhr)
{
  struct WireAccount *wa = cls;
  struct ReserveOutInfo *roi;
  size_t slen;

  wa->dhh = NULL;
  switch (dhr->http_status)
  {
  case MHD_HTTP_OK:
    for (unsigned int i = 0; i<dhr->details.ok.details_length; i++)
    {
      const struct TALER_BANK_DebitDetails *dd
        = &dhr->details.ok.details[i];
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Analyzing bank DEBIT at %s of %s with WTID %s\n",
                  GNUNET_TIME_timestamp2s (dd->execution_date),
                  TALER_amount2s (&dd->amount),
                  TALER_B2S (&dd->wtid));
      /* Update offset */
      wa->wire_off_out = dd->serial_id;
      slen = strlen (dd->credit_account_uri) + 1;
      roi = GNUNET_malloc (sizeof (struct ReserveOutInfo)
                           + slen);
      GNUNET_CRYPTO_hash (&dd->wtid,
                          sizeof (dd->wtid),
                          &roi->subject_hash);
      roi->details.amount = dd->amount;
      roi->details.execution_date = dd->execution_date;
      roi->details.wtid = dd->wtid;
      roi->details.credit_account_uri = (const char *) &roi[1];
      GNUNET_memcpy (&roi[1],
                     dd->credit_account_uri,
                     slen);
      if (GNUNET_OK !=
          GNUNET_CONTAINER_multihashmap_put (out_map,
                                             &roi->subject_hash,
                                             roi,
                                             GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY))
      {
        char *diagnostic;

        GNUNET_asprintf (&diagnostic,
                         "duplicate subject hash `%s'",
                         TALER_B2S (&roi->subject_hash));
        TALER_ARL_amount_add (&total_wire_format_amount,
                              &total_wire_format_amount,
                              &dd->amount);
        TALER_ARL_report (report_wire_format_inconsistencies,
                          GNUNET_JSON_PACK (
                            TALER_JSON_pack_amount ("amount",
                                                    &dd->amount),
                            GNUNET_JSON_pack_uint64 ("wire_offset",
                                                     dd->serial_id),
                            GNUNET_JSON_pack_string ("diagnostic",
                                                     diagnostic)));
        GNUNET_free (diagnostic);
      }
    }
    check_exchange_wire_out (wa);
    return;
  case MHD_HTTP_NO_CONTENT:
    check_exchange_wire_out (wa);
    return;
  case MHD_HTTP_NOT_FOUND:
    if (ignore_account_404)
    {
      check_exchange_wire_out (wa);
      return;
    }
    break;
  default:
    break;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Error fetching debit history of account %s: %u/%u!\n",
              wa->ai->section_name,
              dhr->http_status,
              (unsigned int) dhr->ec);
  commit (GNUNET_DB_STATUS_HARD_ERROR);
  global_ret = EXIT_FAILURE;
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Main function for processing 'reserves_out' data.  We start by going over
 * the DEBIT transactions this time, and then verify that all of them are
 * justified by 'reserves_out'.
 *
 * @param cls `struct WireAccount` with a wire account list to process
 */
static void
process_debits (void *cls)
{
  struct WireAccount *wa = cls;

  /* skip accounts where DEBIT is not enabled */
  while ( (NULL != wa) &&
          (GNUNET_NO == wa->ai->debit_enabled) )
    wa = wa->next;
  if (NULL == wa)
  {
    /* end of iteration, now check wire_out to see
       if it matches #out_map */
    conclude_wire_out ();
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Checking bank DEBIT records of account `%s'\n",
              wa->ai->section_name);
  GNUNET_assert (NULL == wa->dhh);
  // FIXME: handle the case where more than INT32_MAX transactions exist.
  // (CG: used to be INT64_MAX, changed by MS to INT32_MAX, why? To be discussed with him!)
  wa->dhh = TALER_BANK_debit_history (ctx,
                                      wa->ai->auth,
                                      wa->wire_off_out,
                                      INT32_MAX,
                                      GNUNET_TIME_UNIT_ZERO,
                                      &history_debit_cb,
                                      wa);
  if (NULL == wa->dhh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain bank transaction history for `%s'\n",
                wa->ai->section_name);
    commit (GNUNET_DB_STATUS_HARD_ERROR);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


/**
 * Begin analyzing wire_out.
 */
static void
begin_debit_audit (void)
{
  GNUNET_assert (NULL == out_map);
  out_map = GNUNET_CONTAINER_multihashmap_create (1024,
                                                  true);
  process_debits (wa_head);
}


/* ***************************** Analyze reserves_in ************************ */

/**
 * Conclude the credit history check by logging entries that
 * were not found and freeing resources. Then move on to
 * processing debits.
 */
static void
conclude_credit_history (void)
{
  if (NULL != in_map)
  {
    GNUNET_CONTAINER_multihashmap_destroy (in_map);
    in_map = NULL;
  }
  /* credit done, now check debits */
  begin_debit_audit ();
}


/**
 * Function called with details about incoming wire transfers
 * as claimed by the exchange DB.
 *
 * @param cls a `struct WireAccount` we are processing
 * @param rowid unique serial ID for the entry in our DB
 * @param reserve_pub public key of the reserve (also the WTID)
 * @param credit amount that was received
 * @param sender_account_details payto://-URL of the sender's bank account
 * @param wire_reference unique identifier for the wire transfer
 * @param execution_date when did we receive the funds
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
reserve_in_cb (void *cls,
               uint64_t rowid,
               const struct TALER_ReservePublicKeyP *reserve_pub,
               const struct TALER_Amount *credit,
               const char *sender_account_details,
               uint64_t wire_reference,
               struct GNUNET_TIME_Timestamp execution_date)
{
  struct WireAccount *wa = cls;
  struct ReserveInInfo *rii;
  size_t slen;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Analyzing exchange wire IN (%llu) at %s of %s with reserve_pub %s\n",
              (unsigned long long) rowid,
              GNUNET_TIME_timestamp2s (execution_date),
              TALER_amount2s (credit),
              TALER_B2S (reserve_pub));
  TALER_ARL_amount_add (&total_wire_in,
                        &total_wire_in,
                        credit);
  slen = strlen (sender_account_details) + 1;
  rii = GNUNET_malloc (sizeof (struct ReserveInInfo) + slen);
  rii->rowid = rowid;
  rii->details.amount = *credit;
  rii->details.execution_date = execution_date;
  rii->details.reserve_pub = *reserve_pub;
  rii->details.debit_account_uri = (const char *) &rii[1];
  GNUNET_memcpy (&rii[1],
                 sender_account_details,
                 slen);
  GNUNET_CRYPTO_hash (&wire_reference,
                      sizeof (uint64_t),
                      &rii->row_off_hash);
  if (GNUNET_OK !=
      GNUNET_CONTAINER_multihashmap_put (in_map,
                                         &rii->row_off_hash,
                                         rii,
                                         GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY))
  {
    TALER_ARL_report (report_row_inconsistencies,
                      GNUNET_JSON_PACK (
                        GNUNET_JSON_pack_string ("table",
                                                 "reserves_in"),
                        GNUNET_JSON_pack_uint64 ("row",
                                                 rowid),
                        GNUNET_JSON_pack_data_auto ("id",
                                                    &rii->row_off_hash),
                        GNUNET_JSON_pack_string ("diagnostic",
                                                 "duplicate wire offset")));
    GNUNET_free (rii);
    if (TALER_ARL_do_abort ())
      return GNUNET_SYSERR;
    return GNUNET_OK;
  }
  wa->pp.last_reserve_in_serial_id = rowid + 1;
  if (TALER_ARL_do_abort ())
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


/**
 * Complain that we failed to match an entry from #in_map.
 *
 * @param cls a `struct WireAccount`
 * @param key unused key
 * @param value the `struct ReserveInInfo` to free
 * @return #GNUNET_OK
 */
static enum GNUNET_GenericReturnValue
complain_in_not_found (void *cls,
                       const struct GNUNET_HashCode *key,
                       void *value)
{
  struct WireAccount *wa = cls;
  struct ReserveInInfo *rii = value;

  (void) key;
  TALER_ARL_report (
    report_reserve_in_inconsistencies,
    GNUNET_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("row",
                               rii->rowid),
      TALER_JSON_pack_amount ("amount_exchange_expected",
                              &rii->details.amount),
      TALER_JSON_pack_amount ("amount_wired",
                              &zero),
      GNUNET_JSON_pack_data_auto ("reserve_pub",
                                  &rii->details.reserve_pub),
      TALER_JSON_pack_time_abs_human ("timestamp",
                                      rii->details.execution_date.abs_time),
      GNUNET_JSON_pack_string ("account",
                               wa->ai->section_name),
      GNUNET_JSON_pack_string ("diagnostic",
                               "incoming wire transfer claimed by exchange not found")));
  TALER_ARL_amount_add (&total_bad_amount_in_minus,
                        &total_bad_amount_in_minus,
                        &rii->details.amount);
  return GNUNET_OK;
}


/**
 * Start processing the next wire account.
 * Shuts down if we are done.
 *
 * @param cls `struct WireAccount` with a wire account list to process
 */
static void
process_credits (void *cls);


/**
 * We got all of the incoming transactions for @a wa,
 * finish processing the account.
 *
 * @param[in,out] wa wire account to process
 */
static void
conclude_account (struct WireAccount *wa)
{
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Reconciling CREDIT processing of account `%s'\n",
              wa->ai->section_name);
  if (NULL != in_map)
  {
    GNUNET_CONTAINER_multihashmap_iterate (in_map,
                                           &complain_in_not_found,
                                           wa);
    /* clean up before 2nd phase */
    GNUNET_CONTAINER_multihashmap_iterate (in_map,
                                           &free_rii,
                                           NULL);
  }
  process_credits (wa->next);
}


/**
 * Analyze credit transaction @a details into @a wa.
 *
 * @param[in,out] wa account that received the transfer
 * @param details transfer details
 * @return true on success, false to stop loop at this point
 */
static bool
analyze_credit (struct WireAccount *wa,
                const struct TALER_BANK_CreditDetails *details)
{
  struct ReserveInInfo *rii;
  struct GNUNET_HashCode key;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Analyzing bank CREDIT at %s of %s with Reserve-pub %s\n",
              GNUNET_TIME_timestamp2s (details->execution_date),
              TALER_amount2s (&details->amount),
              TALER_B2S (&details->reserve_pub));
  GNUNET_CRYPTO_hash (&details->serial_id,
                      sizeof (details->serial_id),
                      &key);
  rii = GNUNET_CONTAINER_multihashmap_get (in_map,
                                           &key);
  if (NULL == rii)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to find wire transfer at `%s' in exchange database. Audit ends at this point in time.\n",
                GNUNET_TIME_timestamp2s (details->execution_date));
    process_credits (wa->next);
    return false; /* not an error, just end of processing */
  }

  /* Update offset */
  wa->wire_off_in = details->serial_id;
  /* compare records with expected data */
  if (0 != GNUNET_memcmp (&details->reserve_pub,
                          &rii->details.reserve_pub))
  {
    TALER_ARL_report (
      report_reserve_in_inconsistencies,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("row",
                                 rii->rowid),
        GNUNET_JSON_pack_uint64 ("bank_row",
                                 details->serial_id),
        TALER_JSON_pack_amount ("amount_exchange_expected",
                                &rii->details.amount),
        TALER_JSON_pack_amount ("amount_wired",
                                &zero),
        GNUNET_JSON_pack_data_auto ("reserve_pub",
                                    &rii->details.reserve_pub),
        TALER_JSON_pack_time_abs_human ("timestamp",
                                        rii->details.execution_date.abs_time),
        GNUNET_JSON_pack_string ("diagnostic",
                                 "wire subject does not match")));
    TALER_ARL_amount_add (&total_bad_amount_in_minus,
                          &total_bad_amount_in_minus,
                          &rii->details.amount);
    TALER_ARL_report (
      report_reserve_in_inconsistencies,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("row",
                                 rii->rowid),
        GNUNET_JSON_pack_uint64 ("bank_row",
                                 details->serial_id),
        TALER_JSON_pack_amount ("amount_exchange_expected",
                                &zero),
        TALER_JSON_pack_amount ("amount_wired",
                                &details->amount),
        GNUNET_JSON_pack_data_auto ("reserve_pub",
                                    &details->reserve_pub),
        TALER_JSON_pack_time_abs_human ("timestamp",
                                        details->execution_date.abs_time),
        GNUNET_JSON_pack_string ("diagnostic",
                                 "wire subject does not match")));

    TALER_ARL_amount_add (&total_bad_amount_in_plus,
                          &total_bad_amount_in_plus,
                          &details->amount);
    goto cleanup;
  }
  if (0 != TALER_amount_cmp (&rii->details.amount,
                             &details->amount))
  {
    TALER_ARL_report (
      report_reserve_in_inconsistencies,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("row",
                                 rii->rowid),
        GNUNET_JSON_pack_uint64 ("bank_row",
                                 details->serial_id),
        TALER_JSON_pack_amount ("amount_exchange_expected",
                                &rii->details.amount),
        TALER_JSON_pack_amount ("amount_wired",
                                &details->amount),
        GNUNET_JSON_pack_data_auto ("reserve_pub",
                                    &details->reserve_pub),
        TALER_JSON_pack_time_abs_human ("timestamp",
                                        details->execution_date.abs_time),
        GNUNET_JSON_pack_string ("diagnostic",
                                 "wire amount does not match")));
    if (0 < TALER_amount_cmp (&details->amount,
                              &rii->details.amount))
    {
      /* details->amount > rii->details.amount: wire transfer was larger than it should have been */
      struct TALER_Amount delta;

      TALER_ARL_amount_subtract (&delta,
                                 &details->amount,
                                 &rii->details.amount);
      TALER_ARL_amount_add (&total_bad_amount_in_plus,
                            &total_bad_amount_in_plus,
                            &delta);
    }
    else
    {
      /* rii->details.amount < details->amount: wire transfer was smaller than it should have been */
      struct TALER_Amount delta;

      TALER_ARL_amount_subtract (&delta,
                                 &rii->details.amount,
                                 &details->amount);
      TALER_ARL_amount_add (&total_bad_amount_in_minus,
                            &total_bad_amount_in_minus,
                            &delta);
    }
    goto cleanup;
  }
  if (0 != strcasecmp (details->debit_account_uri,
                       rii->details.debit_account_uri))
  {
    TALER_ARL_report (report_misattribution_in_inconsistencies,
                      GNUNET_JSON_PACK (
                        TALER_JSON_pack_amount ("amount",
                                                &rii->details.amount),
                        GNUNET_JSON_pack_uint64 ("row",
                                                 rii->rowid),
                        GNUNET_JSON_pack_uint64 ("bank_row",
                                                 details->serial_id),
                        GNUNET_JSON_pack_data_auto (
                          "reserve_pub",
                          &rii->details.reserve_pub)));
    TALER_ARL_amount_add (&total_misattribution_in,
                          &total_misattribution_in,
                          &rii->details.amount);
  }
  if (GNUNET_TIME_timestamp_cmp (details->execution_date,
                                 !=,
                                 rii->details.execution_date))
  {
    TALER_ARL_report (report_row_minor_inconsistencies,
                      GNUNET_JSON_PACK (
                        GNUNET_JSON_pack_string ("table",
                                                 "reserves_in"),
                        GNUNET_JSON_pack_uint64 ("row",
                                                 rii->rowid),
                        GNUNET_JSON_pack_uint64 ("bank_row",
                                                 details->serial_id),
                        GNUNET_JSON_pack_string ("diagnostic",
                                                 "execution date mismatch")));
  }
cleanup:
  GNUNET_assert (GNUNET_OK ==
                 free_rii (NULL,
                           &key,
                           rii));
  return true;
}


/**
 * This function is called for all transactions that
 * are credited to the exchange's account (incoming
 * transactions).
 *
 * @param cls `struct WireAccount` we are processing
 * @param chr HTTP response returned by the bank
 */
static void
history_credit_cb (void *cls,
                   const struct TALER_BANK_CreditHistoryResponse *chr)
{
  struct WireAccount *wa = cls;

  wa->chh = NULL;
  switch (chr->http_status)
  {
  case MHD_HTTP_OK:
    for (unsigned int i = 0; i<chr->details.ok.details_length; i++)
    {
      const struct TALER_BANK_CreditDetails *cd
        = &chr->details.ok.details[i];

      if (! analyze_credit (wa,
                            cd))
        return;
    }
    conclude_account (wa);
    return;
  case MHD_HTTP_NO_CONTENT:
    conclude_account (wa);
    return;
  case MHD_HTTP_NOT_FOUND:
    if (ignore_account_404)
    {
      conclude_account (wa);
      return;
    }
    break;
  default:
    break;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Error fetching credit history of account %s: %u/%s!\n",
              wa->ai->section_name,
              chr->http_status,
              TALER_ErrorCode_get_hint (chr->ec));
  commit (GNUNET_DB_STATUS_HARD_ERROR);
  global_ret = EXIT_FAILURE;
  GNUNET_SCHEDULER_shutdown ();
}


/* ***************************** Setup logic ************************ */


/**
 * Start processing the next wire account.
 * Shuts down if we are done.
 *
 * @param cls `struct WireAccount` with a wire account list to process
 */
static void
process_credits (void *cls)
{
  struct WireAccount *wa = cls;
  enum GNUNET_DB_QueryStatus qs;

  /* skip accounts where CREDIT is not enabled */
  while ( (NULL != wa) &&
          (GNUNET_NO == wa->ai->credit_enabled) )
    wa = wa->next;
  if (NULL == wa)
  {
    /* done with all accounts, conclude check */
    conclude_credit_history ();
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Analyzing exchange's wire IN table for account `%s'\n",
              wa->ai->section_name);
  qs = TALER_ARL_edb->select_reserves_in_above_serial_id_by_account (
    TALER_ARL_edb->cls,
    wa->ai->section_name,
    wa->pp.last_reserve_in_serial_id,
    &reserve_in_cb,
    wa);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting bank CREDIT history of account `%s'\n",
              wa->ai->section_name);
  // NOTE: handle the case where more than INT32_MAX transactions exist.
  // (CG: used to be INT64_MAX, changed by MS to INT32_MAX, why? To be discussed with him!)
  wa->chh = TALER_BANK_credit_history (ctx,
                                       wa->ai->auth,
                                       wa->wire_off_in,
                                       INT32_MAX,
                                       GNUNET_TIME_UNIT_ZERO,
                                       &history_credit_cb,
                                       wa);
  if (NULL == wa->chh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain bank transaction history\n");
    commit (GNUNET_DB_STATUS_HARD_ERROR);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


/**
 * Begin audit of CREDITs to the exchange.
 */
static void
begin_credit_audit (void)
{
  GNUNET_assert (NULL == in_map);
  in_map = GNUNET_CONTAINER_multihashmap_create (1024,
                                                 GNUNET_YES);
  /* now go over all bank accounts and check delta with in_map */
  process_credits (wa_head);
}


/**
 * Function called about reserve closing operations the aggregator triggered.
 *
 * @param cls closure
 * @param rowid row identifier used to uniquely identify the reserve closing operation
 * @param execution_date when did we execute the close operation
 * @param amount_with_fee how much did we debit the reserve
 * @param closing_fee how much did we charge for closing the reserve
 * @param reserve_pub public key of the reserve
 * @param receiver_account where did we send the funds, in payto://-format
 * @param wtid identifier used for the wire transfer
 * @param close_request_row which close request triggered the operation?
 *         0 if it was a timeout (not used)
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
reserve_closed_cb (void *cls,
                   uint64_t rowid,
                   struct GNUNET_TIME_Timestamp execution_date,
                   const struct TALER_Amount *amount_with_fee,
                   const struct TALER_Amount *closing_fee,
                   const struct TALER_ReservePublicKeyP *reserve_pub,
                   const char *receiver_account,
                   const struct TALER_WireTransferIdentifierRawP *wtid,
                   uint64_t close_request_row)
{
  struct ReserveClosure *rc;
  struct GNUNET_HashCode key;

  (void) cls;
  (void) close_request_row;
  rc = GNUNET_new (struct ReserveClosure);
  if (TALER_ARL_SR_INVALID_NEGATIVE ==
      TALER_ARL_amount_subtract_neg (&rc->amount,
                                     amount_with_fee,
                                     closing_fee))
  {
    TALER_ARL_report (report_row_inconsistencies,
                      GNUNET_JSON_PACK (
                        GNUNET_JSON_pack_string ("table",
                                                 "reserves_closures"),
                        GNUNET_JSON_pack_uint64 ("row",
                                                 rowid),
                        GNUNET_JSON_pack_data_auto ("id",
                                                    reserve_pub),
                        TALER_JSON_pack_amount ("amount_with_fee",
                                                amount_with_fee),
                        TALER_JSON_pack_amount ("closing_fee",
                                                closing_fee),
                        GNUNET_JSON_pack_string ("diagnostic",
                                                 "closing fee above total amount")));
    GNUNET_free (rc);
    if (TALER_ARL_do_abort ())
      return GNUNET_SYSERR;
    return GNUNET_OK;
  }
  TALER_ARL_USE_PP (wire_reserve_close_id)
    = GNUNET_MAX (TALER_ARL_USE_PP (wire_reserve_close_id),
                  rowid + 1);
  rc->receiver_account = GNUNET_strdup (receiver_account);
  rc->wtid = *wtid;
  rc->execution_date = execution_date;
  rc->rowid = rowid;
  hash_rc (receiver_account,
           wtid,
           &key);
  (void) GNUNET_CONTAINER_multihashmap_put (reserve_closures,
                                            &key,
                                            rc,
                                            GNUNET_CONTAINER_MULTIHASHMAPOPTION_MULTIPLE);
  if (TALER_ARL_do_abort ())
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


/**
 * Start the database transactions and begin the audit.
 *
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
begin_transaction (void)
{
  enum GNUNET_DB_QueryStatus qs;

  if (GNUNET_SYSERR ==
      TALER_ARL_edb->preflight (TALER_ARL_edb->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize exchange database connection.\n");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_SYSERR ==
      TALER_ARL_adb->preflight (TALER_ARL_adb->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize auditor database session.\n");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_OK !=
      TALER_ARL_adb->start (TALER_ARL_adb->cls))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  TALER_ARL_edb->preflight (TALER_ARL_edb->cls);
  if (GNUNET_OK !=
      TALER_ARL_edb->start (TALER_ARL_edb->cls,
                            "wire auditor"))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &TALER_ARL_USE_AB (total_drained)));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &total_wire_in));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &total_wire_out));
  qs = TALER_ARL_adb->get_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_GET_AB (total_drained),
    TALER_ARL_GET_AB (final_balance),
    NULL);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    return qs;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (0);
    return qs;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    had_start_balance = false;
    break;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    had_start_balance = true;
    break;
  }
  for (struct WireAccount *wa = wa_head;
       NULL != wa;
       wa = wa->next)
  {
    GNUNET_asprintf (&wa->label_reserve_in_serial_id,
                     "wire-%s-%s",
                     wa->ai->section_name,
                     "reserve_in_serial_id");
    GNUNET_asprintf (&wa->label_wire_out_serial_id,
                     "wire-%s-%s",
                     wa->ai->section_name,
                     "wire_out_serial_id");
    GNUNET_asprintf (&wa->label_wire_off_in,
                     "wire-%s-%s",
                     wa->ai->section_name,
                     "wire_off_in");
    GNUNET_asprintf (&wa->label_wire_off_out,
                     "wire-%s-%s",
                     wa->ai->section_name,
                     "wire_off_out");
    wa->qsx = TALER_ARL_adb->get_auditor_progress (
      TALER_ARL_adb->cls,
      wa->label_reserve_in_serial_id,
      &wa->pp.last_reserve_in_serial_id,
      wa->label_wire_out_serial_id,
      &wa->pp.last_wire_out_serial_id,
      wa->label_wire_off_in,
      &wa->wire_off_in,
      wa->label_wire_off_out,
      &wa->wire_off_out,
      NULL);
    if (0 > wa->qsx)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == wa->qsx);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    wa->start_pp = wa->pp;
  }
  qsx_gwap = TALER_ARL_adb->get_auditor_progress (
    TALER_ARL_adb->cls,
    TALER_ARL_GET_PP (wire_reserve_close_id),
    TALER_ARL_GET_PP (wire_batch_deposit_id),
    TALER_ARL_GET_PP (wire_aggregation_id),
    NULL);
  if (0 > qsx_gwap)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsx_gwap);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsx_gwap)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "First analysis of with wire auditor, starting audit from scratch\n");
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Resuming wire audit at %llu / %llu / %llu\n",
                (unsigned long long) TALER_ARL_USE_PP (wire_reserve_close_id),
                (unsigned long long) TALER_ARL_USE_PP (wire_batch_deposit_id),
                (unsigned long long) TALER_ARL_USE_PP (wire_aggregation_id));
  }

  {
    enum GNUNET_DB_QueryStatus qs;

    qs = TALER_ARL_edb->select_reserve_closed_above_serial_id (
      TALER_ARL_edb->cls,
      TALER_ARL_USE_PP (wire_reserve_close_id),
      &reserve_closed_cb,
      NULL);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  begin_credit_audit ();
  return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
}


/**
 * Function called with information about a wire account.  Adds the
 * account to our list for processing (if it is enabled and we can
 * load the plugin).
 *
 * @param cls closure, NULL
 * @param ai account information
 */
static void
process_account_cb (void *cls,
                    const struct TALER_EXCHANGEDB_AccountInfo *ai)
{
  struct WireAccount *wa;

  (void) cls;
  if ( (! ai->debit_enabled) &&
       (! ai->credit_enabled) )
    return; /* not an active exchange account */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Found exchange account `%s'\n",
              ai->section_name);
  wa = GNUNET_new (struct WireAccount);
  wa->ai = ai;
  GNUNET_CONTAINER_DLL_insert (wa_head,
                               wa_tail,
                               wa);
}


/**
 * Main function that will be run.
 *
 * @param cls closure
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
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Launching wire auditor\n");
  if (GNUNET_OK !=
      TALER_ARL_init (c))
  {
    global_ret = EXIT_FAILURE;
    return;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (TALER_ARL_cfg,
                               "auditor",
                               "TINY_AMOUNT",
                               &tiny_amount))
  {
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &rc);
  rc = GNUNET_CURL_gnunet_rc_create (ctx);
  if (NULL == ctx)
  {
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    return;
  }
  reserve_closures = GNUNET_CONTAINER_multihashmap_create (1024,
                                                           GNUNET_NO);
  GNUNET_assert (NULL !=
                 (report_wire_out_inconsistencies = json_array ()));
  GNUNET_assert (NULL !=
                 (report_reserve_in_inconsistencies = json_array ()));
  GNUNET_assert (NULL !=
                 (report_row_minor_inconsistencies = json_array ()));
  GNUNET_assert (NULL !=
                 (report_wire_format_inconsistencies
                    = json_array ()));
  GNUNET_assert (NULL !=
                 (report_row_inconsistencies = json_array ()));
  GNUNET_assert (NULL !=
                 (report_misattribution_in_inconsistencies
                    = json_array ()));
  GNUNET_assert (NULL !=
                 (report_lags = json_array ()));
  GNUNET_assert (NULL !=
                 (report_aml_lags = json_array ()));
  GNUNET_assert (NULL !=
                 (report_kyc_lags = json_array ()));
  GNUNET_assert (NULL !=
                 (report_closure_lags = json_array ()));
  GNUNET_assert (NULL !=
                 (report_account_progress = json_array ()));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &total_bad_amount_out_plus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &total_bad_amount_out_minus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &total_bad_amount_in_plus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &total_bad_amount_in_minus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &total_misattribution_in));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &total_amount_lag));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &total_closure_amount_lag));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &total_wire_format_amount));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &zero));
  if (GNUNET_OK !=
      TALER_EXCHANGEDB_load_accounts (TALER_ARL_cfg,
                                      TALER_EXCHANGEDB_ALO_DEBIT
                                      | TALER_EXCHANGEDB_ALO_CREDIT
                                      | TALER_EXCHANGEDB_ALO_AUTHDATA))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "No bank accounts configured\n");
    global_ret = EXIT_NOTCONFIGURED;
    GNUNET_SCHEDULER_shutdown ();
  }
  TALER_EXCHANGEDB_find_accounts (&process_account_cb,
                                  NULL);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
      begin_transaction ())
  {
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
  }
}


/**
 * The main function of the wire auditing tool. Checks that
 * the exchange's records of wire transfers match that of
 * the wire gateway.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_flag ('i',
                               "internal",
                               "perform checks only applicable for exchange-internal audits",
                               &internal_checks),
    GNUNET_GETOPT_option_flag ('I',
                               "ignore-not-found",
                               "continue, even if the bank account of the exchange was not found",
                               &ignore_account_404),
    GNUNET_GETOPT_option_flag ('t',
                               "test",
                               "run in test mode and exit when idle",
                               &test_mode),
    GNUNET_GETOPT_option_timetravel ('T',
                                     "timetravel"),
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  if (GNUNET_OK !=
      GNUNET_STRINGS_get_utf8_args (argc, argv,
                                    &argc, &argv))
    return EXIT_INVALIDARGUMENT;
  ret = GNUNET_PROGRAM_run (
    argc,
    argv,
    "taler-helper-auditor-wire",
    gettext_noop (
      "Audit exchange database for consistency with the bank's wire transfers"),
    options,
    &run,
    NULL);
  GNUNET_free_nz ((void *) argv);
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  return global_ret;
}


/* end of taler-helper-auditor-wire.c */
