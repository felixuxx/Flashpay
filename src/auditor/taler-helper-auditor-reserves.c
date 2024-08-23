/*
  This file is part of TALER
  Copyright (C) 2016-2024 Taler Systems SA

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
 * @file auditor/taler-helper-auditor-reserves.c
 * @brief audits the reserves of an exchange database
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_auditordb_plugin.h"
#include "taler_exchangedb_lib.h"
#include "taler_bank_service.h"
#include "taler_signatures.h"
#include "report-lib.h"
#include "taler_dbevents.h"


/**
 * Use a 1 day grace period to deal with clocks not being perfectly synchronized.
 */
#define CLOSING_GRACE_PERIOD GNUNET_TIME_UNIT_DAYS

/**
 * Return value from main().
 */
static int global_ret;

/**
 * Run in test mode. Exit when idle instead of
 * going to sleep and waiting for more work.
 *
 * FIXME: not yet implemented!
 */
static int test_mode;

/**
 * After how long should idle reserves be closed?
 */
static struct GNUNET_TIME_Relative idle_reserve_expiration_time;

/**
 * Checkpointing our progress for reserves.
 */
static TALER_ARL_DEF_PP (reserves_reserve_in_serial_id);
static TALER_ARL_DEF_PP (reserves_reserve_out_serial_id);
static TALER_ARL_DEF_PP (reserves_reserve_recoup_serial_id);
static TALER_ARL_DEF_PP (reserves_reserve_open_serial_id);
static TALER_ARL_DEF_PP (reserves_reserve_close_serial_id);
static TALER_ARL_DEF_PP (reserves_purse_decisions_serial_id);
static TALER_ARL_DEF_PP (reserves_account_merges_serial_id);
static TALER_ARL_DEF_PP (reserves_history_requests_serial_id);

/**
 * Tracked global reserve balances.
 */
static TALER_ARL_DEF_AB (reserves_reserve_total_balance);
static TALER_ARL_DEF_AB (reserves_reserve_loss);
static TALER_ARL_DEF_AB (reserves_withdraw_fee_revenue);
static TALER_ARL_DEF_AB (reserves_close_fee_revenue);
static TALER_ARL_DEF_AB (reserves_purse_fee_revenue);
static TALER_ARL_DEF_AB (reserves_open_fee_revenue);
static TALER_ARL_DEF_AB (reserves_history_fee_revenue);

/**
 * Total amount lost by operations for which signatures were invalid.
 */
static TALER_ARL_DEF_AB (reserves_total_bad_sig_loss);

/**
 * Total amount affected by reserves not having been closed on time.
 */
static TALER_ARL_DEF_AB (total_balance_reserve_not_closed);

/**
 * Total delta between expected and stored reserve balance summaries,
 * for positive deltas.  Used only when internal checks are
 * enabled.
 */
static TALER_ARL_DEF_AB (total_balance_summary_delta_plus);

/**
 * Total delta between expected and stored reserve balance summaries,
 * for negative deltas.  Used only when internal checks are
 * enabled.
 */
static TALER_ARL_DEF_AB (total_balance_summary_delta_minus);

/**
 * Profits the exchange made by bad amount calculations.
 */
static TALER_ARL_DEF_AB (reserves_total_arithmetic_delta_plus);

/**
 * Losses the exchange made by bad amount calculations.
 */
static TALER_ARL_DEF_AB (reserves_total_arithmetic_delta_minus);

/**
 * Should we run checks that only work for exchange-internal audits?
 */
static int internal_checks;

static struct GNUNET_DB_EventHandler *eh;

/**
 * The auditors's configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;

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
  enum GNUNET_DB_QueryStatus qs;

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

  {
    struct TALER_AUDITORDB_AmountArithmeticInconsistency aai = {
      .row_id = rowid,
      .profitable = profitable,
      .operation = (char *) operation,
      .exchange_amount = *exchange,
      .auditor_amount = *auditor,
    };

    qs = TALER_ARL_adb->insert_amount_arithmetic_inconsistency (
      TALER_ARL_adb->cls,
      &aai);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      // FIXME: error handling!!?
    }
  }

  if (0 != profitable)
  {
    target = (1 == profitable)
      ? &TALER_ARL_USE_AB (reserves_total_arithmetic_delta_plus)
      : &TALER_ARL_USE_AB (reserves_total_arithmetic_delta_minus);
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
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_AUDITORDB_RowInconsistency ri = {
    .diagnostic = (char *) diagnostic,
    .row_table = (char *) table,
    .row_id = rowid
  };

  qs = TALER_ARL_adb->insert_row_inconsistency (
    TALER_ARL_adb->cls,
    &ri);

  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    // FIXME: error handling!!?
  }
}


/* ***************************** Analyze reserves ************************ */
/* This logic checks the reserves_in, reserves_out and reserves-tables */

/**
 * Summary data we keep per reserve.
 */
struct ReserveSummary
{
  /**
   * Public key of the reserve.
   * Always set when the struct is first initialized.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Sum of all incoming transfers during this transaction.
   * Updated only in #handle_reserve_in().
   */
  struct TALER_Amount total_in;

  /**
   * Sum of all outgoing transfers during this transaction (includes fees).
   * Updated only in #handle_reserve_out().
   */
  struct TALER_Amount total_out;

  /**
   * Sum of balance and fees encountered during this transaction.
   */
  struct TALER_AUDITORDB_ReserveFeeBalance curr_balance;

  /**
   * Previous balances of the reserve as remembered by the auditor.
   * (updated based on @e total_in and @e total_out at the end).
   */
  struct TALER_AUDITORDB_ReserveFeeBalance prev_balance;

  /**
   * Previous reserve expiration data, as remembered by the auditor.
   * (updated on-the-fly in #handle_reserve_in()).
   */
  struct GNUNET_TIME_Timestamp a_expiration_date;

  /**
   * Which account did originally put money into the reserve?
   */
  char *sender_account;

  /**
   * Did we have a previous reserve info?  Used to decide between
   * UPDATE and INSERT later.  Initialized in
   * #load_auditor_reserve_summary() together with the a-* values
   * (if available).
   */
  bool had_ri;

};


/**
 * Load the auditor's remembered state about the reserve into @a rs.
 * The "total_in" and "total_out" amounts of @a rs must already be
 * initialized (so we can determine the currency).
 *
 * @param[in,out] rs reserve summary to (fully) initialize
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
load_auditor_reserve_summary (struct ReserveSummary *rs)
{
  enum GNUNET_DB_QueryStatus qs;
  uint64_t rowid;

  qs = TALER_ARL_adb->get_reserve_info (TALER_ARL_adb->cls,
                                        &rs->reserve_pub,
                                        &rowid,
                                        &rs->prev_balance,
                                        &rs->a_expiration_date,
                                        &rs->sender_account);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    rs->had_ri = false;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (rs->total_in.currency,
                                          &rs->prev_balance.reserve_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (rs->total_in.currency,
                                          &rs->prev_balance.reserve_loss));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (rs->total_in.currency,
                                          &rs->prev_balance.withdraw_fee_balance
                                          ));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (rs->total_in.currency,
                                          &rs->prev_balance.close_fee_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (rs->total_in.currency,
                                          &rs->prev_balance.purse_fee_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (rs->total_in.currency,
                                          &rs->prev_balance.open_fee_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (rs->total_in.currency,
                                          &rs->prev_balance.history_fee_balance)
                   );
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Creating fresh reserve `%s'\n",
                TALER_B2S (&rs->reserve_pub));
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }
  rs->had_ri = true;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Auditor remembers reserve `%s' has balance %s\n",
              TALER_B2S (&rs->reserve_pub),
              TALER_amount2s (&rs->prev_balance.reserve_balance));
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Closure to the various callbacks we make while checking a reserve.
 */
