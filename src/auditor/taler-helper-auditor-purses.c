/*
  This file is part of TALER
  Copyright (C) 2016-2022 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero Public License for more details.

  You should have received a copy of the GNU Affero Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file auditor/taler-helper-auditor-purses.c
 * @brief audits the purses of an exchange database
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_auditordb_plugin.h"
#include "taler_exchangedb_lib.h"
#include "taler_json_lib.h"
#include "taler_bank_service.h"
#include "taler_signatures.h"
#include "report-lib.h"


/**
 * Use a 1 day grace period to deal with clocks not being perfectly synchronized.
 */
#define EXPIRATION_GRACE_PERIOD GNUNET_TIME_UNIT_DAYS

/**
 * Return value from main().
 */
static int global_ret;

/**
 * Checkpointing our progress for purses.
 */
static struct TALER_AUDITORDB_ProgressPointPurse ppp;

/**
 * Checkpointing our progress for purses.
 */
static struct TALER_AUDITORDB_ProgressPointPurse ppp_start;

/**
 * Global statistics about purses.
 */
static struct TALER_AUDITORDB_PurseBalance balance;

/**
 * Array of reports about row inconsitencies.
 */
static json_t *report_row_inconsistencies;

/**
 * Array of reports about purse balance insufficient inconsitencies.
 */
static json_t *report_purse_balance_insufficient_inconsistencies;

/**
 * Total amount purses were merged with insufficient balance.
 */
static struct TALER_Amount total_balance_insufficient_loss;

/**
 * Total amount purse decisions are delayed past deadline.
 */
static struct TALER_Amount total_delayed_decisions;

/**
 * Array of reports about purses's not being closed inconsitencies.
 */
static json_t *report_purse_not_closed_inconsistencies;

/**
 * Total amount affected by purses not having been closed on time.
 */
static struct TALER_Amount total_balance_purse_not_closed;

/**
 * Report about amount calculation differences (causing profit
 * or loss at the exchange).
 */
static json_t *report_amount_arithmetic_inconsistencies;

/**
 * Profits the exchange made by bad amount calculations.
 */
static struct TALER_Amount total_arithmetic_delta_plus;

/**
 * Losses the exchange made by bad amount calculations.
 */
static struct TALER_Amount total_arithmetic_delta_minus;

/**
 * Array of reports about coin operations with bad signatures.
 */
static json_t *report_bad_sig_losses;

/**
 * Total amount lost by operations for which signatures were invalid.
 */
static struct TALER_Amount total_bad_sig_loss;

/**
 * Should we run checks that only work for exchange-internal audits?
 */
static int internal_checks;

/* ***************************** Report logic **************************** */


/**
 * Report a (serious) inconsistency in the exchange's database with
 * respect to calculations involving amounts.
 *
 * @param operation what operation had the inconsistency
 * @param rowid affected row, 0 if row is missing
 * @param exchange amount calculated by exchange
 * @param auditor amount calculated by auditor
 * @param profitable 1 if @a exchange being larger than @a auditor is
 *           profitable for the exchange for this operation,
 *           -1 if @a exchange being smaller than @a auditor is
 *           profitable for the exchange, and 0 if it is unclear
 */
static void
report_amount_arithmetic_inconsistency (
  const char *operation,
  uint64_t rowid,
  const struct TALER_Amount *exchange,
  const struct TALER_Amount *auditor,
  int profitable)
{
  struct TALER_Amount delta;
  struct TALER_Amount *target;

  if (0 < TALER_amount_cmp (exchange,
                            auditor))
  {
    /* exchange > auditor */
    TALER_ARL_amount_subtract (&delta,
                               exchange,
                               auditor);
  }
  else
  {
    /* auditor < exchange */
    profitable = -profitable;
    TALER_ARL_amount_subtract (&delta,
                               auditor,
                               exchange);
  }
  TALER_ARL_report (report_amount_arithmetic_inconsistencies,
                    GNUNET_JSON_PACK (
                      GNUNET_JSON_pack_string ("operation",
                                               operation),
                      GNUNET_JSON_pack_uint64 ("rowid",
                                               rowid),
                      TALER_JSON_pack_amount ("exchange",
                                              exchange),
                      TALER_JSON_pack_amount ("auditor",
                                              auditor),
                      GNUNET_JSON_pack_int64 ("profitable",
                                              profitable)));
  if (0 != profitable)
  {
    target = (1 == profitable)
        ? &total_arithmetic_delta_plus
        : &total_arithmetic_delta_minus;
    TALER_ARL_amount_add (target,
                          target,
                          &delta);
  }
}


/**
 * Report a (serious) inconsistency in the exchange's database.
 *
 * @param table affected table
 * @param rowid affected row, 0 if row is missing
 * @param diagnostic message explaining the problem
 */
