/*
  This file is part of TALER
  Copyright (C) 2017-2021 Taler Systems SA

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
   * Authentication data for the account.
   */
  struct TALER_BANK_AuthenticationData auth;

  /**
   * Name of the section that configures this account.
   */
  char *section_name;

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
   * Where we are in the inbound (CREDIT) transaction history.
   */
  uint64_t in_wire_off;

  /**
   * Where we are in the inbound (DEBIT) transaction history.
   */
  uint64_t out_wire_off;

  /**
   * We should check for inbound transactions to this account.
   */
  int watch_credit;

  /**
   * We should check for outbound transactions from this account.
   */
  int watch_debit;

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
  struct GNUNET_TIME_Absolute execution_date;

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
static struct TALER_AUDITORDB_WireProgressPoint pp;

/**
 * Last reserve_in / wire_out serial IDs seen.
 */
static struct TALER_AUDITORDB_WireProgressPoint start_pp;

/**
 * Array of reports about row inconsitencies in wire_out table.
 */
static json_t *report_wire_out_inconsistencies;

/**
 * Array of reports about row inconsitencies in reserves_in table.
 */
static json_t *report_reserve_in_inconsistencies;

/**
 * Array of reports about wrong bank account being recorded for
 * incoming wire transfers.
 */
static json_t *report_missattribution_in_inconsistencies;

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
static struct TALER_Amount total_missattribution_in;

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
static int
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
static int
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
static int
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
        GNUNET_JSON_pack_array_steal ("missattribution_in_inconsistencies",
                                      report_missattribution_in_inconsistencies),
        /* Tested in test-auditor.sh #9 */
        TALER_JSON_pack_amount ("total_missattribution_in",
                                &total_missattribution_in),
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
        /* Tested in test-auditor.sh #1 */
        TALER_JSON_pack_amount ("total_amount_lag",
                                &total_amount_lag),
        /* Tested in test-auditor.sh #1 */
        GNUNET_JSON_pack_array_steal ("lag_details",
                                      report_lags),
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
        GNUNET_JSON_pack_uint64 ("start_pp_reserve_close_uuid",
                                 start_pp.last_reserve_close_uuid),
        GNUNET_JSON_pack_uint64 ("end_pp_reserve_close_uuid",
                                 pp.last_reserve_close_uuid),
        TALER_JSON_pack_time_abs_human ("start_pp_last_timestamp",
                                        start_pp.last_timestamp),
        TALER_JSON_pack_time_abs_human ("end_pp_last_timestamp",
                                        pp.last_timestamp),
        GNUNET_JSON_pack_array_steal ("account_progress",
                                      report_account_progress)));
    report_wire_out_inconsistencies = NULL;
    report_reserve_in_inconsistencies = NULL;
    report_row_inconsistencies = NULL;
    report_row_minor_inconsistencies = NULL;
    report_missattribution_in_inconsistencies = NULL;
    report_lags = NULL;
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
    TALER_BANK_auth_free (&wa->auth);
    GNUNET_free (wa->section_name);
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
static int
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
    TALER_ARL_report (report_closure_lags,
                      GNUNET_JSON_PACK (
                        GNUNET_JSON_pack_uint64 ("row",
                                                 rc->rowid),
                        TALER_JSON_pack_amount ("amount",
                                                &rc->amount),
                        TALER_JSON_pack_time_abs_human ("deadline",
                                                        rc->execution_date),
                        GNUNET_JSON_pack_data_auto ("wtid",
                                                    &rc->wtid),
                        GNUNET_JSON_pack_string ("account",
                                                 rc->receiver_account)));
  pp.last_reserve_close_uuid
    = GNUNET_MIN (pp.last_reserve_close_uuid,
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

  memcpy (buf,
          wtid,
          sizeof (*wtid));
  memcpy (&buf[sizeof (*wtid)],
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
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Serialization issue, not recording progress\n");
    else
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Hard error, not recording progress\n");
    TALER_ARL_adb->rollback (TALER_ARL_adb->cls,
                             TALER_ARL_asession);
    TALER_ARL_edb->rollback (TALER_ARL_edb->cls,
                             TALER_ARL_esession);
    return qs;
  }
  for (struct WireAccount *wa = wa_head;
       NULL != wa;
       wa = wa->next)
  {
    GNUNET_assert (0 ==
                   json_array_append_new (
                     report_account_progress,
                     GNUNET_JSON_PACK (
                       GNUNET_JSON_pack_string ("account",
                                                wa->section_name),
                       GNUNET_JSON_pack_uint64 ("start_reserve_in",
                                                wa->start_pp.
                                                last_reserve_in_serial_id),
                       GNUNET_JSON_pack_uint64 ("end_reserve_in",
                                                wa->pp.last_reserve_in_serial_id),
                       GNUNET_JSON_pack_uint64 ("start_wire_out",
                                                wa->start_pp.
                                                last_wire_out_serial_id),
                       GNUNET_JSON_pack_uint64 ("end_wire_out",
                                                wa->pp.last_wire_out_serial_id))));
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == wa->qsx)
      qs = TALER_ARL_adb->update_wire_auditor_account_progress (
        TALER_ARL_adb->cls,
        TALER_ARL_asession,
        &TALER_ARL_master_pub,
        wa->section_name,
        &wa->pp,
        wa->in_wire_off,
        wa->out_wire_off);
    else
      qs = TALER_ARL_adb->insert_wire_auditor_account_progress (
        TALER_ARL_adb->cls,
        TALER_ARL_asession,
        &TALER_ARL_master_pub,
        wa->section_name,
        &wa->pp,
        wa->in_wire_off,
        wa->out_wire_off);
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
    qs = TALER_ARL_adb->update_wire_auditor_progress (TALER_ARL_adb->cls,
                                                      TALER_ARL_asession,
                                                      &TALER_ARL_master_pub,
                                                      &pp);
  else
    qs = TALER_ARL_adb->insert_wire_auditor_progress (TALER_ARL_adb->cls,
                                                      TALER_ARL_asession,
                                                      &TALER_ARL_master_pub,
                                                      &pp);
  if (0 >= qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Concluded audit step at %s\n",
              GNUNET_STRINGS_absolute_time_to_string (pp.last_timestamp));

  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    qs = TALER_ARL_edb->commit (TALER_ARL_edb->cls,
                                TALER_ARL_esession);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Exchange DB commit failed, rolling back transaction\n");
      TALER_ARL_adb->rollback (TALER_ARL_adb->cls,
                               TALER_ARL_asession);
    }
    else
    {
      qs = TALER_ARL_adb->commit (TALER_ARL_adb->cls,
                                  TALER_ARL_asession);
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
    TALER_ARL_adb->rollback (TALER_ARL_adb->cls,
                             TALER_ARL_asession);
    TALER_ARL_edb->rollback (TALER_ARL_edb->cls,
                             TALER_ARL_esession);
  }
  return qs;
}


