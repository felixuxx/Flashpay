/*
  This file is part of TALER
  Copyright (C) 2017-2024 Taler Systems SA

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
 * @file auditor/taler-helper-auditor-wire-debit.c
 * @brief audits that wire outgoing transfers match those from an exchange
 * database.
 * @author Christian Grothoff
 * @author Özgür Kesim
 *
 * - We check that the outgoing wire transfers match those
 *   given in the 'wire_out' and 'reserve_closures' tables;
 *   any outgoing transfer MUST have a prior justification,
 *   so if one is missing we flag it (and never remove it).
 * - We check that all wire transfers that should
 *   have been made, were actually made. If any were not made,
 *   we flag those, but may remove those flags if we later
 *   find that the wire transfers were made (wire transfers
 *   could be delayed due to AML/KYC or core-banking issues).
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
#include "taler_dbevents.h"


/**
 * Maximum number of wire transfers we process per
 * (database) transaction.
 */
#define MAX_PER_TRANSACTION 1024

/**
 * How much do we allow the bank and the exchange to disagree about
 * timestamps? Should be sufficiently large to avoid bogus reports from deltas
 * created by imperfect clock synchronization and network delay.
 */
#define TIME_TOLERANCE GNUNET_TIME_relative_multiply ( \
          GNUNET_TIME_UNIT_MINUTES, \
          15)


/**
 * How long do we try to long-poll for bank wire transfers?
 */
#define MAX_LONGPOLL_DELAY GNUNET_TIME_relative_multiply ( \
          GNUNET_TIME_UNIT_HOURS, \
          1)


/**
 * How long do we wait between polling for bank wire transfers at the minimum?
 */
#define MIN_LONGPOLL_DELAY GNUNET_TIME_relative_multiply ( \
          GNUNET_TIME_UNIT_MINUTES, \
          5)


/**
 * Run in test mode. Exit when idle instead of
 * going to sleep and waiting for more work.
 */
static int test_mode;


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
  struct TALER_BANK_DebitHistoryHandle *dhh;

  /**
   * Task to trigger @e dhh long-polling.
   */
  struct GNUNET_SCHEDULER_Task *dhh_task;

  /**
   * Time when we expect the current @e dhh long-poll
   * to finish and we thus could begin another one.
   */
  struct GNUNET_TIME_Absolute dhh_next;

  /**
   * Progress point for this account.
   */
  uint64_t last_wire_out_serial_id;

  /**
   * Initial progress point for this account.
   */
  uint64_t start_wire_out_serial_id;

  /**
   * Where we are in the outbound transaction history.
   */
  uint64_t wire_off_out;

  /**
   * Label under which we store our pp's reserve_in_serial_id.
   */
  char *label_wire_out_serial_id;

  /**
   * Label under which we store our wire_off_out.
   */
  char *label_wire_off_out;
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
 * State of the current database transaction with
 * the auditor DB.
 */
static enum GNUNET_DB_QueryStatus global_qs;

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
 * Last reserve_out / wire_out serial IDs seen.
 */
static TALER_ARL_DEF_PP (wire_reserve_close_id);

/**
 * Amount that is considered "tiny"
 */
static struct TALER_Amount tiny_amount;

/**
 * Total amount that was transferred too much from the exchange.
 */
static TALER_ARL_DEF_AB (total_bad_amount_out_plus);

/**
 * Total amount that was transferred too little from the exchange.
 */
static TALER_ARL_DEF_AB (total_bad_amount_out_minus);

/**
 * Total amount of reserve closures which the exchange did not transfer in time.
 */
static TALER_ARL_DEF_AB (total_closure_amount_lag);

/**
 * Total amount affected by duplicate wire transfer
 * subjects.
 */
static TALER_ARL_DEF_AB (wire_debit_duplicate_transfer_subject_total);

/**
 * Total amount debited to exchange accounts.
 */
static TALER_ARL_DEF_AB (total_wire_out);

/**
 * Total amount of profits drained.
 */
static TALER_ARL_DEF_AB (total_drained);

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
static struct GNUNET_CURL_RescheduleContext *rctx;

/**
 * Should we run checks that only work for exchange-internal audits?
 */
static int internal_checks;

/**
 * Should we ignore if the bank does not know our bank
 * account?
 */
static int ignore_account_404;

/**
 * Database event handler to wake us up again.
 */
static struct GNUNET_DB_EventHandler *eh;

