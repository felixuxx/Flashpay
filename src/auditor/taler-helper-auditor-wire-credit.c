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
 * @file auditor/taler-helper-auditor-wire-credit.c
 * @brief audits that wire transfers match those from an exchange database.
 * @author Christian Grothoff
 *
 * This auditor verifies that 'reserves_in' actually matches
 * the incoming wire transfers from the bank.
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
 * How much time do we allow the aggregator to lag behind?  If
 * wire transfers should have been made more than #GRACE_PERIOD
 * before, we issue warnings.
 */
#define GRACE_PERIOD GNUNET_TIME_UNIT_HOURS

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
#define TIME_TOLERANCE GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MINUTES, \
                                                      15)


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
  struct TALER_BANK_CreditHistoryHandle *chh;

  /**
   * Progress point for this account.
   */
  uint64_t last_reserve_in_serial_id;

  /**
   * Initial progress point for this account.
   */
  uint64_t start_reserve_in_serial_id;

  /**
   * Where we are in the inbound transaction history.
   */
  uint64_t wire_off_in;

  /**
   * Label under which we store our pp's reserve_in_serial_id.
   */
  char *label_reserve_in_serial_id;

  /**
   * Label under which we store our wire_off_in.
   */
  char *label_wire_off_in;

};


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
 * Map with information about incoming wire transfers.
 * Maps hashes of the wire offsets to `struct ReserveInInfo`s.
 */
static struct GNUNET_CONTAINER_MultiHashMap *in_map;

/**
 * Head of list of wire accounts we still need to look at.
 */
static struct WireAccount *wa_head;

/**
 * Tail of list of wire accounts we still need to look at.
 */
static struct WireAccount *wa_tail;

/**
 * Last reserve_in seen.
 */
// static TALER_ARL_DEF_PP (wire_reserve_in_id); // FIXME: new!

/**
 * Amount that is considered "tiny"
 */
static struct TALER_Amount tiny_amount;

/**
 * Total amount that was transferred too much to the exchange.
 */
static TALER_ARL_DEF_AB (total_bad_amount_in_plus);

/**
 * Total amount that was transferred too little to the exchange.
 */
static TALER_ARL_DEF_AB (total_bad_amount_in_minus);

/**
 * Total amount where the exchange has the wrong sender account
 * for incoming funds and may thus wire funds to the wrong
 * destination when closing the reserve.
 */
static TALER_ARL_DEF_AB (total_misattribution_in);

/**
 * Total amount affected by wire format troubles.
 */
static TALER_ARL_DEF_AB (total_wire_format_amount); // FIXME

/**
 * Total amount credited to exchange accounts.
 */
static TALER_ARL_DEF_AB (total_wire_in);

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

// FIXME: comment
static struct GNUNET_DB_EventHandler *eh;