static void
report_row_inconsistency (const char *table,
                          uint64_t rowid,
                          const char *diagnostic)
{
  TALER_ARL_report (report_row_inconsistencies,
                    GNUNET_JSON_PACK (
                      GNUNET_JSON_pack_string ("table",
                                               table),
                      GNUNET_JSON_pack_uint64 ("row",
                                               rowid),
                      GNUNET_JSON_pack_string ("diagnostic",
                                               diagnostic)));
}


/**
 * Obtain the purse fee for a purse created at @a time.
 *
 * @param atime when was the purse created
 * @param[out] fee set to the purse fee
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
get_purse_fee (struct GNUNET_TIME_Timestamp atime,
               struct TALER_Amount *fee)
{
  struct TALER_MasterSignatureP master_sig;
  struct GNUNET_TIME_Timestamp start_date;
  struct GNUNET_TIME_Timestamp end_date;
  struct TALER_GlobalFeeSet fees;
  struct GNUNET_TIME_Relative ptimeout;
  struct GNUNET_TIME_Relative ktimeout;
  struct GNUNET_TIME_Relative hexp;
  uint32_t pacl;

  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      TALER_ARL_edb->get_global_fee (TALER_ARL_edb->cls,
                                     atime,
                                     &start_date,
                                     &end_date,
                                     &fees,
                                     &ptimeout,
                                     &ktimeout,
                                     &hexp,
                                     &pacl,
                                     &master_sig))
  {
    char *diag;

    GNUNET_asprintf (&diag,
                     "purse fee unavailable at %s\n",
                     GNUNET_TIME_timestamp2s (atime));
    report_row_inconsistency ("purse-fee",
                              atime.abs_time.abs_value_us,
                              diag);
    GNUNET_free (diag);
    return GNUNET_SYSERR;
  }
  *fee = fees.purse;
  return GNUNET_OK;
}


/* ***************************** Analyze purses ************************ */
/* This logic checks the purses_requests, purse_deposits,
   purse_refunds, purse_merges and account_merges */

/**
 * Summary data we keep per purse.
 */
struct PurseSummary
{
  /**
   * Public key of the purse.
   * Always set when the struct is first initialized.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * Balance of the purse from deposits (includes purse fee, excludes deposit
   * fees), as calculated by auditor.
   */
  struct TALER_Amount balance;

  /**
   * Expected value of the purse, excludes purse fee.
   */
  struct TALER_Amount total_value;

  /**
   * Purse balance according to exchange DB.
   */
  struct TALER_Amount exchange_balance;

  /**
   * Contract terms of the purse.
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Merge timestamp (as per exchange DB).
   */
  struct GNUNET_TIME_Timestamp merge_timestamp;

  /**
   * Purse creation date.  This is when the merge
   * fee is applied.
   */
  struct GNUNET_TIME_Timestamp creation_date;

  /**
   * Purse expiration date.
   */
  struct GNUNET_TIME_Timestamp expiration_date;

  /**
   * Did we have a previous purse info?  Used to decide between UPDATE and
   * INSERT later.  Initialized in #load_auditor_purse_summary().
   */
  bool had_pi;

};


/**
 * Load the auditor's remembered state about the purse into @a ps.
 *
 * @param[in,out] ps purse summary to (fully) initialize
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
load_auditor_purse_summary (struct PurseSummary *ps)
{
  enum GNUNET_DB_QueryStatus qs;
  uint64_t rowid;

  qs = TALER_ARL_adb->get_purse_info (TALER_ARL_adb->cls,
                                      &ps->purse_pub,
                                      &TALER_ARL_master_pub,
                                      &rowid,
                                      &ps->balance,
                                      &ps->expiration_date);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    ps->had_pi = false;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (TALER_ARL_currency,
                                          &ps->balance));
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Creating fresh purse `%s'\n",
                TALER_B2S (&ps->purse_pub));
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }
  ps->had_pi = true;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Auditor remembers purse `%s' has balance %s\n",
              TALER_B2S (&ps->purse_pub),
              TALER_amount2s (&ps->balance));
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Closure to the various callbacks we make while checking a purse.
 */
struct PurseContext
{
  /**
   * Map from hash of purse's public key to a `struct PurseSummary`.
   */
  struct GNUNET_CONTAINER_MultiHashMap *purses;

  /**
   * Transaction status code, set to error codes if applicable.
   */
  enum GNUNET_DB_QueryStatus qs;

};


/**
 * Create a new reserve for @a reserve_pub in @a rc.
 *
 * @param[in,out] pc context to update
 * @param purse_pub key for which to create a purse
 * @return NULL on error
 */