struct ReserveContext
{
  /**
   * Map from hash of reserve's public key to a `struct ReserveSummary`.
   */
  struct GNUNET_CONTAINER_MultiHashMap *reserves;

  /**
   * Map from hash of denomination's public key to a
   * static string "revoked" for keys that have been revoked,
   * or "master signature invalid" in case the revocation is
   * there but bogus.
   */
  struct GNUNET_CONTAINER_MultiHashMap *revoked;

  /**
   * Transaction status code, set to error codes if applicable.
   */
  enum GNUNET_DB_QueryStatus qs;

};


/**
 * Create a new reserve for @a reserve_pub in @a rc.
 *
 * @param[in,out] rc context to update
 * @param reserve_pub key for which to create a reserve
 * @return NULL on error
 */
static struct ReserveSummary *
setup_reserve (struct ReserveContext *rc,
               const struct TALER_ReservePublicKeyP *reserve_pub)
{
  struct ReserveSummary *rs;
  struct GNUNET_HashCode key;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_CRYPTO_hash (reserve_pub,
                      sizeof (*reserve_pub),
                      &key);
  rs = GNUNET_CONTAINER_multihashmap_get (rc->reserves,
                                          &key);
  if (NULL != rs)
    return rs;
  rs = GNUNET_new (struct ReserveSummary);
  rs->reserve_pub = *reserve_pub;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &rs->total_in));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &rs->total_out));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &rs->curr_balance.reserve_balance));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &rs->curr_balance.reserve_loss));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &rs->curr_balance.withdraw_fee_balance))
  ;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &rs->curr_balance.close_fee_balance));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &rs->curr_balance.purse_fee_balance));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &rs->curr_balance.open_fee_balance));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &rs->curr_balance.history_fee_balance));
  if (0 > (qs = load_auditor_reserve_summary (rs)))
  {
    GNUNET_free (rs);
    rc->qs = qs;
    return NULL;
  }
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONTAINER_multihashmap_put (rc->reserves,
                                                    &key,
                                                    rs,
                                                    GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  return rs;
}


/**
 * Function called with details about incoming wire transfers.
 *
 * @param cls our `struct ReserveContext`
 * @param rowid unique serial ID for the refresh session in our DB
 * @param reserve_pub public key of the reserve (also the WTID)
 * @param credit amount that was received
 * @param sender_account_details information about the sender's bank account
 * @param wire_reference unique reference identifying the wire transfer
 * @param execution_date when did we receive the funds
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
handle_reserve_in (void *cls,
                   uint64_t rowid,
                   const struct TALER_ReservePublicKeyP *reserve_pub,
                   const struct TALER_Amount *credit,
                   const char *sender_account_details,
                   uint64_t wire_reference,
                   struct GNUNET_TIME_Timestamp execution_date)
{
  struct ReserveContext *rc = cls;
  struct ReserveSummary *rs;
  struct GNUNET_TIME_Timestamp expiry;

  (void) wire_reference;
  /* should be monotonically increasing */
  GNUNET_assert (rowid >= TALER_ARL_USE_PP (reserves_reserve_in_serial_id));
  TALER_ARL_USE_PP (reserves_reserve_in_serial_id) = rowid + 1;
  rs = setup_reserve (rc,
                      reserve_pub);
  if (NULL == rs)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (NULL == rs->sender_account)
    rs->sender_account = GNUNET_strdup (sender_account_details);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Additional incoming wire transfer for reserve `%s' of %s\n",
              TALER_B2S (reserve_pub),
              TALER_amount2s (credit));
  expiry = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (execution_date.abs_time,
                              idle_reserve_expiration_time));
  rs->a_expiration_date = GNUNET_TIME_timestamp_max (rs->a_expiration_date,
                                                     expiry);
  TALER_ARL_amount_add (&rs->total_in,
                        &rs->total_in,
                        credit);
  return GNUNET_OK;
}


/**
 * Function called with details about withdraw operations.  Verifies
 * the signature and updates the reserve's balance.
 *
 * @param cls our `struct ReserveContext`
 * @param rowid unique serial ID for the refresh session in our DB
 * @param h_blind_ev blinded hash of the coin's public key
 * @param denom_pub public denomination key of the deposited coin
 * @param reserve_pub public key of the reserve
 * @param reserve_sig signature over the withdraw operation
 * @param execution_date when did the wallet withdraw the coin
 * @param amount_with_fee amount that was withdrawn
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
handle_reserve_out (void *cls,
                    uint64_t rowid,
                    const struct TALER_BlindedCoinHashP *h_blind_ev,
                    const struct TALER_DenominationPublicKey *denom_pub,
                    const struct TALER_ReservePublicKeyP *reserve_pub,
                    const struct TALER_ReserveSignatureP *reserve_sig,
                    struct GNUNET_TIME_Timestamp execution_date,
                    const struct TALER_Amount *amount_with_fee)
{
  struct ReserveContext *rc = cls;
  struct ReserveSummary *rs;
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue;
  struct TALER_Amount auditor_amount_with_fee;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_DenominationHashP h_denom_pub;

  /* should be monotonically increasing */
  GNUNET_assert (rowid >= TALER_ARL_USE_PP (reserves_reserve_out_serial_id));
  TALER_ARL_USE_PP (reserves_reserve_out_serial_id) = rowid + 1;

  /* lookup denomination pub data (make sure denom_pub is valid, establish fees);
     initializes wsrd.h_denomination_pub! */
  qs = TALER_ARL_get_denomination_info (denom_pub,
                                        &issue,
                                        &h_denom_pub);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Hard database error trying to get denomination %s (%s) from database!\n",
                  TALER_B2S (denom_pub),
                  TALER_amount2s (amount_with_fee));
    rc->qs = qs;
    return GNUNET_SYSERR;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    report_row_inconsistency ("withdraw",
                              rowid,
                              "denomination key not found");
    return GNUNET_OK;
  }

  /* check that execution date is within withdraw range for denom_pub  */
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Checking withdraw timing: %llu, expire: %llu, timing: %llu\n",
              (unsigned long long) issue->start.abs_time.abs_value_us,
              (unsigned long long) issue->expire_withdraw.abs_time.abs_value_us,
              (unsigned long long) execution_date.abs_time.abs_value_us);
  if (GNUNET_TIME_timestamp_cmp (issue->start,
                                 >,
                                 execution_date) ||
      GNUNET_TIME_timestamp_cmp (issue->expire_withdraw,
                                 <,
                                 execution_date))
  {
    struct TALER_AUDITORDB_DenominationKeyValidityWithdrawInconsistency dkvwi ={
      .row_id = rowid,
      .execution_date = execution_date.abs_time,
      .denompub_h = *&h_denom_pub,
      .reserve_pub = *reserve_pub
    };

    qs =
      TALER_ARL_adb->insert_denomination_key_validity_withdraw_inconsistency (
        TALER_ARL_adb->cls,
        &dkvwi);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      /* FIXME: error handling! */
    }
  }

  /* check reserve_sig (first: setup remaining members of wsrd) */
  if (GNUNET_OK !=
      TALER_wallet_withdraw_verify (&h_denom_pub,
                                    amount_with_fee,
                                    h_blind_ev,
                                    reserve_pub,
                                    reserve_sig))
  {
    struct TALER_AUDITORDB_BadSigLosses bsl = {
      .row_id = rowid,
      .operation = "withdraw",
      .loss = *amount_with_fee,
      .operation_specific_pub = reserve_pub->eddsa_pub
    };

    qs = TALER_ARL_adb->insert_bad_sig_losses (
      TALER_ARL_adb->cls,
      &bsl);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      // FIXME: error handling!
    }
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (reserves_total_bad_sig_loss),
                          &TALER_ARL_USE_AB (reserves_total_bad_sig_loss),
                          amount_with_fee);
    return GNUNET_OK;     /* exit function here, we cannot add this to the legitimate withdrawals */
  }

  TALER_ARL_amount_add (&auditor_amount_with_fee,
                        &issue->value,
                        &issue->fees.withdraw);
  if (0 !=
      TALER_amount_cmp (&auditor_amount_with_fee,
                        amount_with_fee))
  {
    report_row_inconsistency ("withdraw",
                              rowid,
                              "amount with fee from exchange does not match denomination value plus fee");
  }
  rs = setup_reserve (rc,
                      reserve_pub);
  if (NULL == rs)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Reserve `%s' reduced by %s from withdraw\n",
              TALER_B2S (reserve_pub),
              TALER_amount2s (&auditor_amount_with_fee));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Increasing withdraw profits by fee %s\n",
              TALER_amount2s (&issue->fees.withdraw));
  TALER_ARL_amount_add (&rs->curr_balance.withdraw_fee_balance,
                        &rs->curr_balance.withdraw_fee_balance,
                        &issue->fees.withdraw);
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (reserves_withdraw_fee_revenue),
                        &TALER_ARL_USE_AB (reserves_withdraw_fee_revenue),
                        &issue->fees.withdraw);
  TALER_ARL_amount_add (&rs->total_out,
                        &rs->total_out,
                        &auditor_amount_with_fee);
  return GNUNET_OK;
}