/**
 * The auditors's configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;

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
  struct TALER_BANK_CreditDetails credit_details;

  /**
   * RowID in reserves_in table.
   */
  uint64_t rowid;

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
  if (NULL != in_map)
  {
    GNUNET_CONTAINER_multihashmap_iterate (in_map,
                                           &free_rii,
                                           NULL);
    GNUNET_CONTAINER_multihashmap_destroy (in_map);
    in_map = NULL;
  }
  while (NULL != (wa = wa_head))
  {
    if (NULL != wa->chh)
    {
      TALER_BANK_credit_history_cancel (wa->chh);
      wa->chh = NULL;
    }
    GNUNET_CONTAINER_DLL_remove (wa_head,
                                 wa_tail,
                                 wa);
    GNUNET_free (wa->label_reserve_in_serial_id);
    GNUNET_free (wa->label_wire_off_in);
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
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Transaction logic ended with status %d\n",
              qs);
  if (qs < 0)
    goto handle_db_error;
  qs = TALER_ARL_adb->update_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_AB (total_wire_in),
    TALER_ARL_SET_AB (total_bad_amount_in_plus),
    TALER_ARL_SET_AB (total_bad_amount_in_minus),
    TALER_ARL_SET_AB (total_misattribution_in),
    TALER_ARL_SET_AB (total_wire_format_amount),
    NULL);
  if (0 > qs)
    goto handle_db_error;
  qs = TALER_ARL_adb->insert_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_AB (total_wire_in),
    TALER_ARL_SET_AB (total_bad_amount_in_plus),
    TALER_ARL_SET_AB (total_bad_amount_in_minus),
    TALER_ARL_SET_AB (total_misattribution_in),
    TALER_ARL_SET_AB (total_wire_format_amount),
    NULL);
  if (0 > qs)
    goto handle_db_error;
  for (struct WireAccount *wa = wa_head;
       NULL != wa;
       wa = wa->next)
  {
    qs = TALER_ARL_adb->update_auditor_progress (
      TALER_ARL_adb->cls,
      wa->label_reserve_in_serial_id,
      wa->last_reserve_in_serial_id,
      wa->label_wire_off_in,
      wa->wire_off_in,
      NULL);
    if (0 > qs)
      goto handle_db_error;
    qs = TALER_ARL_adb->insert_auditor_progress (
      TALER_ARL_adb->cls,
      wa->label_reserve_in_serial_id,
      wa->last_reserve_in_serial_id,
      wa->label_wire_off_in,
      wa->wire_off_in,
      NULL);
    if (0 > qs)
      goto handle_db_error;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Transaction ends at %s=%llu for account `%s'\n",
                wa->label_reserve_in_serial_id,
                (unsigned long long) wa->last_reserve_in_serial_id,
                wa->ai->section_name);
  }
  qs = TALER_ARL_edb->commit (TALER_ARL_edb->cls);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Exchange DB commit failed, rolling back transaction\n");
    goto handle_db_error;
  }
  qs = TALER_ARL_adb->commit (TALER_ARL_adb->cls);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    goto handle_db_error;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Transaction concluded!\n");
  if (1 == test_mode)
    GNUNET_SCHEDULER_shutdown ();
  return;
handle_db_error:
  TALER_ARL_adb->rollback (TALER_ARL_adb->cls);
  TALER_ARL_edb->rollback (TALER_ARL_edb->cls);
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
 * Conclude the credit history check by logging entries that
 * were not found and freeing resources. Then move on to
 * processing debits.
 */
static void
conclude_credit_history (void)
{
  // FIXME: what about entries that are left in in_map?
  if (NULL != in_map)
  {
    GNUNET_CONTAINER_multihashmap_destroy (in_map);
    in_map = NULL;
  }
  commit (global_qs);
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
  char *snp;

  snp = TALER_payto_normalize (sender_account_details);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Analyzing exchange wire IN (%llu) at %s of %s with reserve_pub %s\n",
              (unsigned long long) rowid,
              GNUNET_TIME_timestamp2s (execution_date),
              TALER_amount2s (credit),
              TALER_B2S (reserve_pub));
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_wire_in),
                        &TALER_ARL_USE_AB (total_wire_in),
                        credit);
  slen = strlen (snp) + 1;
  rii = GNUNET_malloc (sizeof (struct ReserveInInfo) + slen);
  rii->rowid = rowid;
  rii->credit_details.type = TALER_BANK_CT_RESERVE;
  rii->credit_details.amount = *credit;
  rii->credit_details.execution_date = execution_date;
  rii->credit_details.details.reserve.reserve_pub = *reserve_pub;
  rii->credit_details.debit_account_uri = (const char *) &rii[1];
  GNUNET_memcpy (&rii[1],
                 snp,
                 slen);
  GNUNET_free (snp);
  GNUNET_CRYPTO_hash (&wire_reference,
                      sizeof (uint64_t),
                      &rii->row_off_hash);
  if (GNUNET_OK !=
      GNUNET_CONTAINER_multihashmap_put (in_map,
                                         &rii->row_off_hash,
                                         rii,
                                         GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY))
  {
    struct TALER_AUDITORDB_RowInconsistency ri = {
      .row_id = rowid,
      .row_table = "reserves_in",
      .diagnostic = "duplicate wire offset"
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = TALER_ARL_adb->insert_row_inconsistency (
      TALER_ARL_adb->cls,
      &ri);
    GNUNET_free (rii);
    if (qs < 0)
    {
      global_qs = qs;
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return GNUNET_SYSERR;
    }
    return GNUNET_OK;
  }
  wa->last_reserve_in_serial_id = rowid + 1;
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
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_AUDITORDB_ReserveInInconsistency riiDb = {
    .bank_row_id = rii->rowid,
    .diagnostic = "incoming wire transfer claimed by exchange not found",
    .account = (char *) wa->ai->section_name,
    .amount_exchange_expected = rii->credit_details.amount,
    .amount_wired = zero,
    .reserve_pub = rii->credit_details.details.reserve.reserve_pub,
    .timestamp = rii->credit_details.execution_date.abs_time
  };

  (void) key;
  GNUNET_assert (TALER_BANK_CT_RESERVE ==
                 rii->credit_details.type);
  qs = TALER_ARL_adb->insert_reserve_in_inconsistency (
    TALER_ARL_adb->cls,
    &riiDb);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    global_qs = qs;
    return GNUNET_SYSERR;
  }
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_bad_amount_in_minus),
                        &TALER_ARL_USE_AB (total_bad_amount_in_minus),
                        &rii->credit_details.amount);
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
    if (global_qs < 0)
    {
      commit (global_qs);
      return;
    }
  }
  process_credits (wa->next);
}


/**
 * Analyze credit transaction @a details into @a wa.
 *
 * @param[in,out] wa account that received the transfer
 * @param credit_details transfer details
 * @return true on success, false to stop loop at this point
 */
static bool
analyze_credit (
  struct WireAccount *wa,
  const struct TALER_BANK_CreditDetails *credit_details)
{
  struct ReserveInInfo *rii;
  struct GNUNET_HashCode key;

  GNUNET_assert (TALER_BANK_CT_RESERVE ==
                 credit_details->type);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Analyzing bank CREDIT #%llu at %s of %s with Reserve-pub %s\n",
              (unsigned long long) credit_details->serial_id,
              GNUNET_TIME_timestamp2s (credit_details->execution_date),
              TALER_amount2s (&credit_details->amount),
              TALER_B2S (&credit_details->details.reserve.reserve_pub));
  GNUNET_CRYPTO_hash (&credit_details->serial_id,
                      sizeof (credit_details->serial_id),
                      &key);
  rii = GNUNET_CONTAINER_multihashmap_get (in_map,
                                           &key);
  if (NULL == rii)
  {
    // FIXME: probably should instead add to
    // auditor DB and report missing! (& continue!)
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to find wire transfer at `%s' in exchange database. Audit ends at this point in time.\n",
                GNUNET_TIME_timestamp2s (credit_details->execution_date));
    process_credits (wa->next);
    return false; /* not an error, just end of processing */
  }

  /* Update offset */
  wa->wire_off_in = credit_details->serial_id;
  /* compare records with expected data */
  if (0 != GNUNET_memcmp (&credit_details->details.reserve.reserve_pub,
                          &rii->credit_details.details.reserve.reserve_pub))
  {
    struct TALER_AUDITORDB_ReserveInInconsistency riiDb = {
      .diagnostic = "wire subject does not match",
      .account = (char *) wa->ai->section_name,
      .bank_row_id = credit_details->serial_id,
      .amount_exchange_expected = rii->credit_details.amount,
      .amount_wired = zero,
      .reserve_pub = rii->credit_details.details.reserve.reserve_pub,
      .timestamp = rii->credit_details.execution_date.abs_time
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = TALER_ARL_adb->insert_reserve_in_inconsistency (
      TALER_ARL_adb->cls,
      &riiDb);
    if (qs <= 0)
    {
      global_qs = qs;
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return false;
    }
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_bad_amount_in_minus),
                          &TALER_ARL_USE_AB (total_bad_amount_in_minus),
                          &rii->credit_details.amount);
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_bad_amount_in_plus),
                          &TALER_ARL_USE_AB (total_bad_amount_in_plus),
                          &credit_details->amount);
    GNUNET_assert (GNUNET_OK ==
                   free_rii (NULL,
                             &key,
                             rii));
    return true;
  }
  if (0 != TALER_amount_cmp (&rii->credit_details.amount,
                             &credit_details->amount))
  {
    struct TALER_AUDITORDB_ReserveInInconsistency riiDb = {
      .diagnostic = "wire amount does not match",
      .account = (char *) wa->ai->section_name,
      .bank_row_id = credit_details->serial_id,
      .amount_exchange_expected = rii->credit_details.amount,
      .amount_wired = credit_details->amount,
      .reserve_pub = rii->credit_details.details.reserve.reserve_pub,
      .timestamp = rii->credit_details.execution_date.abs_time
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = TALER_ARL_adb->insert_reserve_in_inconsistency (
      TALER_ARL_adb->cls,
      &riiDb);
    if (qs <= 0)
    {
      global_qs = qs;
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return false;
    }
    if (0 < TALER_amount_cmp (&credit_details->amount,
                              &rii->credit_details.amount))
    {
      /* details->amount > rii->details.amount: wire transfer was larger than it should have been */
      struct TALER_Amount delta;

      TALER_ARL_amount_subtract (&delta,
                                 &credit_details->amount,
                                 &rii->credit_details.amount);
      TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_bad_amount_in_plus),
                            &TALER_ARL_USE_AB (total_bad_amount_in_plus),
                            &delta);
    }
    else
    {
      /* rii->details.amount < details->amount: wire transfer was smaller than it should have been */
      struct TALER_Amount delta;

      TALER_ARL_amount_subtract (&delta,
                                 &rii->credit_details.amount,
                                 &credit_details->amount);
      TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_bad_amount_in_minus),
                            &TALER_ARL_USE_AB (total_bad_amount_in_minus),
                            &delta);
    }
  }

  {
    char *np;

    np = TALER_payto_normalize (credit_details->debit_account_uri);
    if (0 != strcasecmp (np,
                         rii->credit_details.debit_account_uri))
    {
      struct TALER_AUDITORDB_MisattributionInInconsistency mii = {
        .reserve_pub = rii->credit_details.details.reserve.reserve_pub,
        .amount = rii->credit_details.amount,
        .bank_row = credit_details->serial_id
      };
      enum GNUNET_DB_QueryStatus qs;

      qs = TALER_ARL_adb->insert_misattribution_in_inconsistency (
        TALER_ARL_adb->cls,
        &mii);
      if (qs <= 0)
      {
        global_qs = qs;
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        GNUNET_free (np);
        return false;
      }
      TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_misattribution_in),
                            &TALER_ARL_USE_AB (total_misattribution_in),
                            &rii->credit_details.amount);
    }
    GNUNET_free (np);
  }
  if (GNUNET_TIME_timestamp_cmp (credit_details->execution_date,
                                 !=,
                                 rii->credit_details.execution_date))
  {
    struct TALER_AUDITORDB_RowMinorInconsistencies rmi = {
      .row_id = rii->rowid,
      .diagnostic = "execution date mismatch",
      .row_table = "reserves_in"
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = TALER_ARL_adb->insert_row_minor_inconsistencies (
      TALER_ARL_adb->cls,
      &rmi);

    if (qs <= 0)
    {
      global_qs = qs;
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return false;
    }
  }
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
    for (unsigned int i = 0; i < chr->details.ok.details_length; i++)
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
    wa->last_reserve_in_serial_id,
    &reserve_in_cb,
    wa);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting bank CREDIT history of account `%s'\n",
              wa->ai->section_name);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "user `%s'\n",
              wa->ai->auth->details.basic.username);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "pass `%s'\n",
              wa->ai->auth->details.basic.password);
  wa->chh = TALER_BANK_credit_history (ctx,
                                       wa->ai->auth,
                                       wa->wire_off_in,
                                       MAX_PER_TRANSACTION,
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
  TALER_ARL_edb->preflight (TALER_ARL_edb->cls);
  if (GNUNET_OK !=
      TALER_ARL_edb->start (TALER_ARL_edb->cls,
                            "wire credit auditor"))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  qs = TALER_ARL_adb->get_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_GET_AB (total_wire_in),
    TALER_ARL_GET_AB (total_bad_amount_in_plus),
    TALER_ARL_GET_AB (total_bad_amount_in_minus),
    TALER_ARL_GET_AB (total_misattribution_in),
    TALER_ARL_GET_AB (total_wire_format_amount),
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
    GNUNET_asprintf (&wa->label_reserve_in_serial_id,
                     "wire-%s-%s",
                     wa->ai->section_name,
                     "reserve_in_serial_id");
    GNUNET_asprintf (&wa->label_wire_off_in,
                     "wire-%s-%s",
                     wa->ai->section_name,
                     "wire_off_in");
    qs = TALER_ARL_adb->get_auditor_progress (
      TALER_ARL_adb->cls,
      wa->label_reserve_in_serial_id,
      &wa->last_reserve_in_serial_id,
      wa->label_wire_off_in,
      &wa->wire_off_in,
      NULL);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return qs;
    }
    wa->start_reserve_in_serial_id = wa->last_reserve_in_serial_id;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Starting from reserve_in at %s=%llu for account `%s'\n",
                wa->label_reserve_in_serial_id,
                (unsigned long long) wa->start_reserve_in_serial_id,
                wa->ai->section_name);
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
  if ((! ai->debit_enabled) &&
      (! ai->credit_enabled))
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
              "Launching wire-credit auditor\n");
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
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &zero));
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
  if (GNUNET_OK !=
      TALER_EXCHANGEDB_load_accounts (TALER_ARL_cfg,
                                      TALER_EXCHANGEDB_ALO_CREDIT
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
    "taler-helper-auditor-wire-credit",
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


/* end of taler-helper-auditor-wire-credit.c */