static struct PurseSummary *
setup_purse (struct PurseContext *pc,
             const struct TALER_PurseContractPublicKeyP *purse_pub)
{
  struct PurseSummary *ps;
  struct GNUNET_HashCode key;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_CRYPTO_hash (purse_pub,
                      sizeof (*purse_pub),
                      &key);
  ps = GNUNET_CONTAINER_multihashmap_get (pc->purses,
                                          &key);
  if (NULL != ps)
    return ps;
  ps = GNUNET_new (struct PurseSummary);
  ps->purse_pub = *purse_pub;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &ps->balance));
  /* get purse meta-data from exchange DB */
  qs = TALER_ARL_edb->select_purse (TALER_ARL_edb->cls,
                                    purse_pub,
                                    &ps->creation_date,
                                    &ps->expiration_date,
                                    &ps->total_value,
                                    &ps->exchange_balance,
                                    &ps->h_contract_terms,
                                    &ps->merge_timestamp);
  if (0 >= qs)
  {
    GNUNET_free (ps);
    pc->qs = qs;
    return NULL;
  }
  if (0 > (qs = load_auditor_purse_summary (ps)))
  {
    GNUNET_free (ps);
    pc->qs = qs;
    return NULL;
  }
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONTAINER_multihashmap_put (pc->purses,
                                                    &key,
                                                    ps,
                                                    GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  return ps;
}


/**
 * Function called on purse requests.
 *
 * @param cls closure
 * @param purse_pub public key of the purse
 * @param merge_pub public key representing the merge capability
 * @param purse_expiration when would an unmerged purse expire
 * @param h_contract_terms contract associated with the purse
 * @param age_limit the age limit for deposits into the purse
 * @param target_amount amount to be put into the purse
 * @param purse_sig signature of the purse over the initialization data
 * @return #GNUNET_OK to continue to iterate
   */
static enum GNUNET_GenericReturnValue
handle_purse_requested (
  void *cls,
  uint64_t rowid,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  struct GNUNET_TIME_Timestamp purse_creation,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  uint32_t age_limit,
  const struct TALER_Amount *target_amount,
  const struct TALER_PurseContractSignatureP *purse_sig)
{
  struct PurseContext *pc = cls;
  struct PurseSummary *ps;
  struct GNUNET_HashCode key;

  if (GNUNET_OK !=
      TALER_wallet_purse_create_verify (purse_expiration,
                                        h_contract_terms,
                                        merge_pub,
                                        age_limit,
                                        target_amount,
                                        purse_pub,
                                        purse_sig))
  {
    TALER_ARL_report (report_bad_sig_losses,
                      GNUNET_JSON_PACK (
                        GNUNET_JSON_pack_string ("operation",
                                                 "purse-reqeust"),
                        GNUNET_JSON_pack_uint64 ("row",
                                                 rowid),
                        TALER_JSON_pack_amount ("loss",
                                                target_amount),
                        GNUNET_JSON_pack_data_auto ("key_pub",
                                                    purse_pub)));
    TALER_ARL_amount_add (&total_bad_sig_loss,
                          &total_bad_sig_loss,
                          target_amount);
  }
  GNUNET_CRYPTO_hash (purse_pub,
                      sizeof (*purse_pub),
                      &key);
  ps = GNUNET_new (struct PurseSummary);
  ps->purse_pub = *purse_pub;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &ps->balance));
  ps->creation_date = purse_creation;
  ps->expiration_date = purse_expiration;
  ps->total_value = *target_amount;
  ps->h_contract_terms = *h_contract_terms;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONTAINER_multihashmap_put (pc->purses,
                                                    &key,
                                                    ps,
                                                    GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  return GNUNET_OK;
}