/**
 * Function called with details about withdraw operations.  Verifies
 * the signature and updates the reserve's balance.
 *
 * @param cls our `struct ReserveContext`
 * @param rowid unique serial ID for the refresh session in our DB
 * @param timestamp when did we receive the recoup request
 * @param amount how much should be added back to the reserve
 * @param reserve_pub public key of the reserve
 * @param coin public information about the coin, denomination signature is
 *        already verified in #check_recoup()
 * @param denom_pub public key of the denomionation of @a coin
 * @param coin_sig signature with @e coin_pub of type #TALER_SIGNATURE_WALLET_COIN_RECOUP
 * @param coin_blind blinding factor used to blind the coin
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
handle_recoup_by_reserve (
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_Amount *amount,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_CoinPublicInfo *coin,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  const union GNUNET_CRYPTO_BlindingSecretP *coin_blind)
{
  struct ReserveContext *rc = cls;
  struct ReserveSummary *rs;
  struct GNUNET_TIME_Timestamp expiry;
  struct TALER_MasterSignatureP msig;
  uint64_t rev_rowid;
  enum GNUNET_DB_QueryStatus qs;
  const char *rev;

  (void) denom_pub;
  /* should be monotonically increasing */
  GNUNET_assert (rowid >= TALER_ARL_USE_PP (reserves_reserve_recoup_serial_id));
  TALER_ARL_USE_PP (reserves_reserve_recoup_serial_id) = rowid + 1;
  /* We know that denom_pub matches denom_pub_hash because this
     is how the SQL statement joined the tables. */
  if (GNUNET_OK !=
      TALER_wallet_recoup_verify (&coin->denom_pub_hash,
                                  coin_blind,
                                  &coin->coin_pub,
                                  coin_sig))
  {
    struct TALER_AUDITORDB_BadSigLosses bslr = {
      .row_id = rowid,
      .operation = "recoup",
      .loss = *amount,
      .operation_specific_pub = coin->coin_pub.eddsa_pub
    };

    qs = TALER_ARL_adb->insert_bad_sig_losses (
      TALER_ARL_adb->cls,
      &bslr);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      // FIXME: error handling!
    }
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (reserves_total_bad_sig_loss),
                          &TALER_ARL_USE_AB (reserves_total_bad_sig_loss),
                          amount);
  }

  /* check that the coin was eligible for recoup!*/
  rev = GNUNET_CONTAINER_multihashmap_get (rc->revoked,
                                           &coin->denom_pub_hash.hash);
  if (NULL == rev)
  {
    qs = TALER_ARL_edb->get_denomination_revocation (TALER_ARL_edb->cls,
                                                     &coin->denom_pub_hash,
                                                     &msig,
                                                     &rev_rowid);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      rc->qs = qs;
      return GNUNET_SYSERR;
    }
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      report_row_inconsistency ("recoup",
                                rowid,
                                "denomination key not in revocation set");
      TALER_ARL_amount_add (&TALER_ARL_USE_AB (reserves_reserve_loss),
                            &TALER_ARL_USE_AB (reserves_reserve_loss),
                            amount);
    }
    else
    {
      if (GNUNET_OK !=
          TALER_exchange_offline_denomination_revoke_verify (
            &coin->denom_pub_hash,
            &TALER_ARL_master_pub,
            &msig))
      {
        rev = "master signature invalid";
      }
      else
      {
        rev = "revoked";
      }
      GNUNET_assert (
        GNUNET_OK ==
        GNUNET_CONTAINER_multihashmap_put (
          rc->revoked,
          &coin->denom_pub_hash.hash,
          (void *) rev,
          GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
    }
  }
  else
  {
    rev_rowid = 0;   /* reported elsewhere */
  }
  if ((NULL != rev) &&
      (0 == strcmp (rev,
                    "master signature invalid")))
  {
    struct TALER_AUDITORDB_BadSigLosses bslrm = {
      .row_id = rev_rowid,
      .operation = "recoup-master",
      .loss = *amount,
      .operation_specific_pub = TALER_ARL_master_pub.eddsa_pub
    };

    qs = TALER_ARL_adb->insert_bad_sig_losses (
      TALER_ARL_adb->cls,
      &bslrm);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    }
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (reserves_total_bad_sig_loss),
                          &TALER_ARL_USE_AB (reserves_total_bad_sig_loss),
                          amount);
  }

  rs = setup_reserve (rc,
                      reserve_pub);
  if (NULL == rs)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  TALER_ARL_amount_add (&rs->total_in,
                        &rs->total_in,
                        amount);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Additional /recoup value to for reserve `%s' of %s\n",
              TALER_B2S (reserve_pub),
              TALER_amount2s (amount));
  expiry = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (timestamp.abs_time,
                              idle_reserve_expiration_time));
  rs->a_expiration_date = GNUNET_TIME_timestamp_max (rs->a_expiration_date,
                                                     expiry);
  return GNUNET_OK;
}


/**
 * Obtain the closing fee for a transfer at @a time for target
 * @a receiver_account.
 *
 * @param receiver_account payto:// URI of the target account
 * @param atime when was the transfer made
 * @param[out] fee set to the closing fee
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
get_closing_fee (const char *receiver_account,
                 struct GNUNET_TIME_Timestamp atime,
                 struct TALER_Amount *fee)
{
  struct TALER_MasterSignatureP master_sig;
  struct GNUNET_TIME_Timestamp start_date;
  struct GNUNET_TIME_Timestamp end_date;
  struct TALER_WireFeeSet fees;
  char *method;

  method = TALER_payto_get_method (receiver_account);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Method is `%s'\n",
              method);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      TALER_ARL_edb->get_wire_fee (TALER_ARL_edb->cls,
                                   method,
                                   atime,
                                   &start_date,
                                   &end_date,
                                   &fees,
                                   &master_sig))
  {
    char *diag;

    GNUNET_asprintf (&diag,
                     "closing fee for `%s' unavailable at %s\n",
                     method,
                     GNUNET_TIME_timestamp2s (atime));
    report_row_inconsistency ("closing-fee",
                              atime.abs_time.abs_value_us,
                              diag);
    GNUNET_free (diag);
    GNUNET_free (method);
    return GNUNET_SYSERR;
  }
  *fee = fees.closing;
  GNUNET_free (method);
  return GNUNET_OK;
}