/**
 * The auditors's configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;


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
  if (NULL != eh)
  {
    TALER_ARL_adb->event_listen_cancel (eh);
    eh = NULL;
  }
  TALER_ARL_done ();
  if (NULL != reserve_closures)
  {
    GNUNET_CONTAINER_multihashmap_iterate (reserve_closures,
                                           &free_rc,
                                           NULL);
    GNUNET_CONTAINER_multihashmap_destroy (reserve_closures);
    reserve_closures = NULL;
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
    if (NULL != wa->dhh_task)
    {
      GNUNET_SCHEDULER_cancel (wa->dhh_task);
      wa->dhh_task = NULL;
    }
    if (NULL != wa->dhh)
    {
      TALER_BANK_debit_history_cancel (wa->dhh);
      wa->dhh = NULL;
    }
    GNUNET_CONTAINER_DLL_remove (wa_head,
                                 wa_tail,
                                 wa);
    GNUNET_free (wa->label_wire_out_serial_id);
    GNUNET_free (wa->label_wire_off_out);
    GNUNET_free (wa);
  }
  if (NULL != ctx)
  {
    GNUNET_CURL_fini (ctx);
    ctx = NULL;
  }
  if (NULL != rctx)
  {
    GNUNET_CURL_gnunet_rc_destroy (rctx);
    rctx = NULL;
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
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Missing wire transfer for closed reserve with balance %s\n",
              TALER_amount2s (&rc->amount));
  if (! TALER_amount_is_zero (&rc->amount))
  {
    struct TALER_AUDITORDB_ClosureLags cl = {
      .problem_row_id = rc->rowid,
      .account = rc->receiver_account,
      .amount = rc->amount,
      .deadline = rc->execution_date.abs_time,
      .wtid = rc->wtid
    };
    enum GNUNET_DB_QueryStatus qs;

    /* FIXME: where do we *undo* this if the wire transfer is
       found later? */
    qs = TALER_ARL_adb->insert_auditor_closure_lags (
      TALER_ARL_adb->cls,
      &cl);
    if (qs < 0)
    {
      global_qs = qs;
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return GNUNET_SYSERR;
    }
    /* FIXME: where do we *undo* this if the wire transfer is
       found later? */
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_closure_amount_lag),
                          &TALER_ARL_USE_AB (total_closure_amount_lag),
                          &rc->amount);
  }
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
 * Start the database transactions and begin the audit.
 *
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
begin_transaction (void);


/**
 * Commit the transaction, checkpointing our progress in the auditor DB.
 *
 * @param qs transaction status so far
 */