/**
 * Function called with details about purse deposits that have been made, with
 * the goal of auditing the deposit's execution.
 *
 * @param cls closure
 * @param rowid unique serial ID for the deposit in our DB
 * @param deposit deposit details
 * @param reserve_pub which reserve is the purse merged into, NULL if unknown
 * @param flags purse flags
 * @param auditor_balance purse balance (according to the
 *          auditor during auditing)
 * @param purse_total target amount the purse should reach
 * @param denom_pub denomination public key of @a coin_pub
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
handle_purse_deposits (
  void *cls,
  uint64_t rowid,
  const struct TALER_EXCHANGEDB_PurseDeposit *deposit,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  enum TALER_WalletAccountMergeFlags flags,
  const struct TALER_Amount *auditor_balance,
  const struct TALER_Amount *purse_total,
  const struct TALER_DenominationPublicKey *denom_pub)
{
  struct PurseContext *pc = cls;
  struct TALER_Amount amount_minus_fee;
  struct PurseSummary *ps;
  const char *base_url
    = (NULL == deposit->exchange_base_url)
    ? TALER_ARL_exchange_url
    : deposit->exchange_base_url;
  struct TALER_DenominationHashP h_denom_pub;

  /* should be monotonically increasing */
  GNUNET_assert (rowid >= ppp.last_purse_deposits_serial_id);
  ppp.last_purse_deposits_serial_id = rowid + 1;

  {
    const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue;
    enum GNUNET_DB_QueryStatus qs;

    qs = TALER_ARL_get_denomination_info (denom_pub,
                                          &issue,
                                          &h_denom_pub);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Hard database error trying to get denomination %s from database!\n",
                    TALER_B2S (denom_pub));
      pc->qs = qs;
      return GNUNET_SYSERR;
    }
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      report_row_inconsistency ("purse-deposit",
                                rowid,
                                "denomination key not found");
      if (TALER_ARL_do_abort ())
        return GNUNET_SYSERR;
      return GNUNET_OK;
    }
    TALER_ARL_amount_subtract (&amount_minus_fee,
                               &deposit->amount,
                               &issue->fees.deposit);
  }

  if (GNUNET_OK !=
      TALER_wallet_purse_deposit_verify (base_url,
                                         &deposit->purse_pub,
                                         &deposit->amount,
                                         &h_denom_pub,
                                         &deposit->h_age_commitment,
                                         &deposit->coin_pub,
                                         &deposit->coin_sig))
  {
    TALER_ARL_report (report_bad_sig_losses,
                      GNUNET_JSON_PACK (
                        GNUNET_JSON_pack_string ("operation",
                                                 "purse-deposit"),
                        GNUNET_JSON_pack_uint64 ("row",
                                                 rowid),
                        TALER_JSON_pack_amount ("loss",
                                                &deposit->amount),
                        GNUNET_JSON_pack_data_auto ("key_pub",
                                                    &deposit->coin_pub)));
    TALER_ARL_amount_add (&total_bad_sig_loss,
                          &total_bad_sig_loss,
                          &deposit->amount);
    return GNUNET_OK;
  }

  ps = setup_purse (pc,
                    &deposit->purse_pub);
  if (NULL == ps)
  {
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == pc->qs)
    {
      report_row_inconsistency ("purse-deposit",
                                rowid,
                                "purse not found");
    }
    else
    {
      /* Database trouble!? */
      GNUNET_break (0);
    }
    return GNUNET_SYSERR;
  }
  TALER_ARL_amount_add (&ps->balance,
                        &ps->balance,
                        &amount_minus_fee);
  TALER_ARL_amount_add (&balance.balance,
                        &balance.balance,
                        &amount_minus_fee);
  return GNUNET_OK;
}


/**
 * Function called with details about purse merges that have been made, with
 * the goal of auditing the purse merge execution.
 *
 * @param cls closure
 * @param rowid unique serial ID for the deposit in our DB
 * @param partner_base_url where is the reserve, NULL for this exchange
 * @param amount total amount expected in the purse
 * @param balance current balance in the purse
 * @param flags purse flags
 * @param merge_pub merge capability key
 * @param reserve_pub reserve the merge affects
 * @param merge_sig signature affirming the merge
 * @param purse_pub purse key
 * @param merge_timestamp when did the merge happen
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
handle_purse_merged (
  void *cls,
  uint64_t rowid,
  const char *partner_base_url,
  const struct TALER_Amount *amount,
  const struct TALER_Amount *balance,
  enum TALER_WalletAccountMergeFlags flags,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_PurseMergeSignatureP *merge_sig,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct GNUNET_TIME_Timestamp merge_timestamp)
{
  struct PurseContext *pc = cls;
  struct PurseSummary *ps;

  /* should be monotonically increasing */
  GNUNET_assert (rowid >= ppp.last_purse_merge_serial_id);
  ppp.last_purse_merge_serial_id = rowid + 1;

  {
    char *reserve_url;

    reserve_url
      = TALER_reserve_make_payto (NULL == partner_base_url
                                ? TALER_ARL_exchange_url
                                : partner_base_url,
                                  reserve_pub);
    if (GNUNET_OK !=
        TALER_wallet_purse_merge_verify (reserve_url,
                                         merge_timestamp,
                                         purse_pub,
                                         merge_pub,
                                         merge_sig))
    {
      GNUNET_free (reserve_url);
      TALER_ARL_report (report_bad_sig_losses,
                        GNUNET_JSON_PACK (
                          GNUNET_JSON_pack_string ("operation",
                                                   "merge-purse"),
                          GNUNET_JSON_pack_uint64 ("row",
                                                   rowid),
                          TALER_JSON_pack_amount ("loss",
                                                  amount),
                          GNUNET_JSON_pack_data_auto ("key_pub",
                                                      merge_pub)));
      TALER_ARL_amount_add (&total_bad_sig_loss,
                            &total_bad_sig_loss,
                            amount);
      return GNUNET_OK;
    }
    GNUNET_free (reserve_url);
  }

  ps = setup_purse (pc,
                    purse_pub);
  if (NULL == ps)
  {
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == pc->qs)
    {
      report_row_inconsistency ("purse-merge",
                                rowid,
                                "purse not found");
    }
    else
    {
      /* Database trouble!? */
      GNUNET_break (0);
    }
    return GNUNET_SYSERR;
  }
  GNUNET_break (0 ==
                GNUNET_TIME_timestamp_cmp (merge_timestamp,
                                           ==,
                                           ps->merge_timestamp));
  TALER_ARL_amount_add (&ps->balance,
                        &ps->balance,
                        amount);
  return GNUNET_OK;
}