/**
 * Function called about reserve opening operations.
 *
 * @param cls closure
 * @param rowid row identifier used to uniquely identify the reserve closing operation
 * @param reserve_payment how much to pay from the
 *        reserve's own balance for opening the reserve
 * @param request_timestamp when was the request created
 * @param reserve_expiration desired expiration time for the reserve
 * @param purse_limit minimum number of purses the client
 *       wants to have concurrently open for this reserve
 * @param reserve_pub public key of the reserve
 * @param reserve_sig signature affirming the operation
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
handle_reserve_open (
  void *cls,
  uint64_t rowid,
  const struct TALER_Amount *reserve_payment,
  struct GNUNET_TIME_Timestamp request_timestamp,
  struct GNUNET_TIME_Timestamp reserve_expiration,
  uint32_t purse_limit,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig)
{
  struct ReserveContext *rc = cls;
  struct ReserveSummary *rs;
  enum GNUNET_DB_QueryStatus qs;

  /* should be monotonically increasing */
  GNUNET_assert (rowid >= TALER_ARL_USE_PP (reserves_reserve_open_serial_id));
  TALER_ARL_USE_PP (reserves_reserve_open_serial_id) = rowid + 1;

  rs = setup_reserve (rc,
                      reserve_pub);
  if (NULL == rs)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_reserve_open_verify (reserve_payment,
                                        request_timestamp,
                                        reserve_expiration,
                                        purse_limit,
                                        reserve_pub,
                                        reserve_sig))
  {
    struct TALER_AUDITORDB_BadSigLosses bsl = {
      .row_id = rowid,
      .operation = "reserve-open",
      .loss = *reserve_payment,
      .operation_specific_pub = reserve_pub->eddsa_pub
    };

    qs = TALER_ARL_adb->insert_bad_sig_losses (
      TALER_ARL_adb->cls,
      &bsl);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      // FIXME: error handling!
    }
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (reserves_total_bad_sig_loss),
                          &TALER_ARL_USE_AB (reserves_total_bad_sig_loss),
                          reserve_payment);
    return GNUNET_OK;
  }
  TALER_ARL_amount_add (&rs->curr_balance.open_fee_balance,
                        &rs->curr_balance.open_fee_balance,
                        reserve_payment);
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (reserves_open_fee_revenue),
                        &TALER_ARL_USE_AB (reserves_open_fee_revenue),
                        reserve_payment);
  TALER_ARL_amount_add (&rs->total_out,
                        &rs->total_out,
                        reserve_payment);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Additional open operation for reserve `%s' of %s\n",
              TALER_B2S (reserve_pub),
              TALER_amount2s (reserve_payment));
  return GNUNET_OK;
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
 * @param receiver_account where did we send the funds
 * @param transfer_details details about the wire transfer
 * @param close_request_row which close request triggered the operation?
 *         0 if it was a timeout
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
handle_reserve_closed (
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Timestamp execution_date,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *closing_fee,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const char *receiver_account,
  const struct TALER_WireTransferIdentifierRawP *transfer_details,
  uint64_t close_request_row)
{
  struct ReserveContext *rc = cls;
  struct ReserveSummary *rs;

  (void) transfer_details;
  /* should be monotonically increasing */
  GNUNET_assert (rowid >= TALER_ARL_USE_PP (reserves_reserve_close_serial_id));
  TALER_ARL_USE_PP (reserves_reserve_close_serial_id) = rowid + 1;

  rs = setup_reserve (rc,
                      reserve_pub);
  if (NULL == rs)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  {
    struct TALER_Amount expected_fee;

    /* verify closing_fee is correct! */
    if (GNUNET_OK !=
        get_closing_fee (receiver_account,
                         execution_date,
                         &expected_fee))
    {
      GNUNET_break (0);
    }
    else if (0 != TALER_amount_cmp (&expected_fee,
                                    closing_fee))
    {
      report_amount_arithmetic_inconsistency (
        "closing aggregation fee",
        rowid,
        closing_fee,
        &expected_fee,
        1);
    }
  }

  TALER_ARL_amount_add (&rs->curr_balance.close_fee_balance,
                        &rs->curr_balance.close_fee_balance,
                        closing_fee);
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (reserves_close_fee_revenue),
                        &TALER_ARL_USE_AB (reserves_close_fee_revenue),
                        closing_fee);
  TALER_ARL_amount_add (&rs->total_out,
                        &rs->total_out,
                        amount_with_fee);
  if (0 != close_request_row)
  {
    struct TALER_ReserveSignatureP reserve_sig;
    struct GNUNET_TIME_Timestamp request_timestamp;
    struct TALER_Amount close_balance;
    struct TALER_Amount close_fee;
    char *payto_uri;
    enum GNUNET_DB_QueryStatus qs;

    qs = TALER_ARL_edb->select_reserve_close_request_info (
      TALER_ARL_edb->cls,
      reserve_pub,
      close_request_row,
      &reserve_sig,
      &request_timestamp,
      &close_balance,
      &close_fee,
      &payto_uri);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    {
      report_row_inconsistency ("reserves_close",
                                rowid,
                                "reserve close request unknown");
    }
    else
    {
      struct TALER_PaytoHashP h_payto;

      TALER_payto_hash (payto_uri,
                        &h_payto);
      if (GNUNET_OK !=
          TALER_wallet_reserve_close_verify (
            request_timestamp,
            &h_payto,
            reserve_pub,
            &reserve_sig))
      {
        struct TALER_AUDITORDB_BadSigLosses bsl = {
          .row_id = close_request_row,
          .operation = "close-request",
          .loss = *amount_with_fee,
          .operation_specific_pub = reserve_pub->eddsa_pub
        };

        qs = TALER_ARL_adb->insert_bad_sig_losses (
          TALER_ARL_adb->cls,
          &bsl);

        if (qs < 0)
        {
          GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
          // FIXME: error handling!
        }
        TALER_ARL_amount_add (&TALER_ARL_USE_AB (reserves_total_bad_sig_loss),
                              &TALER_ARL_USE_AB (reserves_total_bad_sig_loss),
                              amount_with_fee);
      }
    }
    if ((NULL == payto_uri) &&
        (NULL == rs->sender_account))
    {
      GNUNET_break (! rs->had_ri);
      report_row_inconsistency ("reserves_close",
                                rowid,
                                "target account not verified, auditor does not know reserve");
    }
    if (NULL == payto_uri)
    {
      if ((NULL == rs->sender_account) ||
          (0 != strcmp (rs->sender_account,
                        receiver_account)))
      {
        report_row_inconsistency ("reserves_close",
                                  rowid,
                                  "target account does not match origin account");
      }
    }
    else
    {
      if (0 != strcmp (payto_uri,
                       receiver_account))
      {
        report_row_inconsistency ("reserves_close",
                                  rowid,
                                  "target account does not match origin account");
      }
    }
    GNUNET_free (payto_uri);
  }
  else
  {
    if (NULL == rs->sender_account)
    {
      GNUNET_break (! rs->had_ri);
      report_row_inconsistency ("reserves_close",
                                rowid,
                                "target account not verified, auditor does not know reserve");
    }
    else if (0 != strcmp (rs->sender_account,
                          receiver_account))
    {
      report_row_inconsistency ("reserves_close",
                                rowid,
                                "target account does not match origin account");
    }
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Additional closing operation for reserve `%s' of %s\n",
              TALER_B2S (reserve_pub),
              TALER_amount2s (amount_with_fee));
  return GNUNET_OK;
}


