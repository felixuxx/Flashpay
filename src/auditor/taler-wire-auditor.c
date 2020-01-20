/*
  This file is part of TALER
  Copyright (C) 2017-2020 Taler Systems SA

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
 * @file auditor/taler-wire-auditor.c
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
 * Command-line option "-r": restart audit from scratch
 */
static int restart;

/**
 * Time when we started the wire audit.
 */
static struct GNUNET_TIME_Absolute start_time;

/**
 * Handle to access the exchange's database.
 */
static struct TALER_EXCHANGEDB_Plugin *edb;

/**
 * Which currency are we doing the audit for?
 */
static char *currency;

/**
 * Our configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;

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
 * Our session with the #edb.
 */
static struct TALER_EXCHANGEDB_Session *esession;

/**
 * Handle to access the auditor's database.
 */
static struct TALER_AUDITORDB_Plugin *adb;

/**
 * Our session with the #adb.
 */
static struct TALER_AUDITORDB_Session *asession;

/**
 * Master public key of the exchange to audit.
 */
static struct TALER_MasterPublicKeyP master_pub;

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
 */
static enum GNUNET_DB_QueryStatus qsx;

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
 * Array of reports about row inconcistencies.
 */
static json_t *report_row_inconsistencies;

/**
 * Array of reports about inconcistencies in the database about
 * the incoming wire transfers (exchange is not exactly to blame).
 */
static json_t *report_wire_format_inconsistencies;

/**
 * Array of reports about minor row inconcistencies.
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
 * #edb later.
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
 * Convert absolute time to human-readable JSON string.
 *
 * @param at time to convert
 * @return human-readable string representing the time
 */
static json_t *
json_from_time_abs (struct GNUNET_TIME_Absolute at)
{
  return json_string
           (GNUNET_STRINGS_absolute_time_to_string (at));
}


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

  if (NULL != report_row_inconsistencies)
  {
    json_t *report;

    GNUNET_assert (NULL != report_row_minor_inconsistencies);
    report = json_pack ("{s:o, s:o, s:o, s:o, s:o,"
                        " s:o, s:o, s:o, s:o, s:o,"
                        " s:o, s:o, s:o, s:o, s:o,"
                        " s:o, s:o, s:o, s:I, s:I,"
                        " s:o, s:o, s:o }",
                        /* blocks of 5 */
                        /* Tested in test-auditor.sh #11, #15, #20 */
                        "wire_out_amount_inconsistencies",
                        report_wire_out_inconsistencies,
                        "total_wire_out_delta_plus",
                        TALER_JSON_from_amount (&total_bad_amount_out_plus),
                        /* Tested in test-auditor.sh #11, #15, #19 */
                        "total_wire_out_delta_minus",
                        TALER_JSON_from_amount (&total_bad_amount_out_minus),
                        /* Tested in test-auditor.sh #2 */
                        "reserve_in_amount_inconsistencies",
                        report_reserve_in_inconsistencies,
                        /* Tested in test-auditor.sh #2 */
                        "total_wire_in_delta_plus",
                        TALER_JSON_from_amount (&total_bad_amount_in_plus),
                        /* block */
                        /* Tested in test-auditor.sh #3 */
                        "total_wire_in_delta_minus",
                        TALER_JSON_from_amount (&total_bad_amount_in_minus),
                        /* Tested in test-auditor.sh #9 */
                        "missattribution_in_inconsistencies",
                        report_missattribution_in_inconsistencies,
                        /* Tested in test-auditor.sh #9 */
                        "total_missattribution_in",
                        TALER_JSON_from_amount (&total_missattribution_in),
                        "row_inconsistencies",
                        report_row_inconsistencies,
                        /* Tested in test-auditor.sh #10/#17 */
                        "row_minor_inconsistencies",
                        report_row_minor_inconsistencies,
                        /* block */
                        /* Tested in test-auditor.sh #19 */
                        "total_wire_format_amount",
                        TALER_JSON_from_amount (&total_wire_format_amount),
                        /* Tested in test-auditor.sh #19 */
                        "wire_format_inconsistencies",
                        report_wire_format_inconsistencies,
                        /* Tested in test-auditor.sh #1 */
                        "total_amount_lag",
                        TALER_JSON_from_amount (&total_amount_lag),
                        /* Tested in test-auditor.sh #1 */
                        "lag_details",
                        report_lags,
                        /* Tested in test-auditor.sh #22 */
                        "total_closure_amount_lag",
                        TALER_JSON_from_amount (&total_closure_amount_lag),
                        /* blocks of 5 */
                        /* Tested in test-auditor.sh #22 */
                        "reserve_lag_details",
                        report_closure_lags,
                        "wire_auditor_start_time",
                        json_from_time_abs (start_time),
                        "wire_auditor_end_time",
                        json_from_time_abs (GNUNET_TIME_absolute_get ()),
                        "start_pp_reserve_close_uuid",
                        (json_int_t) start_pp.last_reserve_close_uuid,
                        "end_pp_reserve_close_uuid",
                        (json_int_t) pp.last_reserve_close_uuid,
                        /* blocks of 5 */
                        "start_pp_last_timestamp",
                        json_from_time_abs (start_pp.last_timestamp),
                        "end_pp_last_timestamp",
                        json_from_time_abs (pp.last_timestamp),
                        "account_progress",
                        report_account_progress
                        );
    GNUNET_break (NULL != report);
    json_dumpf (report,
                stdout,
                JSON_INDENT (2));
    json_decref (report);
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
  if (NULL != adb)
  {
    TALER_AUDITORDB_plugin_unload (adb);
    adb = NULL;
  }
  if (NULL != edb)
  {
    TALER_EXCHANGEDB_plugin_unload (edb);
    edb = NULL;
  }
}