/**
 * Function called with details about account merge requests that have been
 * made, with the goal of auditing the account merge execution.
 *
 * @param cls closure
 * @param rowid unique serial ID for the deposit in our DB
 * @param reserve_pub reserve affected by the merge
 * @param purse_pub purse being merged
 * @param h_contract_terms hash over contract of the purse
 * @param purse_expiration when would the purse expire
 * @param amount total amount in the purse
 * @param min_age minimum age of all coins deposited into the purse
 * @param flags how was the purse created
 * @param purse_fee if a purse fee was paid, how high is it
 * @param merge_timestamp when was the merge approved
 * @param reserve_sig signature by reserve approving the merge
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
handle_account_merged (
  void *cls,
  uint64_t rowid,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_Amount *amount,
  uint32_t min_age,
  enum TALER_WalletAccountMergeFlags flags,
  const struct TALER_Amount *purse_fee,
  struct GNUNET_TIME_Timestamp merge_timestamp,
  const struct TALER_ReserveSignatureP *reserve_sig)
{
  struct PurseContext *pc = cls;
  struct PurseSummary *ps;

  /* should be monotonically increasing */
  GNUNET_assert (rowid >= ppp.last_account_merge_serial_id);
  ppp.last_account_merge_serial_id = rowid + 1;
  if (GNUNET_OK !=
      TALER_wallet_account_merge_verify (merge_timestamp,
                                         purse_pub,
                                         purse_expiration,
                                         h_contract_terms,
                                         amount,
                                         purse_fee,
                                         min_age,
                                         flags,
                                         reserve_pub,
                                         reserve_sig))
  {
    TALER_ARL_report (report_bad_sig_losses,
                      GNUNET_JSON_PACK (
                        GNUNET_JSON_pack_string ("operation",
                                                 "account-merge"),
                        GNUNET_JSON_pack_uint64 ("row",
                                                 rowid),
                        TALER_JSON_pack_amount ("loss",
                                                purse_fee),
                        GNUNET_JSON_pack_data_auto ("key_pub",
                                                    reserve_pub)));
    TALER_ARL_amount_add (&total_bad_sig_loss,
                          &total_bad_sig_loss,
                          purse_fee);
    return GNUNET_OK;
  }
  ps = setup_purse (pc,
                    purse_pub);
  if (NULL == ps)
  {
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == pc->qs)
    {
      report_row_inconsistency ("account-merge",
                                rowid,
                                "purse not found");
    }
    else
    {
      /* Database trouble!? */
      GNUNET_break (0);
    }
    return GNUNET_SYSERR;
  }
  TALER_ARL_amount_add (&balance.balance,
                        &balance.balance,
                        purse_fee);
  TALER_ARL_amount_add (&ps->balance,
                        &ps->balance,
                        purse_fee);
  return GNUNET_OK;
}