/* ***************************** Analyze required transfers ************************ */

/**
 * Function called on deposits that are past their due date
 * and have not yet seen a wire transfer.
 *
 * @param cls closure
 * @param rowid deposit table row of the coin's deposit
 * @param coin_pub public key of the coin
 * @param amount value of the deposit, including fee
 * @param wire where should the funds be wired
 * @param deadline what was the requested wire transfer deadline
 * @param tiny did the exchange defer this transfer because it is too small?
 *             NOTE: only valid in internal audit mode!
 * @param done did the exchange claim that it made a transfer?
 *             NOTE: only valid in internal audit mode!
 */
static void
wire_missing_cb (void *cls,
                 uint64_t rowid,
                 const struct TALER_CoinSpendPublicKeyP *coin_pub,
                 const struct TALER_Amount *amount,
                 const json_t *wire,
                 struct GNUNET_TIME_Absolute deadline,
                 /* bool? */ int tiny,
                 /* bool? */ int done)
{
  json_t *rep;

  (void) cls;
  TALER_ARL_amount_add (&total_amount_lag,
                        &total_amount_lag,
                        amount);
  if (internal_checks)
  {
    /* In internal mode, we insist that the entry was
       actually marked as tiny. */
    if ( (GNUNET_YES == tiny) &&
         (0 > TALER_amount_cmp (amount,
                                &tiny_amount)) )
      return; /* acceptable, amount was tiny */
  }
  else
  {
    /* External auditors do not replicate tiny, so they
       only check that the amount is tiny */
    if (0 > TALER_amount_cmp (amount,
                              &tiny_amount))
      return; /* acceptable, amount was tiny */
  }
  rep = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_uint64 ("row",
                             rowid),
    TALER_JSON_pack_amount ("amount",
                            amount),
    TALER_JSON_pack_time_abs_human ("deadline",
                                    deadline),
    GNUNET_JSON_pack_data_auto ("coin_pub",
                                coin_pub),
    GNUNET_JSON_pack_object_incref ("account",
                                    (json_t *) wire));
  if (internal_checks)
  {
    /* the 'done' bit is only useful in 'internal' mode */
    GNUNET_assert (0 ==
                   json_object_set (rep,
                                    "claimed_done",
                                    json_string ((done) ? "yes" : "no")));
  }
  TALER_ARL_report (report_lags,
                    rep);
}