/* ***************************** Report logic **************************** */


/**
 * Add @a object to the report @a array.  Fail hard if this fails.
 *
 * @param array report array to append @a object to
 * @param object object to append, should be check that it is not NULL
 */
static void
report (json_t *array,
        json_t *object)
{
  GNUNET_assert (NULL != object);
  GNUNET_assert (0 ==
                 json_array_append_new (array,
                                        object));
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
  GNUNET_break (GNUNET_OK ==
                TALER_amount_add (&total_closure_amount_lag,
                                  &total_closure_amount_lag,
                                  &rc->amount));
  report (report_closure_lags,
          json_pack ("{s:I, s:o, s:o, s:o, s:s}",
                     "row", (json_int_t) rc->rowid,
                     "amount", TALER_JSON_from_amount (&rc->amount),
                     "deadline", json_from_time_abs (rc->execution_date),
                     "wtid", GNUNET_JSON_from_data_auto (&rc->wtid),
                     "account", rc->receiver_account));
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


/* *************************** General transaction logic ****************** */

/**
 * Commit the transaction, checkpointing our progress in the auditor
 * DB.
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
    adb->rollback (adb->cls,
                   asession);
    edb->rollback (edb->cls,
                   esession);
    return qs;
  }
  for (struct WireAccount *wa = wa_head;
       NULL != wa;
       wa = wa->next)
  {
    GNUNET_assert (0 ==
                   json_array_append_new (report_account_progress,
                                          json_pack (
                                            "{s:s, s:I, s:I, s:I, s:I}",
                                            "account",
                                            wa->section_name,
                                            "start_reserve_in",
                                            (json_int_t) wa->start_pp.
                                            last_reserve_in_serial_id,
                                            "end_reserve_in",
                                            (json_int_t) wa->pp.
                                            last_reserve_in_serial_id,
                                            "start_wire_out",
                                            (json_int_t) wa->start_pp.
                                            last_wire_out_serial_id,
                                            "end_wire_out",
                                            (json_int_t) wa->pp.
                                            last_wire_out_serial_id
                                            ))
                   );
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qsx)
      qs = adb->update_wire_auditor_account_progress (adb->cls,
                                                      asession,
                                                      &master_pub,
                                                      wa->section_name,
                                                      &wa->pp,
                                                      wa->in_wire_off,
                                                      wa->out_wire_off);
    else
      qs = adb->insert_wire_auditor_account_progress (adb->cls,
                                                      asession,
                                                      &master_pub,
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
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qsx)
    qs = adb->update_wire_auditor_progress (adb->cls,
                                            asession,
                                            &master_pub,
                                            &pp);
  else
    qs = adb->insert_wire_auditor_progress (adb->cls,
                                            asession,
                                            &master_pub,
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
    qs = edb->commit (edb->cls,
                      esession);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Exchange DB commit failed, rolling back transaction\n");
      adb->rollback (adb->cls,
                     asession);
    }
    else
    {
      qs = adb->commit (adb->cls,
                        asession);
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
    adb->rollback (adb->cls,
                   asession);
    edb->rollback (edb->cls,
                   esession);
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
 * @param done did the exchange claim that it made a transfer?
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
  (void) cls;
  GNUNET_break (GNUNET_OK ==
                TALER_amount_add (&total_amount_lag,
                                  &total_amount_lag,
                                  amount));
  if ( (GNUNET_YES == tiny) &&
       (0 > TALER_amount_cmp (amount,
                              &tiny_amount)) )
    return; /* acceptable, amount was tiny */
  report (report_lags,
          json_pack ("{s:I, s:o, s:o, s:s, s:o, s:O}",
                     "row", (json_int_t) rowid,
                     "amount", TALER_JSON_from_amount (amount),
                     "deadline", json_from_time_abs (deadline),
                     "claimed_done", (done) ? "yes" : "no",
                     "coin_pub", GNUNET_JSON_from_data_auto (coin_pub),
                     "account", wire));

}