/**
 * Function called with details about account merge requests that have been
 * made, with the goal of accounting for the merge fee paid by the reserve (if
 * applicable).
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
  struct ReserveContext *rc = cls;
  struct ReserveSummary *rs;
  enum GNUNET_DB_QueryStatus qs;

  /* should be monotonically increasing */
  GNUNET_assert (rowid >= TALER_ARL_USE_PP (reserves_account_merges_serial_id));
  TALER_ARL_USE_PP (reserves_account_merges_serial_id) = rowid + 1;
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
    struct TALER_AUDITORDB_BadSigLosses bsl = {
      .row_id = rowid,
      .operation = "account-merge",
      .loss = *purse_fee,
      .operation_specific_pub = reserve_pub->eddsa_pub
    };

    qs = TALER_ARL_adb->insert_bad_sig_losses (
      TALER_ARL_adb->cls,
      &bsl);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      // FIXME: error handling!
    }
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (reserves_total_bad_sig_loss),
                          &TALER_ARL_USE_AB (reserves_total_bad_sig_loss),
                          purse_fee);
    return GNUNET_OK;
  }
  if ((flags & TALER_WAMF_MERGE_MODE_MASK) !=
      TALER_WAMF_MODE_CREATE_WITH_PURSE_FEE)
    return GNUNET_OK; /* no impact on reserve balance */
  rs = setup_reserve (rc,
                      reserve_pub);
  if (NULL == rs)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (reserves_purse_fee_revenue),
                        &TALER_ARL_USE_AB (reserves_purse_fee_revenue),
                        purse_fee);
  TALER_ARL_amount_add (&rs->curr_balance.purse_fee_balance,
                        &rs->curr_balance.purse_fee_balance,
                        purse_fee);
  TALER_ARL_amount_add (&rs->total_out,
                        &rs->total_out,
                        purse_fee);
  return GNUNET_OK;
}


/**
 * Function called with details about a purse that was merged into an account.
 * Only updates the reserve balance, the actual verifications are done in the
 * purse helper.
 *
 * @param cls closure
 * @param rowid unique serial ID for the refund in our DB
 * @param purse_pub public key of the purse
 * @param reserve_pub which reserve is the purse credited to
 * @param purse_value what is the target value of the purse
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
purse_decision_cb (void *cls,
                   uint64_t rowid,
                   const struct TALER_PurseContractPublicKeyP *purse_pub,
                   const struct TALER_ReservePublicKeyP *reserve_pub,
                   const struct TALER_Amount *purse_value)
{
  struct ReserveContext *rc = cls;
  struct ReserveSummary *rs;

  GNUNET_assert (rowid >= TALER_ARL_USE_PP (
                   reserves_purse_decisions_serial_id)); /* should be monotonically increasing */
  TALER_ARL_USE_PP (reserves_purse_decisions_serial_id) = rowid + 1;
  rs = setup_reserve (rc,
                      reserve_pub);
  if (NULL == rs)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  TALER_ARL_amount_add (&rs->total_in,
                        &rs->total_in,
                        purse_value);
  return GNUNET_OK;
}


/**
 * Check that the reserve summary matches what the exchange database
 * thinks about the reserve, and update our own state of the reserve.
 *
 * Remove all reserves that we are happy with from the DB.
 *
 * @param cls our `struct ReserveContext`
 * @param key hash of the reserve public key
 * @param value a `struct ReserveSummary`
 * @return #GNUNET_OK to process more entries
 */