/**
 * Checks that all wire transfers that should have happened
 * (based on deposits) have indeed happened.
 */
static void
check_for_required_transfers (void)
{
  struct GNUNET_TIME_Absolute next_timestamp;
  enum GNUNET_DB_QueryStatus qs;

  next_timestamp = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&next_timestamp);
  /* Subtract #GRACE_PERIOD, so we can be a bit behind in processing
     without immediately raising undue concern */
  next_timestamp = GNUNET_TIME_absolute_subtract (next_timestamp,
                                                  GRACE_PERIOD);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Analyzing exchange's unfinished deposits (deadline: %s)\n",
              GNUNET_STRINGS_absolute_time_to_string (next_timestamp));
  qs = TALER_ARL_edb->select_deposits_missing_wire (TALER_ARL_edb->cls,
                                                    TALER_ARL_esession,
                                                    pp.last_timestamp,
                                                    next_timestamp,
                                                    &wire_missing_cb,
                                                    &next_timestamp);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  pp.last_timestamp = next_timestamp;
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
                       struct GNUNET_TIME_Absolute want,
                       struct GNUNET_TIME_Absolute have)
{
  struct GNUNET_TIME_Relative delta;
  char *details;

  if (have.abs_value_us > want.abs_value_us)
    delta = GNUNET_TIME_absolute_get_difference (want,
                                                 have);
  else
    delta = GNUNET_TIME_absolute_get_difference (have,
                                                 want);
  if (delta.rel_value_us <= TIME_TOLERANCE.rel_value_us)
    return;

  GNUNET_asprintf (&details,
                   "execution date mismatch (%s)",
                   GNUNET_STRINGS_relative_time_to_string (delta,
                                                           GNUNET_YES));
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
 * @param wire wire transfer details of the receiver
 * @param amount amount that was wired
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
wire_out_cb (void *cls,
             uint64_t rowid,
             struct GNUNET_TIME_Absolute date,
             const struct TALER_WireTransferIdentifierRawP *wtid,
             const json_t *wire,
             const struct TALER_Amount *amount)
{
  struct WireAccount *wa = cls;
  struct GNUNET_HashCode key;
  struct ReserveOutInfo *roi;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Exchange wire OUT at %s of %s with WTID %s\n",
              GNUNET_STRINGS_absolute_time_to_string (date),
              TALER_amount2s (amount),
              TALER_B2S (wtid));
  GNUNET_CRYPTO_hash (wtid,
                      sizeof (struct TALER_WireTransferIdentifierRawP),
                      &key);
  roi = GNUNET_CONTAINER_multihashmap_get (out_map,
                                           &key);
  if (NULL == roi)
  {
    /* Wire transfer was not made (yet) at all (but would have been
       justified), so the entire amount is missing / still to be done.
       This is moderately harmless, it might just be that the aggreator
       has not yet fully caught up with the transfers it should do. */
    TALER_ARL_report (report_wire_out_inconsistencies,
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
                                                        date),
                        GNUNET_JSON_pack_string ("diagnostic",
                                                 "wire transfer not made (yet?)"),
                        GNUNET_JSON_pack_string ("account_section",
                                                 wa->section_name)));
    TALER_ARL_amount_add (&total_bad_amount_out_minus,
                          &total_bad_amount_out_minus,
                          amount);
    if (TALER_ARL_do_abort ())
      return GNUNET_SYSERR;
    return GNUNET_OK;
  }
  {
    char *payto_uri;

    payto_uri = TALER_JSON_wire_to_payto (wire);
    if (0 != strcasecmp (payto_uri,
                         roi->details.credit_account_url))
    {
      /* Destination bank account is wrong in actual wire transfer, so
         we should count the wire transfer as entirely spurious, and
         additionally consider the justified wire transfer as missing. */
      TALER_ARL_report (report_wire_out_inconsistencies,
                        GNUNET_JSON_PACK (
                          GNUNET_JSON_pack_uint64 ("row",
                                                   rowid),
                          TALER_JSON_pack_amount ("amount_wired",
                                                  &roi->details.amount),
                          TALER_JSON_pack_amount ("amount_justified",
                                                  &zero),
                          GNUNET_JSON_pack_data_auto ("wtid", wtid),
                          TALER_JSON_pack_time_abs_human ("timestamp",
                                                          date),
                          GNUNET_JSON_pack_string ("diagnostic",
                                                   "receiver account mismatch"),
                          GNUNET_JSON_pack_string ("target",
                                                   payto_uri),
                          GNUNET_JSON_pack_string ("account_section",
                                                   wa->section_name)));
      TALER_ARL_amount_add (&total_bad_amount_out_plus,
                            &total_bad_amount_out_plus,
                            &roi->details.amount);
      TALER_ARL_report (report_wire_out_inconsistencies,
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
                                                          date),
                          GNUNET_JSON_pack_string ("diagnostic",
                                                   "receiver account mismatch"),
                          GNUNET_JSON_pack_string ("target",
                                                   roi->details.
                                                   credit_account_url),
                          GNUNET_JSON_pack_string ("account_section",
                                                   wa->section_name)));
      TALER_ARL_amount_add (&total_bad_amount_out_minus,
                            &total_bad_amount_out_minus,
                            amount);
      GNUNET_free (payto_uri);
      goto cleanup;
    }
    GNUNET_free (payto_uri);
  }
  if (0 != TALER_amount_cmp (&roi->details.amount,
                             amount))
  {
    TALER_ARL_report (report_wire_out_inconsistencies,
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
                                                        date),
                        GNUNET_JSON_pack_string ("diagnostic",
                                                 "wire amount does not match"),
                        GNUNET_JSON_pack_string ("account_section",
                                                 wa->section_name)));
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
   * Set to #GNUNET_YES if we found a match.
   */
  int found;
};