/**
 * Checks that all wire transfers that should have happened
 * (based on deposits) have indeed happened.
 */
static void
check_for_required_transfers ()
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
  qs = edb->select_deposits_missing_wire (edb->cls,
                                          esession,
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
conclude_wire_out ()
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
  report (report_row_minor_inconsistencies,
          json_pack ("{s:s, s:I, s:s}",
                     "table", table,
                     "row", (json_int_t) rowid,
                     "diagnostic", details));
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
    report (report_wire_out_inconsistencies,
            json_pack ("{s:I, s:o, s:o, s:o, s:o, s:s, s:s}",
                       "row", (json_int_t) rowid,
                       "amount_wired", TALER_JSON_from_amount (&zero),
                       "amount_justified", TALER_JSON_from_amount (amount),
                       "wtid", GNUNET_JSON_from_data_auto (wtid),
                       "timestamp", json_from_time_abs (date),
                       "diagnostic", "wire transfer not made (yet?)",
                       "account_section", wa->section_name));
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (&total_bad_amount_out_minus,
                                    &total_bad_amount_out_minus,
                                    amount));
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
      report (report_wire_out_inconsistencies,
              json_pack ("{s:I, s:o, s:o, s:o, s:o, s:s, s:s}",
                         "row", (json_int_t) rowid,
                         "amount_wired", TALER_JSON_from_amount (
                           &roi->details.amount),
                         "amount_justified", TALER_JSON_from_amount (&zero),
                         "wtid", GNUNET_JSON_from_data_auto (wtid),
                         "timestamp", json_from_time_abs (date),
                         "diagnostic", "recevier account mismatch",
                         "account_section", wa->section_name));
      GNUNET_break (GNUNET_OK ==
                    TALER_amount_add (&total_bad_amount_out_plus,
                                      &total_bad_amount_out_plus,
                                      &roi->details.amount));
      report (report_wire_out_inconsistencies,
              json_pack ("{s:I, s:o, s:o, s:o, s:o, s:s, s:s}",
                         "row", (json_int_t) rowid,
                         "amount_wired", TALER_JSON_from_amount (&zero),
                         "amount_justified", TALER_JSON_from_amount (amount),
                         "wtid", GNUNET_JSON_from_data_auto (wtid),
                         "timestamp", json_from_time_abs (date),
                         "diagnostic", "receiver account mismatch",
                         "account_section", wa->section_name));
      GNUNET_break (GNUNET_OK ==
                    TALER_amount_add (&total_bad_amount_out_minus,
                                      &total_bad_amount_out_minus,
                                      amount));
      GNUNET_free (payto_uri);
      goto cleanup;
    }
    GNUNET_free (payto_uri);
  }
  if (0 != TALER_amount_cmp (&roi->details.amount,
                             amount))
  {
    report (report_wire_out_inconsistencies,
            json_pack ("{s:I, s:o, s:o, s:o, s:o, s:s, s:s}",
                       "row", (json_int_t) rowid,
                       "amount_justified", TALER_JSON_from_amount (amount),
                       "amount_wired", TALER_JSON_from_amount (
                         &roi->details.amount),
                       "wtid", GNUNET_JSON_from_data_auto (wtid),
                       "timestamp", json_from_time_abs (date),
                       "diagnostic", "wire amount does not match",
                       "account_section", wa->section_name));
    if (0 < TALER_amount_cmp (amount,
                              &roi->details.amount))
    {
      /* amount > roi->details.amount: wire transfer was smaller than it should have been */
      struct TALER_Amount delta;

      GNUNET_break (GNUNET_OK ==
                    TALER_amount_subtract (&delta,
                                           amount,
                                           &roi->details.amount));
      GNUNET_break (GNUNET_OK ==
                    TALER_amount_add (&total_bad_amount_out_minus,
                                      &total_bad_amount_out_minus,
                                      &delta));
    }
    else
    {
      /* roi->details.amount < amount: wire transfer was larger than it should have been */
      struct TALER_Amount delta;

      GNUNET_break (GNUNET_OK ==
                    TALER_amount_subtract (&delta,
                                           &roi->details.amount,
                                           amount));
      GNUNET_break (GNUNET_OK ==
                    TALER_amount_add (&total_bad_amount_out_plus,
                                      &total_bad_amount_out_plus,
                                      &delta));
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
 * @param cls a `struct CheckMatchContext`
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
  report (report_wire_out_inconsistencies,
          json_pack ("{s:I, s:o, s:o, s:o, s:o, s:s, s:s}",
                     "row", (json_int_t) 0,
                     "amount_wired", TALER_JSON_from_amount (
                       &roi->details.amount),
                     "amount_justified", TALER_JSON_from_amount (&zero),
                     "wtid", GNUNET_JSON_from_data_auto (&roi->details.wtid),
                     "timestamp", json_from_time_abs (
                       roi->details.execution_date),
                     "account_section",
                     wa->section_name,
                     "diagnostic",
                     "justification for wire transfer not found"));
  GNUNET_break (GNUNET_OK ==
                TALER_amount_add (&total_bad_amount_out_plus,
                                  &total_bad_amount_out_plus,
                                  &roi->details.amount));
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
  qs = edb->select_wire_out_above_serial_id_by_account (edb->cls,
                                                        esession,
                                                        wa->section_name,
                                                        wa->pp.
                                                        last_wire_out_serial_id,
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
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (&total_wire_format_amount,
                                    &total_wire_format_amount,
                                    &details->amount));
    report (report_wire_format_inconsistencies,
            json_pack ("{s:o, s:I, s:s}",
                       "amount", TALER_JSON_from_amount (&details->amount),
                       "wire_offset", (json_int_t) row_off,
                       "diagnostic", diagnostic));
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
    fprintf (stderr,
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
begin_debit_audit ()
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
               const struct
               TALER_ReservePublicKeyP *reserve_pub,
               const struct TALER_Amount *credit,
               const char *sender_account_details,
               uint64_t wire_reference,
               struct GNUNET_TIME_Absolute
               execution_date)
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
  rii = GNUNET_malloc (sizeof (struct ReserveInInfo)
                       + slen);
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
    report (report_row_inconsistencies,
            json_pack ("{s:s, s:I, s:o, s:s}",
                       "table", "reserves_in",
                       "row", (json_int_t) rowid,
                       "wire_offset_hash", GNUNET_JSON_from_data_auto (
                         &rii->row_off_hash),
                       "diagnostic", "duplicate wire offset"));
    GNUNET_free (rii);
    return GNUNET_OK;
  }
  wa->pp.last_reserve_in_serial_id = rowid + 1;
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
  report (report_reserve_in_inconsistencies,
          json_pack ("{s:I, s:o, s:o, s:o, s:o, s:s, s:s}",
                     "row", (json_int_t) rii->rowid,
                     "amount_exchange_expected", TALER_JSON_from_amount (
                       &rii->details.amount),
                     "amount_wired", TALER_JSON_from_amount (&zero),
                     "reserve_pub", GNUNET_JSON_from_data_auto (
                       &rii->details.reserve_pub),
                     "timestamp", json_from_time_abs (
                       rii->details.execution_date),
                     "account", wa->section_name,
                     "diagnostic",
                     "incoming wire transfer claimed by exchange not found"));
  GNUNET_break (GNUNET_OK ==
                TALER_amount_add (&total_bad_amount_in_minus,
                                  &total_bad_amount_in_minus,
                                  &rii->details.amount));
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
    report (report_reserve_in_inconsistencies,
            json_pack ("{s:I, s:I, s:o, s:o, s:o, s:o, s:s}",
                       "row", (json_int_t) rii->rowid,
                       "bank_row", (json_int_t) row_off,
                       "amount_exchange_expected", TALER_JSON_from_amount (
                         &rii->details.amount),
                       "amount_wired", TALER_JSON_from_amount (&zero),
                       "reserve_pub", GNUNET_JSON_from_data_auto (
                         &rii->details.reserve_pub),
                       "timestamp", json_from_time_abs (
                         rii->details.execution_date),
                       "diagnostic", "wire subject does not match"));
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (&total_bad_amount_in_minus,
                                    &total_bad_amount_in_minus,
                                    &rii->details.amount));
    report (report_reserve_in_inconsistencies,
            json_pack ("{s:I, s:I, s:o, s:o, s:o, s:o, s:s}",
                       "row", (json_int_t) rii->rowid,
                       "bank_row", (json_int_t) row_off,
                       "amount_exchange_expected", TALER_JSON_from_amount (
                         &zero),
                       "amount_wired", TALER_JSON_from_amount (
                         &details->amount),
                       "reserve_pub", GNUNET_JSON_from_data_auto (
                         &details->reserve_pub),
                       "timestamp", json_from_time_abs (
                         details->execution_date),
                       "diagnostic", "wire subject does not match"));

    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (&total_bad_amount_in_plus,
                                    &total_bad_amount_in_plus,
                                    &details->amount));
    goto cleanup;
  }
  if (0 != TALER_amount_cmp (&rii->details.amount,
                             &details->amount))
  {
    report (report_reserve_in_inconsistencies,
            json_pack ("{s:I, s:I, s:o, s:o, s:o, s:o, s:s}",
                       "row", (json_int_t) rii->rowid,
                       "bank_row", (json_int_t) row_off,
                       "amount_exchange_expected", TALER_JSON_from_amount (
                         &rii->details.amount),
                       "amount_wired", TALER_JSON_from_amount (
                         &details->amount),
                       "reserve_pub", GNUNET_JSON_from_data_auto (
                         &details->reserve_pub),
                       "timestamp", json_from_time_abs (
                         details->execution_date),
                       "diagnostic", "wire amount does not match"));
    if (0 < TALER_amount_cmp (&details->amount,
                              &rii->details.amount))
    {
      /* details->amount > rii->details.amount: wire transfer was larger than it should have been */
      struct TALER_Amount delta;

      GNUNET_break (GNUNET_OK ==
                    TALER_amount_subtract (&delta,
                                           &details->amount,
                                           &rii->details.amount));
      GNUNET_break (GNUNET_OK ==
                    TALER_amount_add (&total_bad_amount_in_plus,
                                      &total_bad_amount_in_plus,
                                      &delta));
    }
    else
    {
      /* rii->details.amount < details->amount: wire transfer was smaller than it should have been */
      struct TALER_Amount delta;

      GNUNET_break (GNUNET_OK ==
                    TALER_amount_subtract (&delta,
                                           &rii->details.amount,
                                           &details->amount));
      GNUNET_break (GNUNET_OK ==
                    TALER_amount_add (&total_bad_amount_in_minus,
                                      &total_bad_amount_in_minus,
                                      &delta));
    }
    goto cleanup;
  }
  if (0 != strcasecmp (details->debit_account_url,
                       rii->details.debit_account_url))
  {
    report (report_missattribution_in_inconsistencies,
            json_pack ("{s:o, s:I, s:I, s:o}",
                       "amount", TALER_JSON_from_amount (&rii->details.amount),
                       "row", (json_int_t) rii->rowid,
                       "bank_row", (json_int_t) row_off,
                       "reserve_pub", GNUNET_JSON_from_data_auto (
                         &rii->details.reserve_pub)));
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (&total_missattribution_in,
                                    &total_missattribution_in,
                                    &rii->details.amount));
  }
  if (details->execution_date.abs_value_us !=
      rii->details.execution_date.abs_value_us)
  {
    report (report_row_minor_inconsistencies,
            json_pack ("{s:s, s:I, s:I, s:s}",
                       "table", "reserves_in",
                       "row", (json_int_t) rii->rowid,
                       "bank_row", (json_int_t) row_off,
                       "diagnostic", "execution date mismatch"));
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
  qs = edb->select_reserves_in_above_serial_id_by_account (edb->cls,
                                                           esession,
                                                           wa->section_name,
                                                           wa->pp.
                                                           last_reserve_in_serial_id,
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
    fprintf (stderr,
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
begin_credit_audit ()
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
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&rc->amount,
                             amount_with_fee,
                             closing_fee))
  {
    report (report_row_inconsistencies,
            json_pack ("{s:s, s:I, s:o, s:o, s:o, s:s}",
                       "table", "reserves_closures",
                       "row", (json_int_t) rowid,
                       "reserve_pub", GNUNET_JSON_from_data_auto (reserve_pub),
                       "amount_with_fee", TALER_JSON_from_amount (
                         amount_with_fee),
                       "closing_fee", TALER_JSON_from_amount (closing_fee),
                       "diagnostic", "closing fee above total amount"));
    GNUNET_free (rc);
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
  return GNUNET_OK;
}


/**
 * Start the database transactions and begin the audit.
 */
static void
begin_transaction ()
{
  enum GNUNET_DB_QueryStatus qsx;
  int ret;

  ret = adb->start (adb->cls,
                    asession);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  edb->preflight (edb->cls,
                  esession);
  ret = edb->start (edb->cls,
                    esession,
                    "wire auditor");
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  for (struct WireAccount *wa = wa_head;
       NULL != wa;
       wa = wa->next)
  {
    qsx = adb->get_wire_auditor_account_progress (adb->cls,
                                                  asession,
                                                  &master_pub,
                                                  wa->section_name,
                                                  &wa->pp,
                                                  &wa->in_wire_off,
                                                  &wa->out_wire_off);
    if (0 > qsx)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsx);
      global_ret = 1;
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
    wa->start_pp = wa->pp;
  }
  qsx = adb->get_wire_auditor_progress (adb->cls,
                                        asession,
                                        &master_pub,
                                        &pp);
  if (0 > qsx)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsx);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsx)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                _ (
                  "First analysis using this auditor, starting audit from scratch\n"));
  }
  else
  {
    start_pp = pp;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Resuming audit at %s / %llu\n",
                GNUNET_STRINGS_absolute_time_to_string (pp.last_timestamp),
                (unsigned long long) pp.last_reserve_close_uuid);
  }
  edb->select_reserve_closed_above_serial_id (edb->cls,
                                              esession,
                                              pp.
                                              last_reserve_close_uuid,
                                              &reserve_closed_cb,
                                              NULL);
  begin_credit_audit ();
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
      TALER_BANK_auth_parse_cfg (cfg,
                                 ai->section_name,
                                 &wa->auth))
  {
    GNUNET_break (0);
    GNUNET_free (wa->section_name);
    GNUNET_free (wa);
    fprintf (stderr,
             "Failed to access bank account `%s'\n",
             wa->section_name);
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
  static const struct TALER_MasterPublicKeyP zeromp;

  (void) cls;
  (void) args;
  (void) cfgfile;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Launching auditor\n");
  start_time = GNUNET_TIME_absolute_get ();
  cfg = c;
  if (GNUNET_OK !=
      TALER_config_get_amount (cfg,
                               "auditor",
                               "TINY_AMOUNT",
                               &tiny_amount))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "auditor",
                               "TINY_AMOUNT",
                               "invalid amount");
    global_ret = 1;
    return;
  }
  if (0 == GNUNET_memcmp (&zeromp,
                          &master_pub))
  {
    /* -m option not given, try configuration */
    char *master_public_key_str;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "exchange",
                                               "MASTER_PUBLIC_KEY",
                                               &master_public_key_str))
    {
      fprintf (stderr,
               "Pass option -m or set it in the configuration!\n");
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "MASTER_PUBLIC_KEY");
      global_ret = 1;
      return;
    }
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_public_key_from_string (master_public_key_str,
                                                    strlen (
                                                      master_public_key_str),
                                                    &master_pub.eddsa_pub))
    {
      fprintf (stderr,
               "Invalid master public key given in configuration file.");
      GNUNET_free (master_public_key_str);
      global_ret = 1;
      return;
    }
    GNUNET_free (master_public_key_str);
  } /* end of -m not given */

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "taler",
                                             "CURRENCY",
                                             &currency))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler",
                               "CURRENCY");
    global_ret = 1;
    return;
  }
  if (NULL ==
      (edb = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize exchange database plugin.\n");
    global_ret = 1;
    return;
  }
  if (NULL ==
      (adb = TALER_AUDITORDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize auditor database plugin.\n");
    global_ret = 1;
    TALER_EXCHANGEDB_plugin_unload (edb);
    return;
  }
  if (restart)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Full audit restart requested, dropping old audit data.\n");
    GNUNET_break (GNUNET_OK ==
                  adb->drop_tables (adb->cls,
                                    GNUNET_NO));
    TALER_AUDITORDB_plugin_unload (adb);
    if (NULL ==
        (adb = TALER_AUDITORDB_plugin_load (cfg)))
    {
      fprintf (stderr,
               "Failed to initialize auditor database plugin after drop.\n");
      global_ret = 1;
      TALER_EXCHANGEDB_plugin_unload (edb);
      return;
    }
    GNUNET_break (GNUNET_OK ==
                  adb->create_tables (adb->cls));
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
  esession = edb->get_session (edb->cls);
  if (NULL == esession)
  {
    fprintf (stderr,
             "Failed to initialize exchange session.\n");
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  asession = adb->get_session (adb->cls);
  if (NULL == asession)
  {
    fprintf (stderr,
             "Failed to initialize auditor session.\n");
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
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
                 (report_wire_format_inconsistencies = json_array ()));
  GNUNET_assert (NULL !=
                 (report_row_inconsistencies = json_array ()));
  GNUNET_assert (NULL !=
                 (report_missattribution_in_inconsistencies = json_array ()));
  GNUNET_assert (NULL !=
                 (report_lags = json_array ()));
  GNUNET_assert (NULL !=
                 (report_closure_lags = json_array ()));
  GNUNET_assert (NULL !=
                 (report_account_progress = json_array ()));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_bad_amount_out_plus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_bad_amount_out_minus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_bad_amount_in_plus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_bad_amount_in_minus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_missattribution_in));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_amount_lag));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_closure_amount_lag));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_wire_format_amount));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &zero));
  TALER_EXCHANGEDB_find_accounts (cfg,
                                  &process_account_cb,
                                  NULL);
  begin_transaction ();
}


/**
 * The main function of the database initialization tool.
 * Used to initialize the Taler Exchange's database.
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
    GNUNET_GETOPT_option_base32_auto ('m',
                                      "exchange-key",
                                      "KEY",
                                      "public key of the exchange (Crockford base32 encoded)",
                                      &master_pub),
    GNUNET_GETOPT_option_flag ('r',
                               "restart",
                               "restart audit from the beginning (required on first run)",
                               &restart),
    GNUNET_GETOPT_OPTION_END
  };

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-wire-auditor",
                                   "MESSAGE",
                                   NULL));
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc,
                          argv,
                          "taler-wire-auditor",
                          "Audit exchange database for consistency with the bank's wire transfers",
                          options,
                          &run,
                          NULL))
    return 1;
  return global_ret;
}


/* end of taler-wire-auditor.c */