static enum GNUNET_GenericReturnValue
verify_reserve_balance (void *cls,
                        const struct GNUNET_HashCode *key,
                        void *value)
{
  struct ReserveContext *rc = cls;
  struct ReserveSummary *rs = value;
  struct TALER_Amount mbalance;
  struct TALER_Amount nbalance;
  enum GNUNET_DB_QueryStatus qs;
  enum GNUNET_GenericReturnValue ret;

  ret = GNUNET_OK;
  /* Check our reserve summary balance calculation shows that
     the reserve balance is acceptable (i.e. non-negative) */
  TALER_ARL_amount_add (&mbalance,
                        &rs->total_in,
                        &rs->prev_balance.reserve_balance);
  if (TALER_ARL_SR_INVALID_NEGATIVE ==
      TALER_ARL_amount_subtract_neg (&nbalance,
                                     &mbalance,
                                     &rs->total_out))
  {
    struct TALER_AUDITORDB_ReserveBalanceInsufficientInconsistency rbiil = {
      .reserve_pub = rs->reserve_pub.eddsa_pub,
      .inconsistency_gain = false
    };

    TALER_ARL_amount_subtract (&rbiil.inconsistency_amount,
                               &rs->total_out,
                               &mbalance);
    TALER_ARL_amount_add (&rs->curr_balance.reserve_loss,
                          &rs->prev_balance.reserve_loss,
                          &rbiil.inconsistency_amount);
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (reserves_reserve_loss),
                          &TALER_ARL_USE_AB (reserves_reserve_loss),
                          &rbiil.inconsistency_amount);
    qs = TALER_ARL_adb->insert_reserve_balance_insufficient_inconsistency (
      TALER_ARL_adb->cls,
      &rbiil);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      // FIXME: error handling!
    }
    /* Continue with a reserve balance of zero */
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (TALER_ARL_currency,
                                          &rs->curr_balance.reserve_balance));
  }
  else
  {
    /* Update remaining reserve balance! */
    rs->curr_balance.reserve_balance = nbalance;
  }

  if (internal_checks)
  {
    /* Now check OUR balance calculation vs. the one the exchange has
       in its database. This can only be done when we are doing an
       internal audit, as otherwise the balance of the 'reserves' table
       is not replicated at the auditor. */
    struct TALER_EXCHANGEDB_Reserve reserve;

    reserve.pub = rs->reserve_pub;
    qs = TALER_ARL_edb->reserves_get (TALER_ARL_edb->cls,
                                      &reserve);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    {
      /* If the exchange doesn't have this reserve in the summary, it
         is like the exchange 'lost' that amount from its records,
         making an illegitimate gain over the amount it dropped.
         We don't add the amount to some total simply because it is
         not an actualized gain and could be trivially corrected by
         restoring the summary. */
      struct TALER_AUDITORDB_ReserveBalanceInsufficientInconsistency rbiig = {
        .reserve_pub = rs->reserve_pub.eddsa_pub,
        .inconsistency_amount = nbalance,
        .inconsistency_gain = true
      };

      qs = TALER_ARL_adb->insert_reserve_balance_insufficient_inconsistency (
        TALER_ARL_adb->cls,
        &rbiig);

      if (qs < 0)
      {
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        // FIXME: error handling
      }
      if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
      {
        GNUNET_break (0);
        qs = GNUNET_DB_STATUS_HARD_ERROR;
      }
      rc->qs = qs;
    }
    else
    {
      /* Check that exchange's balance matches our expected balance for the reserve */
      if (0 != TALER_amount_cmp (&rs->curr_balance.reserve_balance,
                                 &reserve.balance))
      {

        struct TALER_Amount delta;

        if (0 < TALER_amount_cmp (&rs->curr_balance.reserve_balance,
                                  &reserve.balance))
        {
          /* balance > reserve.balance */
          TALER_ARL_amount_subtract (&delta,
                                     &rs->curr_balance.reserve_balance,
                                     &reserve.balance);
          TALER_ARL_amount_add (&TALER_ARL_USE_AB (
                                  total_balance_summary_delta_plus),
                                &TALER_ARL_USE_AB (
                                  total_balance_summary_delta_plus),
                                &delta);
        }
        else
        {
          /* balance < reserve.balance */
          TALER_ARL_amount_subtract (&delta,
                                     &reserve.balance,
                                     &rs->curr_balance.reserve_balance);
          TALER_ARL_amount_add (&TALER_ARL_USE_AB (
                                  total_balance_summary_delta_minus),
                                &TALER_ARL_USE_AB (
                                  total_balance_summary_delta_minus),
                                &delta);
        }

        {
          struct TALER_AUDITORDB_ReserveBalanceInsufficientInconsistency rbiig =
          {
            .reserve_pub = rs->reserve_pub.eddsa_pub,
            .inconsistency_amount = nbalance,
            .inconsistency_gain = true
          };

          qs = TALER_ARL_adb->insert_reserve_balance_insufficient_inconsistency
               (
            TALER_ARL_adb->cls,
            &rbiig);
        }
        if (qs < 0)
        {
          GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
          // FIXME: error handling
        }

        {
          struct TALER_AUDITORDB_ReserveBalanceSummaryWrongInconsistency rbswi =
          {
            .exchange_amount = reserve.balance,
            .auditor_amount = rs->curr_balance.reserve_balance,
            .reserve_pub = rs->reserve_pub
          };

          qs = TALER_ARL_adb->insert_reserve_balance_summary_wrong_inconsistency
               (
            TALER_ARL_adb->cls,
            &rbswi);
        }
        if (qs < 0)
        {
          GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
          // FIXME: error handling
        }
      }
    }
  }   /* end of 'if (internal_checks)' */

  /* Check that reserve is being closed if it is past its expiration date
     (and the closing fee would not exceed the remaining balance) */
  if (GNUNET_TIME_relative_cmp (CLOSING_GRACE_PERIOD,
                                <,
                                GNUNET_TIME_absolute_get_duration (
                                  rs->a_expiration_date.abs_time)))
  {
    /* Reserve is expired */
    struct TALER_Amount cfee;

    if ( (NULL != rs->sender_account) &&
         (GNUNET_OK ==
          get_closing_fee (rs->sender_account,
                           rs->a_expiration_date,
                           &cfee)) )
    {
      /* We got the closing fee */
      if (1 == TALER_amount_cmp (&nbalance,
                                 &cfee))
      {
        struct TALER_AUDITORDB_ReserveNotClosedInconsistency rnci = {
          .reserve_pub = rs->reserve_pub,
          .expiration_time = rs->a_expiration_date.abs_time,
          .balance = nbalance

        };

        /* remaining balance (according to us) exceeds closing fee */
        TALER_ARL_amount_add (&TALER_ARL_USE_AB (
                                total_balance_reserve_not_closed),
                              &TALER_ARL_USE_AB (
                                total_balance_reserve_not_closed),
                              &rnci.balance);
        qs = TALER_ARL_adb->insert_reserve_not_closed_inconsistency (
          TALER_ARL_adb->cls,
          &rnci);

        if (qs < 0)
        {
          GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
          // FIXME: error handling
        }
      }
    }
    else
    {
      /* We failed to determine the closing fee, complain! */
      // TODO: fix correctly and not just comment out
      // nbalance is set to invalid and there is never a check happening when working further with nbalance,
      // why so and why adding those balances here? or what's the usecase of setting nbalance to zero?
      /*
        TALER_ARL_amount_add (&TALER_ARL_USE_AB(total_balance_reserve_not_closed),
        &TALER_ARL_USE_AB(total_balance_reserve_not_closed),
                            &nbalance);*/
      struct TALER_AUDITORDB_ReserveNotClosedInconsistency rncid = {
        .reserve_pub = rs->reserve_pub,
        .balance = nbalance,
        .expiration_time = rs->a_expiration_date.abs_time,
        .diagnostic = "could not determine closing fee"
      };

      qs = TALER_ARL_adb->insert_reserve_not_closed_inconsistency (
        TALER_ARL_adb->cls,
        &rncid);
      if (qs < 0)
      {
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        // FIXME: error handling
      }
    }
  }
  /* We already computed the 'new' balance in 'curr_balance'
     to include the previous balance, so this one is just
     an assignment, not adding up! */
  rs->prev_balance.reserve_balance = rs->curr_balance.reserve_balance;

  /* Add up new totals to previous totals  */
  TALER_ARL_amount_add (&rs->prev_balance.reserve_loss,
                        &rs->prev_balance.reserve_loss,
                        &rs->curr_balance.reserve_loss);
  TALER_ARL_amount_add (&rs->prev_balance.withdraw_fee_balance,
                        &rs->prev_balance.withdraw_fee_balance,
                        &rs->curr_balance.withdraw_fee_balance);
  TALER_ARL_amount_add (&rs->prev_balance.close_fee_balance,
                        &rs->prev_balance.close_fee_balance,
                        &rs->curr_balance.close_fee_balance);
  TALER_ARL_amount_add (&rs->prev_balance.purse_fee_balance,
                        &rs->prev_balance.purse_fee_balance,
                        &rs->curr_balance.purse_fee_balance);
  TALER_ARL_amount_add (&rs->prev_balance.open_fee_balance,
                        &rs->prev_balance.open_fee_balance,
                        &rs->curr_balance.open_fee_balance);
  TALER_ARL_amount_add (&rs->prev_balance.history_fee_balance,
                        &rs->prev_balance.history_fee_balance,
                        &rs->curr_balance.history_fee_balance);
  /* Update global balance: add incoming first, then try
     to subtract outgoing... */
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (reserves_reserve_total_balance),
                        &TALER_ARL_USE_AB (reserves_reserve_total_balance),
                        &rs->total_in);
  {
    struct TALER_Amount r;

    if (TALER_ARL_SR_INVALID_NEGATIVE ==
        TALER_ARL_amount_subtract_neg (&r,
                                       &TALER_ARL_USE_AB (
                                         reserves_reserve_total_balance),
                                       &rs->total_out))
    {
      /* We could not reduce our total balance, i.e. exchange allowed IN TOTAL (!)
         to be withdrawn more than it was IN TOTAL ever given (exchange balance
         went negative!).  Woopsie. Calculate how badly it went and log. */
      report_amount_arithmetic_inconsistency ("global escrow balance",
                                              0,
                                              &TALER_ARL_USE_AB (
                                                reserves_reserve_total_balance),                   /* what we had */
                                              &rs->total_out,   /* what we needed */
                                              0 /* specific profit/loss does not apply to the total summary */
                                              );
      /* We unexpectedly went negative, so a sane value to continue from
         would be zero. */
      GNUNET_assert (GNUNET_OK ==
                     TALER_amount_set_zero (TALER_ARL_currency,
                                            &TALER_ARL_USE_AB (
                                              reserves_reserve_total_balance)));
    }
    else
    {
      TALER_ARL_USE_AB (reserves_reserve_total_balance) = r;
    }
  }
  if (TALER_amount_is_zero (&rs->prev_balance.reserve_balance))
  {
    /* balance is zero, drop reserve details (and then do not update/insert) */
    if (rs->had_ri)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Final balance of reserve `%s' is zero, dropping it\n",
                  TALER_B2S (&rs->reserve_pub));
      qs = TALER_ARL_adb->del_reserve_info (TALER_ARL_adb->cls,
                                            &rs->reserve_pub);
      if (0 >= qs)
      {
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        ret = GNUNET_SYSERR;
        rc->qs = qs;
      }
    }
    else
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Final balance of reserve `%s' is zero, no need to remember it\n",
                  TALER_B2S (&rs->reserve_pub));
    }
  }
  else
  {
    /* balance is non-zero, persist for future audits */
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Remembering final balance of reserve `%s' as %s\n",
                TALER_B2S (&rs->reserve_pub),
                TALER_amount2s (&rs->prev_balance.reserve_balance));
    if (rs->had_ri)
      qs = TALER_ARL_adb->update_reserve_info (TALER_ARL_adb->cls,
                                               &rs->reserve_pub,
                                               &rs->prev_balance,
                                               rs->a_expiration_date);
    else
      qs = TALER_ARL_adb->insert_reserve_info (TALER_ARL_adb->cls,
                                               &rs->reserve_pub,
                                               &rs->prev_balance,
                                               rs->a_expiration_date,
                                               rs->sender_account);
    if (0 >= qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      ret = GNUNET_SYSERR;
      rc->qs = qs;
    }
  }
  /* now we can discard the cached entry */
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CONTAINER_multihashmap_remove (rc->reserves,
                                                       key,
                                                       rs));
  GNUNET_free (rs->sender_account);
  GNUNET_free (rs);
  return ret;
}


/**
 * Analyze reserves for being well-formed.
 *
 * @param cls NULL
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
analyze_reserves (void *cls)
{
  struct ReserveContext rc;
  enum GNUNET_DB_QueryStatus qs;

  (void) cls;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Analyzing reserves\n");
  qs = TALER_ARL_adb->get_auditor_progress (
    TALER_ARL_adb->cls,
    TALER_ARL_GET_PP (reserves_reserve_in_serial_id),
    TALER_ARL_GET_PP (reserves_reserve_out_serial_id),
    TALER_ARL_GET_PP (reserves_reserve_recoup_serial_id),
    TALER_ARL_GET_PP (reserves_reserve_open_serial_id),
    TALER_ARL_GET_PP (reserves_reserve_close_serial_id),
    TALER_ARL_GET_PP (reserves_purse_decisions_serial_id),
    TALER_ARL_GET_PP (reserves_account_merges_serial_id),
    TALER_ARL_GET_PP (reserves_history_requests_serial_id),
    NULL);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "First analysis using this auditor, starting audit from scratch\n");
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Resuming reserve audit at %llu/%llu/%llu/%llu/%llu/%llu/%llu/%llu\n",
                (unsigned long long) TALER_ARL_USE_PP (
                  reserves_reserve_in_serial_id),
                (unsigned long long) TALER_ARL_USE_PP (
                  reserves_reserve_out_serial_id),
                (unsigned long long) TALER_ARL_USE_PP (
                  reserves_reserve_recoup_serial_id),
                (unsigned long long) TALER_ARL_USE_PP (
                  reserves_reserve_open_serial_id),
                (unsigned long long) TALER_ARL_USE_PP (
                  reserves_reserve_close_serial_id),
                (unsigned long long) TALER_ARL_USE_PP (
                  reserves_purse_decisions_serial_id),
                (unsigned long long) TALER_ARL_USE_PP (
                  reserves_account_merges_serial_id),
                (unsigned long long) TALER_ARL_USE_PP (
                  reserves_history_requests_serial_id));
  }
  rc.qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  qs = TALER_ARL_adb->get_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_GET_AB (reserves_reserve_total_balance),
    TALER_ARL_GET_AB (reserves_reserve_loss),
    TALER_ARL_GET_AB (reserves_withdraw_fee_revenue),
    TALER_ARL_GET_AB (reserves_close_fee_revenue),
    TALER_ARL_GET_AB (reserves_purse_fee_revenue),
    TALER_ARL_GET_AB (reserves_open_fee_revenue),
    TALER_ARL_GET_AB (reserves_history_fee_revenue),
    TALER_ARL_GET_AB (reserves_total_bad_sig_loss),
    TALER_ARL_GET_AB (total_balance_reserve_not_closed),
    TALER_ARL_GET_AB (reserves_total_arithmetic_delta_plus),
    TALER_ARL_GET_AB (reserves_total_arithmetic_delta_minus),
    TALER_ARL_GET_AB (total_balance_summary_delta_minus),
    NULL);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  rc.reserves = GNUNET_CONTAINER_multihashmap_create (512,
                                                      GNUNET_NO);
  rc.revoked = GNUNET_CONTAINER_multihashmap_create (4,
                                                     GNUNET_NO);

  qs = TALER_ARL_edb->select_reserves_in_above_serial_id (
    TALER_ARL_edb->cls,
    TALER_ARL_USE_PP (reserves_reserve_in_serial_id),
    &handle_reserve_in,
    &rc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  qs = TALER_ARL_edb->select_withdrawals_above_serial_id (
    TALER_ARL_edb->cls,
    TALER_ARL_USE_PP (reserves_reserve_out_serial_id),
    &handle_reserve_out,
    &rc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  qs = TALER_ARL_edb->select_recoup_above_serial_id (
    TALER_ARL_edb->cls,
    TALER_ARL_USE_PP (reserves_reserve_recoup_serial_id),
    &handle_recoup_by_reserve,
    &rc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  qs = TALER_ARL_edb->select_reserve_open_above_serial_id (
    TALER_ARL_edb->cls,
    TALER_ARL_USE_PP (reserves_reserve_open_serial_id),
    &handle_reserve_open,
    &rc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  qs = TALER_ARL_edb->select_reserve_closed_above_serial_id (
    TALER_ARL_edb->cls,
    TALER_ARL_USE_PP (reserves_reserve_close_serial_id),
    &handle_reserve_closed,
    &rc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  /* process purse_decisions (to credit reserve) */
  if (0 >
      (qs = TALER_ARL_edb->select_purse_decisions_above_serial_id (
         TALER_ARL_edb->cls,
         TALER_ARL_USE_PP (reserves_purse_decisions_serial_id),
         false, /* only go for merged purses! */
         &purse_decision_cb,
         &rc)))
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  if (0 > rc.qs)
    return rc.qs;
  /* Charge purse fee! */

  qs = TALER_ARL_edb->select_account_merges_above_serial_id (
    TALER_ARL_edb->cls,
    TALER_ARL_USE_PP (reserves_account_merges_serial_id),
    &handle_account_merged,
    &rc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  GNUNET_CONTAINER_multihashmap_iterate (rc.reserves,
                                         &verify_reserve_balance,
                                         &rc);
  GNUNET_break (0 ==
                GNUNET_CONTAINER_multihashmap_size (rc.reserves));
  GNUNET_CONTAINER_multihashmap_destroy (rc.reserves);
  GNUNET_CONTAINER_multihashmap_destroy (rc.revoked);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != rc.qs)
    return qs;

  qs = TALER_ARL_adb->insert_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_AB (reserves_reserve_total_balance),
    TALER_ARL_SET_AB (reserves_reserve_loss),
    TALER_ARL_SET_AB (reserves_withdraw_fee_revenue),
    TALER_ARL_SET_AB (reserves_close_fee_revenue),
    TALER_ARL_SET_AB (reserves_purse_fee_revenue),
    TALER_ARL_SET_AB (reserves_open_fee_revenue),
    TALER_ARL_SET_AB (reserves_history_fee_revenue),
    TALER_ARL_SET_AB (reserves_total_bad_sig_loss),
    TALER_ARL_SET_AB (total_balance_reserve_not_closed),
    TALER_ARL_SET_AB (reserves_total_arithmetic_delta_plus),
    TALER_ARL_SET_AB (reserves_total_arithmetic_delta_minus),
    TALER_ARL_SET_AB (total_balance_summary_delta_minus),
    NULL);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  qs = TALER_ARL_adb->update_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_AB (reserves_reserve_total_balance),
    TALER_ARL_SET_AB (reserves_reserve_loss),
    TALER_ARL_SET_AB (reserves_withdraw_fee_revenue),
    TALER_ARL_SET_AB (reserves_close_fee_revenue),
    TALER_ARL_SET_AB (reserves_purse_fee_revenue),
    TALER_ARL_SET_AB (reserves_open_fee_revenue),
    TALER_ARL_SET_AB (reserves_history_fee_revenue),
    TALER_ARL_SET_AB (reserves_total_bad_sig_loss),
    TALER_ARL_SET_AB (total_balance_reserve_not_closed),
    TALER_ARL_SET_AB (reserves_total_arithmetic_delta_plus),
    TALER_ARL_SET_AB (reserves_total_arithmetic_delta_minus),
    TALER_ARL_SET_AB (total_balance_summary_delta_minus),
    NULL);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  qs = TALER_ARL_adb->insert_auditor_progress (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_PP (reserves_reserve_in_serial_id),
    TALER_ARL_SET_PP (reserves_reserve_out_serial_id),
    TALER_ARL_SET_PP (reserves_reserve_recoup_serial_id),
    TALER_ARL_SET_PP (reserves_reserve_open_serial_id),
    TALER_ARL_SET_PP (reserves_reserve_close_serial_id),
    TALER_ARL_SET_PP (reserves_purse_decisions_serial_id),
    TALER_ARL_SET_PP (reserves_account_merges_serial_id),
    TALER_ARL_SET_PP (reserves_history_requests_serial_id),
    NULL);
  if (0 > qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  qs = TALER_ARL_adb->update_auditor_progress (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_PP (reserves_reserve_in_serial_id),
    TALER_ARL_SET_PP (reserves_reserve_out_serial_id),
    TALER_ARL_SET_PP (reserves_reserve_recoup_serial_id),
    TALER_ARL_SET_PP (reserves_reserve_open_serial_id),
    TALER_ARL_SET_PP (reserves_reserve_close_serial_id),
    TALER_ARL_SET_PP (reserves_purse_decisions_serial_id),
    TALER_ARL_SET_PP (reserves_account_merges_serial_id),
    TALER_ARL_SET_PP (reserves_history_requests_serial_id),
    NULL);
  if (0 > qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Concluded reserve audit step at %llu/%llu/%llu/%llu/%llu/%llu/%llu/%llu\n",
              (unsigned long long) TALER_ARL_USE_PP (
                reserves_reserve_in_serial_id),
              (unsigned long long) TALER_ARL_USE_PP (
                reserves_reserve_out_serial_id),
              (unsigned long long) TALER_ARL_USE_PP (
                reserves_reserve_recoup_serial_id),
              (unsigned long long) TALER_ARL_USE_PP (
                reserves_reserve_open_serial_id),
              (unsigned long long) TALER_ARL_USE_PP (
                reserves_reserve_close_serial_id),
              (unsigned long long) TALER_ARL_USE_PP (
                reserves_purse_decisions_serial_id),
              (unsigned long long) TALER_ARL_USE_PP (
                reserves_account_merges_serial_id),
              (unsigned long long) TALER_ARL_USE_PP (
                reserves_history_requests_serial_id));
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
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
              "Received notification to wake reserves helper\n");
  if (GNUNET_OK !=
      TALER_ARL_setup_sessions_and_run (&analyze_reserves,
                                        NULL))
  {
    GNUNET_SCHEDULER_shutdown ();
    global_ret = EXIT_FAILURE;
    return;
  }
}


/**
 * Function called on shutdown.
 */
static void
do_shutdown (void *cls)
{
  (void) cls;
  if (NULL != eh)
  {
    TALER_ARL_adb->event_listen_cancel (eh);
    eh = NULL;
  }
  TALER_ARL_done ();
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
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Launching reserves auditor\n");
  if (GNUNET_OK !=
      TALER_ARL_init (c))
  {
    global_ret = EXIT_FAILURE;
    return;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (TALER_ARL_cfg,
                                           "exchangedb",
                                           "IDLE_RESERVE_EXPIRATION_TIME",
                                           &idle_reserve_expiration_time))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb",
                               "IDLE_RESERVE_EXPIRATION_TIME");
    GNUNET_SCHEDULER_shutdown ();
    global_ret = EXIT_FAILURE;
    return;
  }
  if (test_mode != 1)
  {
    struct GNUNET_DB_EventHeaderP es = {
      .size = htons (sizeof (es)),
      .type = htons (TALER_DBEVENT_EXCHANGE_AUDITOR_WAKE_HELPER_RESERVES)
    };

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Running helper indefinitely\n");
    eh = TALER_ARL_adb->event_listen (TALER_ARL_adb->cls,
                                      &es,
                                      GNUNET_TIME_UNIT_FOREVER_REL,
                                      &db_notify,
                                      NULL);
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting audit\n");
  if (GNUNET_OK !=
      TALER_ARL_setup_sessions_and_run (&analyze_reserves,
                                        NULL))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Audit failed\n");
    GNUNET_SCHEDULER_shutdown ();
    global_ret = EXIT_FAILURE;
    return;
  }
}


/**
 * The main function to check the database's handling of reserves.
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
    "taler-helper-auditor-reserves",
    gettext_noop ("Audit Taler exchange reserve handling"),
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


/* end of taler-helper-auditor-reserves.c */