/**
 * Check if any of the reserve closures match the given wire transfer.
 *
 * @param[in,out] cls a `struct CheckMatchContext`
 * @param key key of @a value in #reserve_closures
 * @param value a `struct ReserveClosure`
 */
static int
check_rc_matches (void *cls,
                  const struct GNUNET_HashCode *key,
                  void *value)
{
  struct CheckMatchContext *ctx = cls;
  struct ReserveClosure *rc = value;

  if ( (0 == GNUNET_memcmp (&ctx->roi->details.wtid,
                            &rc->wtid)) &&
       (0 == strcasecmp (rc->receiver_account,
                         ctx->roi->details.credit_account_url)) &&
       (0 == TALER_amount_cmp (&rc->amount,
                               &ctx->roi->details.amount)) )
  {
    check_time_difference ("reserves_closures",
                           rc->rowid,
                           rc->execution_date,
                           ctx->roi->details.execution_date);
    ctx->found = GNUNET_YES;
    free_rc (NULL,
             key,
             rc);
    return GNUNET_NO;
  }
  return GNUNET_OK;
}


/**
 * Check whether the given transfer was justified by a reserve closure. If
 * not, complain that we failed to match an entry from #out_map.  This means a
 * wire transfer was made without proper justification.
 *
 * @param cls a `struct WireAccount`
 * @param key unused key
 * @param value the `struct ReserveOutInfo` to report
 * @return #GNUNET_OK
 */
static int
complain_out_not_found (void *cls,
                        const struct GNUNET_HashCode *key,
                        void *value)
{
  struct WireAccount *wa = cls;
  struct ReserveOutInfo *roi = value;
  struct GNUNET_HashCode rkey;
  struct CheckMatchContext ctx = {
    .roi = roi,
    .found = GNUNET_NO
  };

  (void) key;
  hash_rc (roi->details.credit_account_url,
           &roi->details.wtid,
           &rkey);
  GNUNET_CONTAINER_multihashmap_get_multiple (reserve_closures,
                                              &rkey,
                                              &check_rc_matches,
                                              &ctx);
  if (GNUNET_YES == ctx.found)
    return GNUNET_OK;
  TALER_ARL_report (report_wire_out_inconsistencies,
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
                                                      roi->details.
                                                      execution_date),
                      GNUNET_JSON_pack_string ("account_section",
                                               wa->section_name),
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

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Analyzing exchange's wire OUT table for account `%s'\n",
              wa->section_name);
  qs = TALER_ARL_edb->select_wire_out_above_serial_id_by_account (
    TALER_ARL_edb->cls,
    TALER_ARL_esession,
    wa->section_name,
    wa->pp.last_wire_out_serial_id,
    &wire_out_cb,
    wa);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    global_ret = 1;
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
 * @param http_status_code http status of the request
 * @param ec error code in case something went wrong
 * @param row_off identification of the position at which we are querying
 * @param details details about the wire transfer
 * @param json original response in JSON format
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to abort iteration
 */