/**
 * Function called with details about purse decisions that have been made.
 *
 * @param cls closure
 * @param rowid unique serial ID for the deposit in our DB
 * @param purse_pub which purse was the decision made on
 * @param refunded true if decision was to refund
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
handle_purse_decision (
  void *cls,
  uint64_t rowid,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  bool refunded)
{
  struct PurseContext *pc = cls;
  struct PurseSummary *ps;
  struct GNUNET_HashCode key;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_Amount purse_fee;
  struct TALER_Amount balance_without_purse_fee;

  ps = setup_purse (pc,
                    purse_pub);
  if (NULL == ps)
  {
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == pc->qs)
    {
      report_row_inconsistency ("purse-decision",
                                rowid,
                                "purse not found");
    }
    else
    {
      /* Database trouble!? */
      GNUNET_break (0);
    }
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      get_purse_fee (ps->creation_date,
                     &purse_fee))
  {
    report_row_inconsistency ("purse-request",
                              rowid,
                              "purse fee unavailable");
  }
  if (0 >
      TALER_amount_subtract (&balance_without_purse_fee,
                             &ps->balance,
                             &purse_fee))
  {
    report_row_inconsistency ("purse-request",
                              rowid,
                              "purse fee higher than balance");
    TALER_amount_set_zero (TALER_ARL_currency,
                           &balance_without_purse_fee);
  }

  if (refunded)
  {
    if (-1 != TALER_amount_cmp (&balance_without_purse_fee,
                                &ps->total_value))
    {
      report_amount_arithmetic_inconsistency ("purse-decision: refund",
                                              rowid,
                                              &balance_without_purse_fee,
                                              &ps->total_value,
                                              0);
    }
  }
  else
  {
    if (-1 == TALER_amount_cmp (&balance_without_purse_fee,
                                &ps->total_value))
    {
      report_amount_arithmetic_inconsistency ("purse-decision: merge",
                                              rowid,
                                              &ps->total_value,
                                              &balance_without_purse_fee,
                                              0);
      TALER_ARL_amount_add (&total_balance_insufficient_loss,
                            &total_balance_insufficient_loss,
                            &ps->total_value);
    }
  }

  qs = TALER_ARL_adb->delete_purse_info (TALER_ARL_adb->cls,
                                         purse_pub,
                                         &TALER_ARL_master_pub);
  GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
    pc->qs = qs;
    return GNUNET_SYSERR;
  }
  GNUNET_CRYPTO_hash (purse_pub,
                      sizeof (*purse_pub),
                      &key);
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CONTAINER_multihashmap_remove (pc->purses,
                                                       &key,
                                                       ps));
  GNUNET_free (ps);
  return GNUNET_OK;
}


/**
 * Function called on expired purses.
 *
 * @param cls closure
 * @param purse_pub public key of the purse
 * @param balance amount of money in the purse
 * @param expiration_date when did the purse expire?
 * @return #GNUNET_OK to continue to iterate
 */
static enum GNUNET_GenericReturnValue
handle_purse_expired (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_Amount *balance,
  struct GNUNET_TIME_Timestamp expiration_date)
{
  struct PurseContext *pc = cls;

  (void) pc;
  TALER_ARL_report (report_purse_not_closed_inconsistencies,
                    GNUNET_JSON_PACK (
                      GNUNET_JSON_pack_data_auto ("purse_pub",
                                                  purse_pub),
                      TALER_JSON_pack_amount ("balance",
                                              balance),
                      TALER_JSON_pack_time_abs_human ("expired",
                                                      expiration_date.abs_time)));
  TALER_ARL_amount_add (&total_delayed_decisions,
                        &total_delayed_decisions,
                        balance);
  return GNUNET_OK;
}


/**
 * Check that the purse summary matches what the exchange database
 * thinks about the purse, and update our own state of the purse.
 *
 * Remove all purses that we are happy with from the DB.
 *
 * @param cls our `struct PurseContext`
 * @param key hash of the purse public key
 * @param value a `struct PurseSummary`
 * @return #GNUNET_OK to process more entries
 */
static enum GNUNET_GenericReturnValue
verify_purse_balance (void *cls,
                      const struct GNUNET_HashCode *key,
                      void *value)
{
  struct PurseContext *pc = cls;
  struct PurseSummary *ps = value;
  enum GNUNET_GenericReturnValue ret;
  enum GNUNET_DB_QueryStatus qs;

  ret = GNUNET_OK;
  if (internal_checks)
  {
    struct TALER_Amount pf;
    struct TALER_Amount balance_without_purse_fee;

    /* subtract purse fee from ps->balance to get actual balance we expect, as
       we track the balance including purse fee, while the exchange subtracts
       the purse fee early on. */
    if (GNUNET_OK !=
        get_purse_fee (ps->creation_date,
                       &pf))
    {
      GNUNET_break (0);
      report_row_inconsistency ("purse",
                                0,
                                "purse fee unavailable");
    }
    if (0 >
        TALER_amount_subtract (&balance_without_purse_fee,
                               &ps->balance,
                               &pf))
    {
      report_row_inconsistency ("purse",
                                0,
                                "purse fee higher than balance");
      TALER_amount_set_zero (TALER_ARL_currency,
                             &balance_without_purse_fee);
    }

    if (0 != TALER_amount_cmp (&ps->exchange_balance,
                               &balance_without_purse_fee))
    {
      report_amount_arithmetic_inconsistency ("purse-balance",
                                              0,
                                              &ps->exchange_balance,
                                              &balance_without_purse_fee,
                                              0);
    }
  }

  if (ps->had_pi)
    qs = TALER_ARL_adb->update_purse_info (TALER_ARL_adb->cls,
                                           &ps->purse_pub,
                                           &TALER_ARL_master_pub,
                                           &ps->balance);
  else
    qs = TALER_ARL_adb->insert_purse_info (TALER_ARL_adb->cls,
                                           &ps->purse_pub,
                                           &TALER_ARL_master_pub,
                                           &ps->balance,
                                           ps->expiration_date);
  GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
    pc->qs = qs;
    return GNUNET_SYSERR;
  }

  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CONTAINER_multihashmap_remove (pc->purses,
                                                       key,
                                                       ps));
  GNUNET_free (ps);
  return ret;
}