static void
commit (enum GNUNET_DB_QueryStatus qs)
{
  GNUNET_CONTAINER_multihashmap_iterate (reserve_closures,
                                         &check_pending_rc,
                                         NULL);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Transaction logic ended with status %d\n",
              qs);
  TALER_ARL_edb->rollback (TALER_ARL_edb->cls);
  qs = TALER_ARL_adb->update_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_AB (total_drained),
    TALER_ARL_SET_AB (total_wire_out),
    TALER_ARL_SET_AB (total_bad_amount_out_plus),
    TALER_ARL_SET_AB (total_bad_amount_out_minus),
    TALER_ARL_SET_AB (total_closure_amount_lag),
    TALER_ARL_SET_AB (wire_debit_duplicate_transfer_subject_total),
    TALER_ARL_SET_AB (total_wire_out),
    NULL);
  if (0 > qs)
    goto handle_db_error;
  qs = TALER_ARL_adb->insert_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_AB (total_drained),
    TALER_ARL_SET_AB (total_wire_out),
    TALER_ARL_SET_AB (total_bad_amount_out_plus),
    TALER_ARL_SET_AB (total_bad_amount_out_minus),
    TALER_ARL_SET_AB (total_closure_amount_lag),
    TALER_ARL_SET_AB (wire_debit_duplicate_transfer_subject_total),
    TALER_ARL_SET_AB (total_wire_out),
    NULL);
  if (0 > qs)
    goto handle_db_error;
  for (struct WireAccount *wa = wa_head;
       NULL != wa;
       wa = wa->next)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Transaction of account %s ends at %llu/%llu\n",
                wa->ai->section_name,
                (unsigned long long) wa->last_wire_out_serial_id,
                (unsigned long long) wa->wire_off_out);
    qs = TALER_ARL_adb->update_auditor_progress (
      TALER_ARL_adb->cls,
      wa->label_wire_out_serial_id,
      wa->last_wire_out_serial_id,
      wa->label_wire_off_out,
      wa->wire_off_out,
      NULL);
    if (0 > qs)
      goto handle_db_error;
    qs = TALER_ARL_adb->insert_auditor_progress (
      TALER_ARL_adb->cls,
      wa->label_wire_out_serial_id,
      wa->last_wire_out_serial_id,
      wa->label_wire_off_out,
      wa->wire_off_out,
      NULL);
    if (0 > qs)
      goto handle_db_error;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Transaction ends at %s=%llu for account `%s'\n",
                wa->label_wire_out_serial_id,
                (unsigned long long) wa->last_wire_out_serial_id,
                wa->ai->section_name);
  }
  qs = TALER_ARL_adb->update_auditor_progress (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_PP (wire_reserve_close_id),
    NULL);
  if (0 > qs)
    goto handle_db_error;
  qs = TALER_ARL_adb->insert_auditor_progress (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_PP (wire_reserve_close_id),
    NULL);
  if (0 > qs)
    goto handle_db_error;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Concluded audit step at %llu\n",
              (unsigned long long) TALER_ARL_USE_PP (wire_reserve_close_id));
  qs = TALER_ARL_adb->commit (TALER_ARL_adb->cls);
  if (0 > qs)
    goto handle_db_error;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Transaction concluded!\n");
  if (1 == test_mode)
    GNUNET_SCHEDULER_shutdown ();
  return;
handle_db_error:
  TALER_ARL_adb->rollback (TALER_ARL_adb->cls);
  for (unsigned int max_retries = 3; max_retries>0; max_retries--)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      break;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Serialization issue, trying again\n");
    qs = begin_transaction ();
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Hard database error, terminating\n");
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Check that @a want is within #TIME_TOLERANCE of @a have.
 * Otherwise report an inconsistency in row @a rowid of @a table.
 *
 * @param table where is the inconsistency (if any)
 * @param rowid what is the row
 * @param want what is the expected time
 * @param have what is the time we got
 * @return true on success, false to abort
 */
static bool
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
    return true;

  GNUNET_asprintf (&details,
                   "execution date mismatch (%s)",
                   GNUNET_TIME_relative2s (delta,
                                           true));
  {
    struct TALER_AUDITORDB_RowMinorInconsistencies rmi = {
      .row_table = (char *) table,
      .problem_row = rowid,
      .diagnostic = details
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = TALER_ARL_adb->insert_row_minor_inconsistencies (
      TALER_ARL_adb->cls,
      &rmi);

    if (qs < 0)
    {
      global_qs = qs;
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_free (details);
      return false;
    }
  }
  GNUNET_free (details);
  return true;
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
  struct CheckMatchContext *cmx = cls;
  struct ReserveClosure *rc = value;

  if ((0 == GNUNET_memcmp (&cmx->roi->details.wtid,
                           &rc->wtid)) &&
      (0 == strcasecmp (rc->receiver_account,
                        cmx->roi->details.credit_account_uri)) &&
      (0 == TALER_amount_cmp (&rc->amount,
                              &cmx->roi->details.amount)))
  {
    if (! check_time_difference ("reserves_closures",
                                 rc->rowid,
                                 rc->execution_date,
                                 cmx->roi->details.execution_date))
    {
      free_rc (NULL,
               key,
               rc);
      return GNUNET_SYSERR;
    }
    cmx->found = true;
    free_rc (NULL,
             key,
             rc);
    return GNUNET_NO;
  }
  return GNUNET_OK;
}


/**
 * Maximum required length for make_missing_diag().
 */
#define MAX_DIAG_LEN 128

/**
 * Make diagnostic string for missing wire transfer.
 *
 * @param[out] diag where to write the diagnostic string
 * @param wtid wire transfer ID to include
 */
static void
make_missing_diag (char diag[MAX_DIAG_LEN],
                   const struct TALER_WireTransferIdentifierRawP *wtid)
{
  char *wtid_s;

  wtid_s = GNUNET_STRINGS_data_to_string_alloc (wtid,
                                                sizeof (*wtid));
  GNUNET_snprintf (diag,
                   MAX_DIAG_LEN,
                   "expected outgoing wire transfer %s missing",
                   wtid_s);
  GNUNET_free (wtid_s);
}


/**
 * Check if an existing report on a missing wire
 * out operation justified the @a roi. If so,
 * clear the existing report.
 *
 * @param roi reserve out operation to check
 * @return #GNUNET_YES if @a roi was justified by a previous report,
 *         #GNUNET_NO of @a roi was not justified by a previous missing report
 *         #GNUNET_SYSERR on database trouble
 */
static enum GNUNET_GenericReturnValue
check_reported_inconsistency (struct ReserveOutInfo *roi)
{
  char diag[MAX_DIAG_LEN];
  struct TALER_AUDITORDB_WireOutInconsistency woi = {
    .wire_out_row_id = roi->details.serial_id,
    .destination_account = (char *) roi->details.credit_account_uri,
    .diagnostic = diag,
    .expected = roi->details.amount,
    .claimed = zero,
  };
  enum GNUNET_DB_QueryStatus qs;

  make_missing_diag (diag,
                     &roi->details.wtid);
  qs = TALER_ARL_adb->delete_wire_out_inconsistency_if_matching (
    TALER_ARL_adb->cls,
    &woi);
  if (qs < 0)
  {
    global_qs = qs;
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return GNUNET_SYSERR;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Deletion of wire out inconsistency %llu (%s, %s, %s) failed: not reported missing!\n",
                (unsigned long long) roi->details.serial_id,
                roi->details.credit_account_uri,
                diag,
                TALER_amount2s (&roi->details.amount));
    return GNUNET_NO;
  }
  TALER_ARL_amount_subtract (&TALER_ARL_USE_AB (total_bad_amount_out_minus),
                             &TALER_ARL_USE_AB (total_bad_amount_out_minus),
                             &roi->details.amount);
  return GNUNET_YES;
}


/**
 * Check if a profit drain operation justified the @a roi
 *
 * @param roi reserve out operation to check
 * @return #GNUNET_YES if @a roi was justified by a profit drain,
 *         #GNUNET_NO of @a roi was not justified by a proft drain
 *         #GNUNET_SYSERR on database trouble
 */
static enum GNUNET_GenericReturnValue
check_profit_drain (struct ReserveOutInfo *roi)
{
  enum GNUNET_DB_QueryStatus qs;
  uint64_t serial;
  char *account_section;
  char *payto_uri;
  struct GNUNET_TIME_Timestamp request_timestamp;
  struct TALER_Amount amount;
  struct TALER_MasterSignatureP master_sig;

  qs = TALER_ARL_edb->get_drain_profit (
    TALER_ARL_edb->cls,
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
    return GNUNET_SYSERR;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    /* not a profit drain */
    return GNUNET_NO;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break;
  }
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
    struct TALER_AUDITORDB_RowInconsistency ri = {
      .row_id = roi->details.serial_id,
      .row_table = "profit_drains",
      .diagnostic = "invalid signature"
    };

    GNUNET_break (0);
    qs = TALER_ARL_adb->insert_row_inconsistency (
      TALER_ARL_adb->cls,
      &ri);
    GNUNET_free (payto_uri);
    GNUNET_free (account_section);
    if (qs < 0)
    {
      global_qs = qs;
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return GNUNET_SYSERR;
    }
    return GNUNET_NO;
  }
  GNUNET_free (account_section);

  {
    char *np = TALER_payto_normalize (payto_uri);

    if (0 !=
        strcasecmp (np,
                    roi->details.credit_account_uri))
    {
      struct TALER_AUDITORDB_WireOutInconsistency woi = {
        .wire_out_row_id = serial,
        .destination_account = (char *) roi->details.credit_account_uri,
        .diagnostic = "profit drain wired to invalid account",
        .expected = roi->details.amount,
        .claimed = zero,
      };

      GNUNET_free (np);
      qs = TALER_ARL_adb->insert_wire_out_inconsistency (
        TALER_ARL_adb->cls,
        &woi);
      if (qs < 0)
      {
        global_qs = qs;
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        GNUNET_free (payto_uri);
        return GNUNET_SYSERR;
      }
      TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_bad_amount_out_plus),
                            &TALER_ARL_USE_AB (total_bad_amount_out_plus),
                            &amount);
      GNUNET_free (payto_uri);
      return GNUNET_YES; /* justified, kind-of */
    }
    GNUNET_free (np);
  }
  GNUNET_free (payto_uri);
  if (0 !=
      TALER_amount_cmp (&amount,
                        &roi->details.amount))
  {
    struct TALER_AUDITORDB_WireOutInconsistency woi = {
      .wire_out_row_id = roi->details.serial_id,
      .destination_account = (char *) roi->details.credit_account_uri,
      .diagnostic = "incorrect amount drained to correct account",
      .expected = roi->details.amount,
      .claimed = amount,
    };

    qs = TALER_ARL_adb->insert_wire_out_inconsistency (
      TALER_ARL_adb->cls,
      &woi);
    if (qs < 0)
    {
      global_qs = qs;
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return GNUNET_SYSERR;
    }
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_bad_amount_out_minus),
                          &TALER_ARL_USE_AB (total_bad_amount_out_minus),
                          &roi->details.amount);
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_bad_amount_out_plus),
                          &TALER_ARL_USE_AB (total_bad_amount_out_plus),
                          &amount);
    return GNUNET_YES; /* justified, kind-of */
  }
  /* profit drain was correct */
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_drained),
                        &TALER_ARL_USE_AB (total_drained),
                        &amount);
  return GNUNET_YES;
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
  // struct WireAccount *wa = cls;
  struct ReserveOutInfo *roi = value;
  struct GNUNET_HashCode rkey;
  struct CheckMatchContext cmx = {
    .roi = roi,
    .found = false
  };
  enum GNUNET_GenericReturnValue ret;

  (void) cls;
  (void) key;
  hash_rc (roi->details.credit_account_uri,
           &roi->details.wtid,
           &rkey);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Checking for reserve closure %s benefiting %s\n",
              GNUNET_h2s (&rkey),
              roi->details.credit_account_uri);
  GNUNET_CONTAINER_multihashmap_get_multiple (reserve_closures,
                                              &rkey,
                                              &check_rc_matches,
                                              &cmx);
  if (cmx.found)
    return GNUNET_OK;
  ret = check_reported_inconsistency (roi);
  if (GNUNET_NO != ret)
    return ret;
  ret = check_profit_drain (roi);
  if (GNUNET_NO != ret)
    return ret;


  {
    struct TALER_AUDITORDB_WireOutInconsistency woi = {
      .destination_account = (char *) roi->details.credit_account_uri,
      .diagnostic = "missing justification for outgoing wire transfer",
      .wire_out_row_id = roi->details.serial_id,
      .expected = zero,
      .claimed = roi->details.amount
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = TALER_ARL_adb->insert_wire_out_inconsistency (
      TALER_ARL_adb->cls,
      &woi);
    if (qs < 0)
    {
      global_qs = qs;
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return GNUNET_SYSERR;
    }
  }
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_bad_amount_out_plus),
                        &TALER_ARL_USE_AB (total_bad_amount_out_plus),
                        &roi->details.amount);
  return GNUNET_OK;
}


/**
 * Function called with details about outgoing wire transfers
 * as claimed by the exchange DB.
 *
 * @param cls a `struct WireAccount`
 * @param rowid unique serial ID in wire_out table
 * @param date timestamp of the transfer (roughly)
 * @param wtid wire transfer subject
 * @param payto_uri wire transfer details of the receiver
 * @param amount amount that was wired
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
wire_out_cb (
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Timestamp date,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const char *payto_uri,
  const struct TALER_Amount *amount)
{
  struct WireAccount *wa = cls;
  struct GNUNET_HashCode key;
  struct ReserveOutInfo *roi;
  char *np = TALER_payto_normalize (payto_uri);

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Exchange wire OUT #%llu at %s of %s with WTID %s\n",
              (unsigned long long) rowid,
              GNUNET_TIME_timestamp2s (date),
              TALER_amount2s (amount),
              TALER_B2S (wtid));
  wa->last_wire_out_serial_id = rowid + 1;
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_wire_out),
                        &TALER_ARL_USE_AB (total_wire_out),
                        amount);
  GNUNET_CRYPTO_hash (wtid,
                      sizeof (*wtid),
                      &key);
  roi = GNUNET_CONTAINER_multihashmap_get (out_map,
                                           &key);
  if (NULL == roi)
  {
    /* Wire transfer was not made (yet) at all (but would have been
       justified), so the entire amount is missing / still to be done.  This
       is moderately harmless, it might just be that the
       taler-exchange-transfer tool or bank has not yet fully caught up with
       the transfers it should do.
       May be cleared later by check_reported_inconsistency() */
    char diag[MAX_DIAG_LEN];
    struct TALER_AUDITORDB_WireOutInconsistency woi = {
      .destination_account = np,
      .diagnostic = diag,
      .wire_out_row_id = rowid,
      .expected = *amount,
      .claimed = zero,
    };
    enum GNUNET_DB_QueryStatus qs;

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Wire out for row %llu still missing\n",
                (unsigned long long) rowid);
    make_missing_diag (diag,
                       wtid);
    qs = TALER_ARL_adb->insert_wire_out_inconsistency (
      TALER_ARL_adb->cls,
      &woi);
    GNUNET_free (np);
    if (qs < 0)
    {
      global_qs = qs;
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return GNUNET_SYSERR;
    }
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_bad_amount_out_minus),
                          &TALER_ARL_USE_AB (total_bad_amount_out_minus),
                          amount);
    return GNUNET_OK;
  }

  if (0 != strcasecmp (np,
                       roi->details.credit_account_uri))
  {
    /* Destination bank account is wrong in actual wire transfer, so
       we should count the wire transfer as entirely spurious, and
       additionally consider the justified wire transfer as missing. */
    struct TALER_AUDITORDB_WireOutInconsistency woi = {
      .wire_out_row_id = rowid,
      .destination_account = np,
      .diagnostic = "receiver account mismatch",
      .expected = *amount,
      .claimed = roi->details.amount,
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = TALER_ARL_adb->insert_wire_out_inconsistency (
      TALER_ARL_adb->cls,
      &woi);
    GNUNET_free (np);
    if (qs < 0)
    {
      global_qs = qs;
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return GNUNET_SYSERR;
    }
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_bad_amount_out_plus),
                          &TALER_ARL_USE_AB (total_bad_amount_out_plus),
                          &roi->details.amount);
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_bad_amount_out_minus),
                          &TALER_ARL_USE_AB (total_bad_amount_out_minus),
                          amount);
    GNUNET_assert (GNUNET_OK ==
                   free_roi (NULL,
                             &key,
                             roi));
    return GNUNET_OK;
  }

  if (0 != TALER_amount_cmp (&roi->details.amount,
                             amount))
  {
    struct TALER_AUDITORDB_WireOutInconsistency woi = {
      .destination_account = np,
      .diagnostic = "wire amount does not match",
      .wire_out_row_id = rowid,
      .expected = *amount,
      .claimed = roi->details.amount,
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = TALER_ARL_adb->insert_wire_out_inconsistency (
      TALER_ARL_adb->cls,
      &woi);
    GNUNET_free (np);
    if (qs < 0)
    {
      global_qs = qs;
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return GNUNET_SYSERR;
    }
    if (0 < TALER_amount_cmp (amount,
                              &roi->details.amount))
    {
      /* amount > roi->details.amount: wire transfer was smaller than it should have been */
      struct TALER_Amount delta;

      TALER_ARL_amount_subtract (&delta,
                                 amount,
                                 &roi->details.amount);
      TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_bad_amount_out_minus),
                            &TALER_ARL_USE_AB (total_bad_amount_out_minus),
                            &delta);
    }
    else
    {
      /* roi->details.amount < amount: wire transfer was larger than it should have been */
      struct TALER_Amount delta;

      TALER_ARL_amount_subtract (&delta,
                                 &roi->details.amount,
                                 amount);
      TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_bad_amount_out_plus),
                            &TALER_ARL_USE_AB (total_bad_amount_out_plus),
                            &delta);
    }
    GNUNET_assert (GNUNET_OK ==
                   free_roi (NULL,
                             &key,
                             roi));
    return GNUNET_OK;
  }

  {
    enum GNUNET_GenericReturnValue ret;

    if (! check_time_difference ("wire_out",
                                 rowid,
                                 date,
                                 roi->details.execution_date))
    {
      /* We had a database error, fail */
      ret = GNUNET_SYSERR;
    }
    else
    {
      ret = GNUNET_OK;
    }
    GNUNET_assert (GNUNET_OK ==
                   free_roi (NULL,
                             &key,
                             roi));
    GNUNET_free (np);
    return ret;
  }
}


/**
 * Main function for processing 'reserves_out' data.  We start by going over
 * the DEBIT transactions this time, and then verify that all of them are
 * justified by 'reserves_out'.
 *
 * @param[in,out] wa wire account list to process
 */
static void
process_debits (struct WireAccount *wa);


/**
 * Go over the "wire_out" table of the exchange and
 * verify that all wire outs are in that table.
 *
 * @param[in,out] wa wire account we are processing
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
    wa->last_wire_out_serial_id,
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
history_debit_cb (
  void *cls,
  const struct TALER_BANK_DebitHistoryResponse *dhr);


/**
 * Task scheduled to begin long-polling on the
 * bank transfer.
 *
 * @param cls a `struct WireAccount *`
 */
static void
dh_long_poll (void *cls)
{
  struct WireAccount *wa = cls;

  wa->dhh_task = NULL;
  wa->dhh_next
    = GNUNET_TIME_relative_to_absolute (MIN_LONGPOLL_DELAY);
  GNUNET_assert (NULL == wa->dhh);
  wa->dhh = TALER_BANK_debit_history (
    ctx,
    wa->ai->auth,
    wa->wire_off_out,
    MAX_PER_TRANSACTION,
    MAX_LONGPOLL_DELAY,
    &history_debit_cb,
    wa);
  if (NULL == wa->dhh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to start long-polling for bank transaction history for `%s'\n",
                wa->ai->section_name);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