static int
history_debit_cb (void *cls,
                  unsigned int http_status_code,
                  enum TALER_ErrorCode ec,
                  uint64_t row_off,
                  const struct TALER_BANK_DebitDetails *details,
                  const json_t *json)
{
  struct WireAccount *wa = cls;
  struct ReserveOutInfo *roi;
  size_t slen;

  (void) json;
  if (NULL == details)
  {
    wa->dhh = NULL;
    if (TALER_EC_NONE != ec)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Error fetching debit history of account %s: %u/%u!\n",
                  wa->section_name,
                  http_status_code,
                  (unsigned int) ec);
      commit (GNUNET_DB_STATUS_HARD_ERROR);
      global_ret = 1;
      GNUNET_SCHEDULER_shutdown ();
      return GNUNET_SYSERR;
    }
    check_exchange_wire_out (wa);
    return GNUNET_OK;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Analyzing bank DEBIT at %s of %s with WTID %s\n",
              GNUNET_STRINGS_absolute_time_to_string (details->execution_date),
              TALER_amount2s (&details->amount),
              TALER_B2S (&details->wtid));
  /* Update offset */
  wa->out_wire_off = row_off;
  slen = strlen (details->credit_account_url) + 1;
  roi = GNUNET_malloc (sizeof (struct ReserveOutInfo)
                       + slen);
  GNUNET_CRYPTO_hash (&details->wtid,
                      sizeof (details->wtid),
                      &roi->subject_hash);
  roi->details.amount = details->amount;
  roi->details.execution_date = details->execution_date;
  roi->details.wtid = details->wtid;
  roi->details.credit_account_url = (const char *) &roi[1];
  memcpy (&roi[1],
          details->credit_account_url,
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
                          &details->amount);
    TALER_ARL_report (report_wire_format_inconsistencies,
                      GNUNET_JSON_PACK (
                        TALER_JSON_pack_amount ("amount",
                                                &details->amount),
                        GNUNET_JSON_pack_uint64 ("wire_offset",
                                                 row_off),
                        GNUNET_JSON_pack_string ("diagnostic",
                                                 diagnostic)));
    GNUNET_free (diagnostic);
    return GNUNET_OK;
  }
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
process_debits (void *cls)
{
  struct WireAccount *wa = cls;

  /* skip accounts where DEBIT is not enabled */
  while ( (NULL != wa) &&
          (GNUNET_NO == wa->watch_debit) )
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
              wa->section_name);
  GNUNET_assert (NULL == wa->dhh);
  wa->dhh = TALER_BANK_debit_history (ctx,
                                      &wa->auth,
                                      wa->out_wire_off,
                                      INT64_MAX,
                                      &history_debit_cb,
                                      wa);
  if (NULL == wa->dhh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain bank transaction history for `%s'\n",
                wa->section_name);
    commit (GNUNET_DB_STATUS_HARD_ERROR);
    global_ret = 1;
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
  out_map = GNUNET_CONTAINER_multihashmap_create (1024,
                                                  GNUNET_YES);
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
  GNUNET_CONTAINER_multihashmap_destroy (in_map);
  in_map = NULL;
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
static int
reserve_in_cb (void *cls,
               uint64_t rowid,
               const struct TALER_ReservePublicKeyP *reserve_pub,
               const struct TALER_Amount *credit,
               const char *sender_account_details,
               uint64_t wire_reference,
               struct GNUNET_TIME_Absolute execution_date)
{
  struct WireAccount *wa = cls;
  struct ReserveInInfo *rii;
  size_t slen;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Analyzing exchange wire IN (%llu) at %s of %s with reserve_pub %s\n",
              (unsigned long long) rowid,
              GNUNET_STRINGS_absolute_time_to_string (execution_date),
              TALER_amount2s (credit),
              TALER_B2S (reserve_pub));
  slen = strlen (sender_account_details) + 1;
  rii = GNUNET_malloc (sizeof (struct ReserveInInfo) + slen);
  rii->rowid = rowid;
  rii->details.amount = *credit;
  rii->details.execution_date = execution_date;
  rii->details.reserve_pub = *reserve_pub;
  rii->details.debit_account_url = (const char *) &rii[1];
  memcpy (&rii[1],
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
                        GNUNET_JSON_pack_data_auto ("wire_offset_hash",
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
static int
complain_in_not_found (void *cls,
                       const struct GNUNET_HashCode *key,
                       void *value)
{
  struct WireAccount *wa = cls;
  struct ReserveInInfo *rii = value;

  (void) key;
  TALER_ARL_report (report_reserve_in_inconsistencies,
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
                                                      rii->details.
                                                      execution_date),
                      GNUNET_JSON_pack_string ("account",
                                               wa->section_name),
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
 * This function is called for all transactions that
 * are credited to the exchange's account (incoming
 * transactions).
 *
 * @param cls `struct WireAccount` we are processing
 * @param http_status HTTP status returned by the bank
 * @param ec error code in case something went wrong
 * @param row_off identification of the position at which we are querying
 * @param details details about the wire transfer
 * @param json raw response
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to abort iteration
 */
static int
history_credit_cb (void *cls,
                   unsigned int http_status,
                   enum TALER_ErrorCode ec,
                   uint64_t row_off,
                   const struct TALER_BANK_CreditDetails *details,
                   const json_t *json)
{
  struct WireAccount *wa = cls;
  struct ReserveInInfo *rii;
  struct GNUNET_HashCode key;

  (void) json;
  if (NULL == details)
  {
    wa->chh = NULL;
    if (TALER_EC_NONE != ec)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Error fetching credit history of account %s: %u/%u!\n",
                  wa->section_name,
                  http_status,
                  (unsigned int) ec);
      commit (GNUNET_DB_STATUS_HARD_ERROR);
      global_ret = 1;
      GNUNET_SCHEDULER_shutdown ();
      return GNUNET_SYSERR;
    }
    /* end of operation */
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Reconciling CREDIT processing of account `%s'\n",
                wa->section_name);
    GNUNET_CONTAINER_multihashmap_iterate (in_map,
                                           &complain_in_not_found,
                                           wa);
    /* clean up before 2nd phase */
    GNUNET_CONTAINER_multihashmap_iterate (in_map,
                                           &free_rii,
                                           NULL);
    process_credits (wa->next);
    return GNUNET_OK;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Analyzing bank CREDIT at %s of %s with Reserve-pub %s\n",
              GNUNET_STRINGS_absolute_time_to_string (details->execution_date),
              TALER_amount2s (&details->amount),
              TALER_B2S (&details->reserve_pub));
  GNUNET_CRYPTO_hash (&row_off,
                      sizeof (row_off),
                      &key);
  rii = GNUNET_CONTAINER_multihashmap_get (in_map,
                                           &key);
  if (NULL == rii)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to find wire transfer at `%s' in exchange database. Audit ends at this point in time.\n",
                GNUNET_STRINGS_absolute_time_to_string (
                  details->execution_date));
    wa->chh = NULL;
    process_credits (wa->next);
    return GNUNET_SYSERR; /* not an error, just end of processing */
  }

  /* Update offset */
  wa->in_wire_off = row_off;
  /* compare records with expected data */
  if (0 != GNUNET_memcmp (&details->reserve_pub,
                          &rii->details.reserve_pub))
  {
    TALER_ARL_report (report_reserve_in_inconsistencies,
                      GNUNET_JSON_PACK (
                        GNUNET_JSON_pack_uint64 ("row",
                                                 rii->rowid),
                        GNUNET_JSON_pack_uint64 ("bank_row",
                                                 row_off),
                        TALER_JSON_pack_amount ("amount_exchange_expected",
                                                &rii->details.amount),
                        TALER_JSON_pack_amount ("amount_wired",
                                                &zero),
                        GNUNET_JSON_pack_data_auto ("reserve_pub",
                                                    &rii->details.reserve_pub),
                        TALER_JSON_pack_time_abs_human ("timestamp",
                                                        rii->details.
                                                        execution_date),
                        GNUNET_JSON_pack_string ("diagnostic",
                                                 "wire subject does not match")));
    TALER_ARL_amount_add (&total_bad_amount_in_minus,
                          &total_bad_amount_in_minus,
                          &rii->details.amount);
    TALER_ARL_report (report_reserve_in_inconsistencies,
                      GNUNET_JSON_PACK (
                        GNUNET_JSON_pack_uint64 ("row",
                                                 rii->rowid),
                        GNUNET_JSON_pack_uint64 ("bank_row",
                                                 row_off),
                        TALER_JSON_pack_amount ("amount_exchange_expected",
                                                &zero),
                        TALER_JSON_pack_amount ("amount_wired",
                                                &details->amount),
                        GNUNET_JSON_pack_data_auto ("reserve_pub",
                                                    &details->reserve_pub),
                        TALER_JSON_pack_time_abs_human ("timestamp",
                                                        details->execution_date),
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
    TALER_ARL_report (report_reserve_in_inconsistencies,
                      GNUNET_JSON_PACK (
                        GNUNET_JSON_pack_uint64 ("row",
                                                 rii->rowid),
                        GNUNET_JSON_pack_uint64 ("bank_row",
                                                 row_off),
                        TALER_JSON_pack_amount ("amount_exchange_expected",
                                                &rii->details.amount),
                        TALER_JSON_pack_amount ("amount_wired",
                                                &details->amount),
                        GNUNET_JSON_pack_data_auto ("reserve_pub",
                                                    &details->reserve_pub),
                        TALER_JSON_pack_time_abs_human ("timestamp",
                                                        details->execution_date),
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
  if (0 != strcasecmp (details->debit_account_url,
                       rii->details.debit_account_url))
  {
    TALER_ARL_report (report_missattribution_in_inconsistencies,
                      GNUNET_JSON_PACK (
                        TALER_JSON_pack_amount ("amount",
                                                &rii->details.amount),
                        GNUNET_JSON_pack_uint64 ("row",
                                                 rii->rowid),
                        GNUNET_JSON_pack_uint64 ("bank_row",
                                                 row_off),
                        GNUNET_JSON_pack_data_auto (
                          "reserve_pub",
                          &rii->details.reserve_pub)));
    TALER_ARL_amount_add (&total_missattribution_in,
                          &total_missattribution_in,
                          &rii->details.amount);
  }
  if (details->execution_date.abs_value_us !=
      rii->details.execution_date.abs_value_us)
  {
    TALER_ARL_report (report_row_minor_inconsistencies,
                      GNUNET_JSON_PACK (
                        GNUNET_JSON_pack_string ("table",
                                                 "reserves_in"),
                        GNUNET_JSON_pack_uint64 ("row",
                                                 rii->rowid),
                        GNUNET_JSON_pack_uint64 ("bank_row",
                                                 row_off),
                        GNUNET_JSON_pack_string ("diagnostic",
                                                 "execution date mismatch")));
  }
cleanup:
  GNUNET_assert (GNUNET_OK ==
                 free_rii (NULL,
                           &key,
                           rii));
  return GNUNET_OK;
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
          (GNUNET_NO == wa->watch_credit) )
    wa = wa->next;
  if (NULL == wa)
  {
    /* done with all accounts, conclude check */
    conclude_credit_history ();
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Analyzing exchange's wire IN table for account `%s'\n",
              wa->section_name);
  qs = TALER_ARL_edb->select_reserves_in_above_serial_id_by_account (
    TALER_ARL_edb->cls,
    TALER_ARL_esession,
    wa->section_name,
    wa->pp.last_reserve_in_serial_id,
    &reserve_in_cb,
    wa);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting bank CREDIT history of account `%s'\n",
              wa->section_name);
  wa->chh = TALER_BANK_credit_history (ctx,
                                       &wa->auth,
                                       wa->in_wire_off,
                                       INT64_MAX,
                                       &history_credit_cb,
                                       wa);
  if (NULL == wa->chh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain bank transaction history\n");
    commit (GNUNET_DB_STATUS_HARD_ERROR);
    global_ret = 1;
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
  in_map = GNUNET_CONTAINER_multihashmap_create (1024,
                                                 GNUNET_YES);
  /* now go over all bank accounts and check delta with in_map */
  process_credits (wa_head);
}


/**
 * Function called about reserve closing operations
 * the aggregator triggered.
 *
 * @param cls closure
 * @param rowid row identifier used to uniquely identify the reserve closing operation
 * @param execution_date when did we execute the close operation
 * @param amount_with_fee how much did we debit the reserve
 * @param closing_fee how much did we charge for closing the reserve
 * @param reserve_pub public key of the reserve
 * @param receiver_account where did we send the funds, in payto://-format
 * @param wtid identifier used for the wire transfer
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
reserve_closed_cb (void *cls,
                   uint64_t rowid,
                   struct GNUNET_TIME_Absolute execution_date,
                   const struct TALER_Amount *amount_with_fee,
                   const struct TALER_Amount *closing_fee,
                   const struct TALER_ReservePublicKeyP *reserve_pub,
                   const char *receiver_account,
                   const struct TALER_WireTransferIdentifierRawP *wtid)
{
  struct ReserveClosure *rc;
  struct GNUNET_HashCode key;

  (void) cls;
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
                        GNUNET_JSON_pack_data_auto ("reserve_pub",
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
  pp.last_reserve_close_uuid
    = GNUNET_MAX (pp.last_reserve_close_uuid,
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
  TALER_ARL_esession = TALER_ARL_edb->get_session (TALER_ARL_edb->cls);
  if (NULL == TALER_ARL_esession)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize exchange database session.\n");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  TALER_ARL_asession = TALER_ARL_adb->get_session (TALER_ARL_adb->cls);
  if (NULL == TALER_ARL_asession)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize auditor database session.\n");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_OK !=
      TALER_ARL_adb->start (TALER_ARL_adb->cls,
                            TALER_ARL_asession))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  TALER_ARL_edb->preflight (TALER_ARL_edb->cls,
                            TALER_ARL_esession);
  if (GNUNET_OK !=
      TALER_ARL_edb->start (TALER_ARL_edb->cls,
                            TALER_ARL_esession,
                            "wire auditor"))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  for (struct WireAccount *wa = wa_head;
       NULL != wa;
       wa = wa->next)
  {
    wa->qsx = TALER_ARL_adb->get_wire_auditor_account_progress (
      TALER_ARL_adb->cls,
      TALER_ARL_asession,
      &TALER_ARL_master_pub,
      wa->section_name,
      &wa->pp,
      &wa->in_wire_off,
      &wa->out_wire_off);
    if (0 > wa->qsx)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == wa->qsx);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    wa->start_pp = wa->pp;
  }
  qsx_gwap = TALER_ARL_adb->get_wire_auditor_progress (TALER_ARL_adb->cls,
                                                       TALER_ARL_asession,
                                                       &TALER_ARL_master_pub,
                                                       &pp);
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
    start_pp = pp;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Resuming wire audit at %s / %llu\n",
                GNUNET_STRINGS_absolute_time_to_string (pp.last_timestamp),
                (unsigned long long) pp.last_reserve_close_uuid);
  }

  {
    enum GNUNET_DB_QueryStatus qs;

    qs = TALER_ARL_edb->select_reserve_closed_above_serial_id (
      TALER_ARL_edb->cls,
      TALER_ARL_esession,
      pp.last_reserve_close_uuid,
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
  if ( (GNUNET_NO == ai->debit_enabled) &&
       (GNUNET_NO == ai->credit_enabled) )
    return; /* not an active exchange account */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Found exchange account `%s'\n",
              ai->section_name);
  wa = GNUNET_new (struct WireAccount);
  wa->section_name = GNUNET_strdup (ai->section_name);
  wa->watch_debit = ai->debit_enabled;
  wa->watch_credit = ai->credit_enabled;
  if (GNUNET_OK !=
      TALER_BANK_auth_parse_cfg (TALER_ARL_cfg,
                                 ai->section_name,
                                 &wa->auth))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to access bank account `%s'\n",
                wa->section_name);
    GNUNET_break (0);
    GNUNET_free (wa->section_name);
    GNUNET_free (wa);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
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
    global_ret = 1;
    return;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (TALER_ARL_cfg,
                               "auditor",
                               "TINY_AMOUNT",
                               &tiny_amount))
  {
    global_ret = 1;
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
                 (report_missattribution_in_inconsistencies
                    = json_array ()));
  GNUNET_assert (NULL !=
                 (report_lags = json_array ()));
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
                                        &total_missattribution_in));
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
  TALER_EXCHANGEDB_find_accounts (TALER_ARL_cfg,
                                  &process_account_cb,
                                  NULL);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
      begin_transaction ())
  {
    global_ret = 1;
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
    GNUNET_GETOPT_option_base32_auto ('m',
                                      "exchange-key",
                                      "KEY",
                                      "public key of the exchange (Crockford base32 encoded)",
                                      &TALER_ARL_master_pub),
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
    return 4;
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
    return 3;
  if (GNUNET_NO == ret)
    return 0;
  return global_ret;
}


/* end of taler-helper-auditor-wire.c */