/**
 * Analyze purses for being well-formed.
 *
 * @param cls NULL
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
analyze_purses (void *cls)
{
  struct PurseContext pc;
  enum GNUNET_DB_QueryStatus qsx;
  enum GNUNET_DB_QueryStatus qs;
  enum GNUNET_DB_QueryStatus qsp;

  (void) cls;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Analyzing purses\n");
  qsp = TALER_ARL_adb->get_auditor_progress_purse (TALER_ARL_adb->cls,
                                                   &TALER_ARL_master_pub,
                                                   &ppp);
  if (0 > qsp)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsp);
    return qsp;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsp)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "First analysis using this auditor, starting audit from scratch\n");
  }
  else
  {
    ppp_start = ppp;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Resuming purse audit at %llu/%llu/%llu/%llu/%llu\n",
                (unsigned long long) ppp.last_purse_request_serial_id,
                (unsigned long long) ppp.last_purse_decision_serial_id,
                (unsigned long long) ppp.last_purse_merge_serial_id,
                (unsigned long long) ppp.last_purse_deposits_serial_id,
                (unsigned long long) ppp.last_account_merge_serial_id);
  }
  pc.qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  qsx = TALER_ARL_adb->get_purse_summary (TALER_ARL_adb->cls,
                                          &TALER_ARL_master_pub,
                                          &balance);
  if (qsx < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsx);
    return qsx;
  }
  pc.purses = GNUNET_CONTAINER_multihashmap_create (512,
                                                    GNUNET_NO);

  qs = TALER_ARL_edb->select_purse_requests_above_serial_id (
    TALER_ARL_edb->cls,
    ppp.last_purse_request_serial_id,
    &handle_purse_requested,
    &pc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  qs = TALER_ARL_edb->select_purse_merges_above_serial_id (
    TALER_ARL_edb->cls,
    ppp.last_purse_merge_serial_id,
    &handle_purse_merged,
    &pc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  qs = TALER_ARL_edb->select_purse_deposits_above_serial_id (
    TALER_ARL_edb->cls,
    ppp.last_purse_deposits_serial_id,
    &handle_purse_deposits,
    &pc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  /* Charge purse fee! */
  qs = TALER_ARL_edb->select_account_merges_above_serial_id (
    TALER_ARL_edb->cls,
    ppp.last_account_merge_serial_id,
    &handle_account_merged,
    &pc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  qs = TALER_ARL_edb->select_all_purse_decisions_above_serial_id (
    TALER_ARL_edb->cls,
    ppp.last_purse_decision_serial_id,
    &handle_purse_decision,
    &pc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  qs = TALER_ARL_adb->select_purse_expired (
    TALER_ARL_adb->cls,
    &TALER_ARL_master_pub,
    &handle_purse_expired,
    &pc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  GNUNET_CONTAINER_multihashmap_iterate (pc.purses,
                                         &verify_purse_balance,
                                         &pc);
  GNUNET_break (0 ==
                GNUNET_CONTAINER_multihashmap_size (pc.purses));
  GNUNET_CONTAINER_multihashmap_destroy (pc.purses);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != pc.qs)
    return qs;
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsx)
  {
    qs = TALER_ARL_adb->insert_purse_summary (TALER_ARL_adb->cls,
                                              &TALER_ARL_master_pub,
                                              &balance);
  }
  else
  {
    qs = TALER_ARL_adb->update_purse_summary (TALER_ARL_adb->cls,
                                              &TALER_ARL_master_pub,
                                              &balance);
  }
  if (0 >= qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qsp)
    qs = TALER_ARL_adb->update_auditor_progress_purse (TALER_ARL_adb->cls,
                                                       &TALER_ARL_master_pub,
                                                       &ppp);
  else
    qs = TALER_ARL_adb->insert_auditor_progress_purse (TALER_ARL_adb->cls,
                                                       &TALER_ARL_master_pub,
                                                       &ppp);
  if (0 >= qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Concluded purse audit step at %llu/%llu/%llu/%llu/%llu\n",
              (unsigned long long) ppp.last_purse_request_serial_id,
              (unsigned long long) ppp.last_purse_decision_serial_id,
              (unsigned long long) ppp.last_purse_merge_serial_id,
              (unsigned long long) ppp.last_purse_deposits_serial_id,
              (unsigned long long) ppp.last_account_merge_serial_id);
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
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
              "Launching auditor\n");
  if (GNUNET_OK !=
      TALER_ARL_init (c))
  {
    global_ret = EXIT_FAILURE;
    return;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &balance.balance));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &total_balance_insufficient_loss));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &total_delayed_decisions));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &total_arithmetic_delta_plus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &total_arithmetic_delta_minus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &total_balance_purse_not_closed));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &total_bad_sig_loss));

  GNUNET_assert (NULL !=
                 (report_row_inconsistencies = json_array ()));
  GNUNET_assert (NULL !=
                 (report_purse_balance_insufficient_inconsistencies
                    = json_array ()));
  GNUNET_assert (NULL !=
                 (report_purse_not_closed_inconsistencies
                    = json_array ()));
  GNUNET_assert (NULL !=
                 (report_amount_arithmetic_inconsistencies
                    = json_array ()));
  GNUNET_assert (NULL !=
                 (report_bad_sig_losses = json_array ()));
  if (GNUNET_OK !=
      TALER_ARL_setup_sessions_and_run (&analyze_purses,
                                        NULL))
  {
    global_ret = EXIT_FAILURE;
    return;
  }
  TALER_ARL_done (
    GNUNET_JSON_PACK (
      /* Globals (REVIEW!) */
      TALER_JSON_pack_amount ("total_balance_insufficient",
                              &total_balance_insufficient_loss),
      TALER_JSON_pack_amount ("total_delayed_purse_decisions",
                              &total_delayed_decisions),
      GNUNET_JSON_pack_array_steal (
        "purse_balance_insufficient_inconsistencies",
        report_purse_balance_insufficient_inconsistencies),
      TALER_JSON_pack_amount ("total_balance_purse_not_closed",
                              &total_balance_purse_not_closed),
      TALER_JSON_pack_amount ("total_bad_sig_loss",
                              &total_bad_sig_loss),
      TALER_JSON_pack_amount ("total_arithmetic_delta_plus",
                              &total_arithmetic_delta_plus),
      TALER_JSON_pack_amount ("total_arithmetic_delta_minus",
                              &total_arithmetic_delta_minus),

      /* Global 'balances' */
      TALER_JSON_pack_amount ("total_purse_balance",
                              &balance.balance),
      GNUNET_JSON_pack_uint64 ("total_purse_count",
                               balance.open_purses),

      GNUNET_JSON_pack_array_steal ("purse_not_closed_inconsistencies",
                                    report_purse_not_closed_inconsistencies),
      GNUNET_JSON_pack_array_steal ("bad_sig_losses",
                                    report_bad_sig_losses),
      GNUNET_JSON_pack_array_steal ("row_inconsistencies",
                                    report_row_inconsistencies),
      GNUNET_JSON_pack_array_steal ("amount_arithmetic_inconsistencies",
                                    report_amount_arithmetic_inconsistencies),
      /* Information about audited range ... */
      TALER_JSON_pack_time_abs_human ("auditor_start_time",
                                      start_time),
      TALER_JSON_pack_time_abs_human ("auditor_end_time",
                                      GNUNET_TIME_absolute_get ()),
      GNUNET_JSON_pack_uint64 ("start_ppp_purse_merges_serial_id",
                               ppp_start.last_purse_merge_serial_id),
      GNUNET_JSON_pack_uint64 ("start_ppp_purse_deposits_serial_id",
                               ppp_start.last_purse_deposits_serial_id),
      GNUNET_JSON_pack_uint64 ("start_ppp_account_merge_serial_id",
                               ppp_start.last_account_merge_serial_id),
      GNUNET_JSON_pack_uint64 ("end_ppp_purse_merges_serial_id",
                               ppp.last_purse_merge_serial_id),
      GNUNET_JSON_pack_uint64 ("end_ppp_purse_deposits_serial_id",
                               ppp.last_purse_deposits_serial_id),
      GNUNET_JSON_pack_uint64 ("end_ppp_account_merge_serial_id",
                               ppp.last_account_merge_serial_id)));
}


/**
 * The main function to check the database's handling of purses.
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
    return EXIT_INVALIDARGUMENT;
  ret = GNUNET_PROGRAM_run (
    argc,
    argv,
    "taler-helper-auditor-purses",
    gettext_noop ("Audit Taler exchange purse handling"),
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


/* end of taler-helper-auditor-purses.c */