static void
history_debit_cb (
  void *cls,
  const struct TALER_BANK_DebitHistoryResponse *dhr)
{
  struct WireAccount *wa = cls;
  struct ReserveOutInfo *roi;
  size_t slen;

  wa->dhh = NULL;
  if ( (MHD_HTTP_OK == dhr->http_status) &&
       (0 != dhr->details.ok.details_length) )
  {
    /* As we got results, we go again *immediately* */
    wa->dhh_next = GNUNET_TIME_UNIT_ZERO_ABS;
  }
  GNUNET_assert (NULL == wa->dhh_task);
  wa->dhh_task
    = GNUNET_SCHEDULER_add_at (wa->dhh_next,
                               &dh_long_poll,
                               wa);
  switch (dhr->http_status)
  {
  case MHD_HTTP_OK:
    for (unsigned int i = 0; i < dhr->details.ok.details_length; i++)
    {
      const struct TALER_BANK_DebitDetails *dd
        = &dhr->details.ok.details[i];
      char *np = TALER_payto_normalize (dd->credit_account_uri);

      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Analyzing bank DEBIT #%llu at %s of %s with WTID %s\n",
                  (unsigned long long) dd->serial_id,
                  GNUNET_TIME_timestamp2s (dd->execution_date),
                  TALER_amount2s (&dd->amount),
                  TALER_B2S (&dd->wtid));
      wa->wire_off_out = dd->serial_id + 1;
      slen = strlen (np) + 1;
      roi = GNUNET_malloc (sizeof (struct ReserveOutInfo)
                           + slen);
      GNUNET_CRYPTO_hash (&dd->wtid,
                          sizeof (dd->wtid),
                          &roi->subject_hash);
      roi->details = *dd;
      roi->details.credit_account_uri
        = (const char *) &roi[1];
      GNUNET_memcpy (&roi[1],
                     np,
                     slen);
      GNUNET_free (np);
      if (GNUNET_OK !=
          GNUNET_CONTAINER_multihashmap_put (out_map,
                                             &roi->subject_hash,
                                             roi,
                                             GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY))
      {
        struct TALER_AUDITORDB_WireFormatInconsistency wfi = {
          .amount = dd->amount,
          .wire_offset = dd->serial_id,
          .diagnostic = "duplicate outgoing wire transfer subject"
        };
        enum GNUNET_DB_QueryStatus qs;

        qs = TALER_ARL_adb->insert_wire_format_inconsistency (
          TALER_ARL_adb->cls,
          &wfi);
        if (qs < 0)
        {
          global_qs = qs;
          GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
          commit (qs);
          return;
        }
        TALER_ARL_amount_add (&TALER_ARL_USE_AB (
                                wire_debit_duplicate_transfer_subject_total),
                              &TALER_ARL_USE_AB (
                                wire_debit_duplicate_transfer_subject_total),
                              &dd->amount);
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
  return;
}


static void
process_debits (struct WireAccount *wa)
{
  /* skip accounts where DEBIT is not enabled */
  while ( (NULL != wa) &&
          (! wa->ai->debit_enabled) )
    wa = wa->next;
  if (NULL == wa)
  {
    /* end of iteration */
    commit (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT);
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Checking bank DEBIT records of account `%s'\n",
              wa->ai->section_name);
  if ( (NULL == wa->dhh) &&
       (NULL == wa->dhh_task) )
  {
    wa->dhh = TALER_BANK_debit_history (
      ctx,
      wa->ai->auth,
      wa->wire_off_out,
      MAX_PER_TRANSACTION,
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
}


/**
 * Function called about reserve closing operations the aggregator triggered.
 *
 * @param cls closure; NULL
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
reserve_closed_cb (
  void *cls,
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
  GNUNET_assert (TALER_ARL_USE_PP (wire_reserve_close_id) <= rowid);
  TALER_ARL_USE_PP (wire_reserve_close_id) = rowid + 1;
  rc = GNUNET_new (struct ReserveClosure);
  if (TALER_ARL_SR_INVALID_NEGATIVE ==
      TALER_ARL_amount_subtract_neg (&rc->amount,
                                     amount_with_fee,
                                     closing_fee))
  {
    struct TALER_AUDITORDB_RowInconsistency ri = {
      .row_id = rowid,
      .row_table = "reserves_closures",
      .diagnostic = "closing fee above reserve balance (and closed anyway)"
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = TALER_ARL_adb->insert_row_inconsistency (
      TALER_ARL_adb->cls,
      &ri);
    if (qs < 0)
    {
      global_qs = qs;
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return GNUNET_OK;
    }
    GNUNET_free (rc);
    return GNUNET_OK;
  }
  rc->receiver_account = TALER_payto_normalize (receiver_account);
  rc->wtid = *wtid;
  rc->execution_date = execution_date;
  rc->rowid = rowid;
  hash_rc (rc->receiver_account,
           wtid,
           &key);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Discovered reserve closure %llu (%s) over %s benefiting %s\n",
              (unsigned long long) rowid,
              GNUNET_h2s (&key),
              TALER_amount2s (amount_with_fee),
              receiver_account);
  (void) GNUNET_CONTAINER_multihashmap_put (
    reserve_closures,
    &key,
    rc,
    GNUNET_CONTAINER_MULTIHASHMAPOPTION_MULTIPLE);
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
  global_qs = GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  if (GNUNET_OK !=
      TALER_ARL_adb->start (TALER_ARL_adb->cls))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_OK !=
      TALER_ARL_edb->start_read_only (TALER_ARL_edb->cls,
                                      "wire debit auditor"))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  qs = TALER_ARL_adb->get_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_GET_AB (total_drained),
    TALER_ARL_GET_AB (total_wire_out),
    TALER_ARL_GET_AB (total_bad_amount_out_plus),
    TALER_ARL_GET_AB (total_bad_amount_out_minus),
    TALER_ARL_GET_AB (total_closure_amount_lag),
    TALER_ARL_GET_AB (wire_debit_duplicate_transfer_subject_total),
    TALER_ARL_GET_AB (total_wire_out),
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
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break;
  }
  for (struct WireAccount *wa = wa_head;
       NULL != wa;
       wa = wa->next)
  {
    GNUNET_asprintf (&wa->label_wire_out_serial_id,
                     "wire-%s-%s",
                     wa->ai->section_name,
                     "wire_out_serial_id");
    GNUNET_asprintf (&wa->label_wire_off_out,
                     "wire-%s-%s",
                     wa->ai->section_name,
                     "wire_off_out");
    qs = TALER_ARL_adb->get_auditor_progress (
      TALER_ARL_adb->cls,
      wa->label_wire_out_serial_id,
      &wa->last_wire_out_serial_id,
      wa->label_wire_off_out,
      &wa->wire_off_out,
      NULL);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return qs;
    }
    GNUNET_assert (2 == qs);
    wa->start_wire_out_serial_id = wa->last_wire_out_serial_id;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Resuming account %s debit audit at %llu/%llu\n",
                wa->ai->section_name,
                (unsigned long long) wa->last_wire_out_serial_id,
                (unsigned long long) wa->wire_off_out);
  }
  qs = TALER_ARL_adb->get_auditor_progress (
    TALER_ARL_adb->cls,
    TALER_ARL_GET_PP (wire_reserve_close_id),
    NULL);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "First analysis of with wire auditor, starting audit from scratch\n");
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Resuming wire debit audit at %llu\n",
                (unsigned long long) TALER_ARL_USE_PP (wire_reserve_close_id));
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Iterating over reserve closures from %llu\n",
              (unsigned long long) TALER_ARL_USE_PP (wire_reserve_close_id));
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
  process_debits (wa_head);
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
 * Function called on events received from Postgres.
 *
 * @param cls closure, NULL
 * @param extra additional event data provided
 * @param extra_size number of bytes in @a extra
 */
static void
db_notify (void *cls,
           const void *extra,
           size_t extra_size)
{
  (void) cls;
  (void) extra;
  (void) extra_size;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received notification to wake wire helper\n");
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
      begin_transaction ())
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Audit failed\n");
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
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
  cfg = c;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Launching wire auditor\n");
  if (GNUNET_OK !=
      TALER_ARL_init (c))
  {
    global_ret = EXIT_FAILURE;
    return;
  }

  reserve_closures
    = GNUNET_CONTAINER_multihashmap_create (1024,
                                            GNUNET_NO);
  if (GNUNET_OK !=
      TALER_config_get_amount (TALER_ARL_cfg,
                               "auditor",
                               "TINY_AMOUNT",
                               &tiny_amount))
  {
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &zero));
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &rctx);
  rctx = GNUNET_CURL_gnunet_rc_create (ctx);
  if (NULL == ctx)
  {
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    return;
  }
  reserve_closures = GNUNET_CONTAINER_multihashmap_create (1024,
                                                           GNUNET_NO);
  out_map = GNUNET_CONTAINER_multihashmap_create (1024,
                                                  true);
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
    return;
  }
  TALER_EXCHANGEDB_find_accounts (&process_account_cb,
                                  NULL);

  if (0 == test_mode)
  {
    struct GNUNET_DB_EventHeaderP es = {
      .size = htons (sizeof (es)),
      .type = htons (TALER_DBEVENT_EXCHANGE_AUDITOR_WAKE_HELPER_WIRE)
    };

    eh = TALER_ARL_adb->event_listen (TALER_ARL_adb->cls,
                                      &es,
                                      GNUNET_TIME_UNIT_FOREVER_REL,
                                      &db_notify,
                                      NULL);
    GNUNET_assert (NULL != eh);
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
      begin_transaction ())
  {
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
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
    "taler-helper-auditor-wire-debit",
    gettext_noop (
      "Audit exchange database for consistency with the bank's outgoing wire transfers"),
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


/* end of taler-helper-auditor-wire-debit.c */
