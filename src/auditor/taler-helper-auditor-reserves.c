/*
  This file is part of TALER
  Copyright (C) 2016-2020 Taler Systems SA

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
#include "taler_json_lib.h"
#include "taler_bank_service.h"
#include "taler_signatures.h"
#include "report-lib.h"


/**
 * Use a 1 day grace period to deal with clocks not being perfectly synchronized.
 */
#define CLOSING_GRACE_PERIOD GNUNET_TIME_UNIT_DAYS

/**
 * Return value from main().
 */
static int global_ret;

/**
 * After how long should idle reserves be closed?
 */
static struct GNUNET_TIME_Relative idle_reserve_expiration_time;

/**
 * Checkpointing our progress for reserves.
 */
static struct TALER_AUDITORDB_ProgressPointReserve ppr;

/**
 * Checkpointing our progress for reserves.
 */
static struct TALER_AUDITORDB_ProgressPointReserve ppr_start;

/**
 * Array of reports about row inconsitencies.
 */
static json_t *report_row_inconsistencies;

/**
 * Array of reports about the denomination key not being
 * valid at the time of withdrawal.
 */
static json_t *denomination_key_validity_withdraw_inconsistencies;

/**
 * Array of reports about reserve balance insufficient inconsitencies.
 */
static json_t *report_reserve_balance_insufficient_inconsistencies;

/**
 * Total amount reserves were charged beyond their balance.
 */
static struct TALER_Amount total_balance_insufficient_loss;

/**
 * Array of reports about reserve balance summary wrong in database.
 */
static json_t *report_reserve_balance_summary_wrong_inconsistencies;

/**
 * Total delta between expected and stored reserve balance summaries,
 * for positive deltas.
 */
static struct TALER_Amount total_balance_summary_delta_plus;

/**
 * Total delta between expected and stored reserve balance summaries,
 * for negative deltas.
 */
static struct TALER_Amount total_balance_summary_delta_minus;

/**
 * Array of reports about reserve's not being closed inconsitencies.
 */
static json_t *report_reserve_not_closed_inconsistencies;

/**
 * Total amount affected by reserves not having been closed on time.
 */
static struct TALER_Amount total_balance_reserve_not_closed;

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
 * Expected balance in the escrow account.
 */
static struct TALER_Amount total_escrow_balance;

/**
 * Recoups we made on denominations that were not revoked (!?).
 */
static struct TALER_Amount total_irregular_recoups;

/**
 * Total withdraw fees earned.
 */
static struct TALER_Amount total_withdraw_fee_income;

/**
 * Array of reports about coin operations with bad signatures.
 */
static json_t *report_bad_sig_losses;

/**
 * Total amount lost by operations for which signatures were invalid.
 */
static struct TALER_Amount total_bad_sig_loss;


/* ***************************** Report logic **************************** */


/**
 * Report a (serious) inconsistency in the exchange's database with
 * respect to calculations involving amounts.
 *
 * @param operation what operation had the inconsistency
 * @param rowid affected row, UINT64_MAX if row is missing
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
                    json_pack ("{s:s, s:I, s:o, s:o, s:I}",
                               "operation", operation,
                               "rowid", (json_int_t) rowid,
                               "exchange", TALER_JSON_from_amount (exchange),
                               "auditor", TALER_JSON_from_amount (auditor),
                               "profitable", (json_int_t) profitable));
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
 * @param rowid affected row, UINT64_MAX if row is missing
 * @param diagnostic message explaining the problem
 */
static void
report_row_inconsistency (const char *table,
                          uint64_t rowid,
                          const char *diagnostic)
{
  TALER_ARL_report (report_row_inconsistencies,
                    json_pack ("{s:s, s:I, s:s}",
                               "table", table,
                               "row", (json_int_t) rowid,
                               "diagnostic", diagnostic));
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
   * Sum of withdraw fees encountered during this transaction.
   */
  struct TALER_Amount total_fee;

  /**
   * Previous balance of the reserve as remembered by the auditor.
   * (updated based on @e total_in and @e total_out at the end).
   */
  struct TALER_Amount balance_at_previous_audit;

  /**
   * Previous withdraw fee balance of the reserve, as remembered by the auditor.
   * (updated based on @e total_fee at the end).
   */
  struct TALER_Amount a_withdraw_fee_balance;

  /**
   * Previous reserve expiration data, as remembered by the auditor.
   * (updated on-the-fly in #handle_reserve_in()).
   */
  struct GNUNET_TIME_Absolute a_expiration_date;

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
  int had_ri;

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
                                        TALER_ARL_asession,
                                        &rs->reserve_pub,
                                        &TALER_ARL_master_pub,
                                        &rowid,
                                        &rs->balance_at_previous_audit,
                                        &rs->a_withdraw_fee_balance,
                                        &rs->a_expiration_date,
                                        &rs->sender_account);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    rs->had_ri = GNUNET_NO;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (rs->total_in.currency,
                                          &rs->balance_at_previous_audit));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (rs->total_in.currency,
                                          &rs->a_withdraw_fee_balance));
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Creating fresh reserve `%s' with starting balance %s\n",
                TALER_B2S (&rs->reserve_pub),
                TALER_amount2s (&rs->balance_at_previous_audit));
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }
  rs->had_ri = GNUNET_YES;
  if ( (GNUNET_YES !=
        TALER_amount_cmp_currency (&rs->balance_at_previous_audit,
                                   &rs->a_withdraw_fee_balance)) ||
       (GNUNET_YES !=
        TALER_amount_cmp_currency (&rs->total_in,
                                   &rs->balance_at_previous_audit)) )
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Auditor remembers reserve `%s' has balance %s\n",
              TALER_B2S (&rs->reserve_pub),
              TALER_amount2s (&rs->balance_at_previous_audit));
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
static int
handle_reserve_in (void *cls,
                   uint64_t rowid,
                   const struct TALER_ReservePublicKeyP *reserve_pub,
                   const struct TALER_Amount *credit,
                   const char *sender_account_details,
                   uint64_t wire_reference,
                   struct GNUNET_TIME_Absolute execution_date)
{
  struct ReserveContext *rc = cls;
  struct GNUNET_HashCode key;
  struct ReserveSummary *rs;
  struct GNUNET_TIME_Absolute expiry;
  enum GNUNET_DB_QueryStatus qs;

  (void) wire_reference;
  /* should be monotonically increasing */
  GNUNET_assert (rowid >= ppr.last_reserve_in_serial_id);
  ppr.last_reserve_in_serial_id = rowid + 1;

  GNUNET_CRYPTO_hash (reserve_pub,
                      sizeof (*reserve_pub),
                      &key);
  rs = GNUNET_CONTAINER_multihashmap_get (rc->reserves,
                                          &key);
  if (NULL == rs)
  {
    rs = GNUNET_new (struct ReserveSummary);
    rs->sender_account = GNUNET_strdup (sender_account_details);
    rs->reserve_pub = *reserve_pub;
    rs->total_in = *credit;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (credit->currency,
                                          &rs->total_out));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (credit->currency,
                                          &rs->total_fee));
    if (0 > (qs = load_auditor_reserve_summary (rs)))
    {
      GNUNET_break (0);
      GNUNET_free (rs);
      rc->qs = qs;
      return GNUNET_SYSERR;
    }
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CONTAINER_multihashmap_put (rc->reserves,
                                                      &key,
                                                      rs,
                                                      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  }
  else
  {
    TALER_ARL_amount_add (&rs->total_in,
                          &rs->total_in,
                          credit);
    if (NULL == rs->sender_account)
      rs->sender_account = GNUNET_strdup (sender_account_details);
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Additional incoming wire transfer for reserve `%s' of %s\n",
              TALER_B2S (reserve_pub),
              TALER_amount2s (credit));
  expiry = GNUNET_TIME_absolute_add (execution_date,
                                     idle_reserve_expiration_time);
  rs->a_expiration_date = GNUNET_TIME_absolute_max (rs->a_expiration_date,
                                                    expiry);
  if (TALER_ARL_do_abort ())
    return GNUNET_SYSERR;
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
static int
handle_reserve_out (void *cls,
                    uint64_t rowid,
                    const struct GNUNET_HashCode *h_blind_ev,
                    const struct TALER_DenominationPublicKey *denom_pub,
                    const struct TALER_ReservePublicKeyP *reserve_pub,
                    const struct TALER_ReserveSignatureP *reserve_sig,
                    struct GNUNET_TIME_Absolute execution_date,
                    const struct TALER_Amount *amount_with_fee)
{
  struct ReserveContext *rc = cls;
  struct GNUNET_HashCode key;
  struct ReserveSummary *rs;
  const struct TALER_DenominationKeyValidityPS *issue;
  struct TALER_Amount withdraw_fee;
  struct TALER_Amount auditor_value;
  struct TALER_Amount auditor_amount_with_fee;
  struct GNUNET_TIME_Absolute valid_start;
  struct GNUNET_TIME_Absolute expire_withdraw;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_WithdrawRequestPS wsrd = {
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW),
    .purpose.size = htonl (sizeof (wsrd)),
    .reserve_pub = *reserve_pub,
    .h_coin_envelope = *h_blind_ev
  };

  /* should be monotonically increasing */
  GNUNET_assert (rowid >= ppr.last_reserve_out_serial_id);
  ppr.last_reserve_out_serial_id = rowid + 1;

  /* lookup denomination pub data (make sure denom_pub is valid, establish fees);
     initializes wsrd.h_denomination_pub! */
  qs = TALER_ARL_get_denomination_info (denom_pub,
                                        &issue,
                                        &wsrd.h_denomination_pub);
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
    if (TALER_ARL_do_abort ())
      return GNUNET_SYSERR;
    return GNUNET_OK;
  }

  /* check that execution date is within withdraw range for denom_pub  */
  valid_start = GNUNET_TIME_absolute_ntoh (issue->start);
  expire_withdraw = GNUNET_TIME_absolute_ntoh (issue->expire_withdraw);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Checking withdraw timing: %llu, expire: %llu, timing: %llu\n",
              (unsigned long long) valid_start.abs_value_us,
              (unsigned long long) expire_withdraw.abs_value_us,
              (unsigned long long) execution_date.abs_value_us);
  if ( (valid_start.abs_value_us > execution_date.abs_value_us) ||
       (expire_withdraw.abs_value_us < execution_date.abs_value_us) )
  {
    TALER_ARL_report (denomination_key_validity_withdraw_inconsistencies,
                      json_pack ("{s:I, s:o, s:o, s:o}",
                                 "row", (json_int_t) rowid,
                                 "execution_date",
                                 TALER_ARL_json_from_time_abs (execution_date),
                                 "reserve_pub", GNUNET_JSON_from_data_auto (
                                   reserve_pub),
                                 "denompub_h", GNUNET_JSON_from_data_auto (
                                   &wsrd.h_denomination_pub)));
  }

  /* check reserve_sig (first: setup remaining members of wsrd) */
  TALER_amount_hton (&wsrd.amount_with_fee,
                     amount_with_fee);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW,
                                  &wsrd,
                                  &reserve_sig->eddsa_signature,
                                  &reserve_pub->eddsa_pub))
  {
    TALER_ARL_report (report_bad_sig_losses,
                      json_pack ("{s:s, s:I, s:o, s:o}",
                                 "operation", "withdraw",
                                 "row", (json_int_t) rowid,
                                 "loss", TALER_JSON_from_amount (
                                   amount_with_fee),
                                 "key_pub", GNUNET_JSON_from_data_auto (
                                   reserve_pub)));
    TALER_ARL_amount_add (&total_bad_sig_loss,
                          &total_bad_sig_loss,
                          amount_with_fee);
    if (TALER_ARL_do_abort ())
      return GNUNET_SYSERR;
    return GNUNET_OK;   /* exit function here, we cannot add this to the legitimate withdrawals */
  }

  TALER_amount_ntoh (&withdraw_fee,
                     &issue->fee_withdraw);
  TALER_amount_ntoh (&auditor_value,
                     &issue->value);
  TALER_ARL_amount_add (&auditor_amount_with_fee,
                        &auditor_value,
                        &withdraw_fee);
  if (0 !=
      TALER_amount_cmp (&auditor_amount_with_fee,
                        amount_with_fee))
  {
    report_row_inconsistency ("withdraw",
                              rowid,
                              "amount with fee from exchange does not match denomination value plus fee");
  }


  GNUNET_CRYPTO_hash (reserve_pub,
                      sizeof (*reserve_pub),
                      &key);
  rs = GNUNET_CONTAINER_multihashmap_get (rc->reserves,
                                          &key);
  if (NULL == rs)
  {
    rs = GNUNET_new (struct ReserveSummary);
    rs->reserve_pub = *reserve_pub;
    rs->total_out = auditor_amount_with_fee;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (amount_with_fee->currency,
                                          &rs->total_in));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (amount_with_fee->currency,
                                          &rs->total_fee));
    qs = load_auditor_reserve_summary (rs);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_free (rs);
      rc->qs = qs;
      return GNUNET_SYSERR;
    }
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CONTAINER_multihashmap_put (rc->reserves,
                                                      &key,
                                                      rs,
                                                      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  }
  else
  {
    TALER_ARL_amount_add (&rs->total_out,
                          &rs->total_out,
                          &auditor_amount_with_fee);
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Reserve `%s' reduced by %s from withdraw\n",
              TALER_B2S (reserve_pub),
              TALER_amount2s (&auditor_amount_with_fee));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Increasing withdraw profits by fee %s\n",
              TALER_amount2s (&withdraw_fee));
  TALER_ARL_amount_add (&rs->total_fee,
                        &rs->total_fee,
                        &withdraw_fee);
  if (TALER_ARL_do_abort ())
    return GNUNET_SYSERR;
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
static int
handle_recoup_by_reserve (
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Absolute timestamp,
  const struct TALER_Amount *amount,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_CoinPublicInfo *coin,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  const struct TALER_DenominationBlindingKeyP *coin_blind)
{
  struct ReserveContext *rc = cls;
  struct GNUNET_HashCode key;
  struct ReserveSummary *rs;
  struct GNUNET_TIME_Absolute expiry;
  struct TALER_MasterSignatureP msig;
  uint64_t rev_rowid;
  enum GNUNET_DB_QueryStatus qs;
  const char *rev;

  (void) denom_pub;
  /* should be monotonically increasing */
  GNUNET_assert (rowid >= ppr.last_reserve_recoup_serial_id);
  ppr.last_reserve_recoup_serial_id = rowid + 1;
  /* We know that denom_pub matches denom_pub_hash because this
     is how the SQL statement joined the tables. */
  {
    struct TALER_RecoupRequestPS pr = {
      .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_RECOUP),
      .purpose.size = htonl (sizeof (pr)),
      .h_denom_pub = coin->denom_pub_hash,
      .coin_pub = coin->coin_pub,
      .coin_blind = *coin_blind
    };

    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_RECOUP,
                                    &pr,
                                    &coin_sig->eddsa_signature,
                                    &coin->coin_pub.eddsa_pub))
    {
      TALER_ARL_report (report_bad_sig_losses,
                        json_pack ("{s:s, s:I, s:o, s:o}",
                                   "operation", "recoup",
                                   "row", (json_int_t) rowid,
                                   "loss", TALER_JSON_from_amount (amount),
                                   "key_pub", GNUNET_JSON_from_data_auto (
                                     &coin->coin_pub)));
      TALER_ARL_amount_add (&total_bad_sig_loss,
                            &total_bad_sig_loss,
                            amount);
    }
  }

  /* check that the coin was eligible for recoup!*/
  rev = GNUNET_CONTAINER_multihashmap_get (rc->revoked,
                                           &coin->denom_pub_hash);
  if (NULL == rev)
  {
    qs = TALER_ARL_edb->get_denomination_revocation (TALER_ARL_edb->cls,
                                                     TALER_ARL_esession,
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
      TALER_ARL_amount_add (&total_irregular_recoups,
                            &total_irregular_recoups,
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
      GNUNET_assert (GNUNET_OK ==
                     GNUNET_CONTAINER_multihashmap_put (rc->revoked,
                                                        &coin->denom_pub_hash,
                                                        (void *) rev,
                                                        GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
    }
  }
  else
  {
    rev_rowid = 0; /* reported elsewhere */
  }
  if ( (NULL != rev) &&
       (0 == strcmp (rev, "master signature invalid")) )
  {
    TALER_ARL_report (report_bad_sig_losses,
                      json_pack ("{s:s, s:I, s:o, s:o}",
                                 "operation", "recoup-master",
                                 "row", (json_int_t) rev_rowid,
                                 "loss", TALER_JSON_from_amount (amount),
                                 "key_pub", GNUNET_JSON_from_data_auto (
                                   &TALER_ARL_master_pub)));
    TALER_ARL_amount_add (&total_bad_sig_loss,
                          &total_bad_sig_loss,
                          amount);
  }

  GNUNET_CRYPTO_hash (reserve_pub,
                      sizeof (*reserve_pub),
                      &key);
  rs = GNUNET_CONTAINER_multihashmap_get (rc->reserves,
                                          &key);
  if (NULL == rs)
  {
    rs = GNUNET_new (struct ReserveSummary);
    rs->reserve_pub = *reserve_pub;
    rs->total_in = *amount;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (amount->currency,
                                          &rs->total_out));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (amount->currency,
                                          &rs->total_fee));
    qs = load_auditor_reserve_summary (rs);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_free (rs);
      rc->qs = qs;
      return GNUNET_SYSERR;
    }
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CONTAINER_multihashmap_put (rc->reserves,
                                                      &key,
                                                      rs,
                                                      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  }
  else
  {
    TALER_ARL_amount_add (&rs->total_in,
                          &rs->total_in,
                          amount);
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Additional /recoup value to for reserve `%s' of %s\n",
              TALER_B2S (reserve_pub),
              TALER_amount2s (amount));
  expiry = GNUNET_TIME_absolute_add (timestamp,
                                     idle_reserve_expiration_time);
  rs->a_expiration_date = GNUNET_TIME_absolute_max (rs->a_expiration_date,
                                                    expiry);
  if (TALER_ARL_do_abort ())
    return GNUNET_SYSERR;
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
static int
get_closing_fee (const char *receiver_account,
                 struct GNUNET_TIME_Absolute atime,
                 struct TALER_Amount *fee)
{
  struct TALER_MasterSignatureP master_sig;
  struct GNUNET_TIME_Absolute start_date;
  struct GNUNET_TIME_Absolute end_date;
  struct TALER_Amount wire_fee;
  char *method;

  method = TALER_payto_get_method (receiver_account);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Method is `%s'\n",
              method);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      TALER_ARL_edb->get_wire_fee (TALER_ARL_edb->cls,
                                   TALER_ARL_esession,
                                   method,
                                   atime,
                                   &start_date,
                                   &end_date,
                                   &wire_fee,
                                   fee,
                                   &master_sig))
  {
    char *diag;

    GNUNET_asprintf (&diag,
                     "closing fee for `%s' unavailable at %s\n",
                     method,
                     GNUNET_STRINGS_absolute_time_to_string (atime));
    report_row_inconsistency ("closing-fee",
                              atime.abs_value_us,
                              diag);
    GNUNET_free (diag);
    GNUNET_free (method);
    return GNUNET_SYSERR;
  }
  GNUNET_free (method);
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
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
handle_reserve_closed (
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Absolute execution_date,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *closing_fee,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const char *receiver_account,
  const struct TALER_WireTransferIdentifierRawP *transfer_details)
{
  struct ReserveContext *rc = cls;
  struct GNUNET_HashCode key;
  struct ReserveSummary *rs;
  enum GNUNET_DB_QueryStatus qs;

  (void) transfer_details;
  /* should be monotonically increasing */
  GNUNET_assert (rowid >= ppr.last_reserve_close_serial_id);
  ppr.last_reserve_close_serial_id = rowid + 1;

  GNUNET_CRYPTO_hash (reserve_pub,
                      sizeof (*reserve_pub),
                      &key);
  rs = GNUNET_CONTAINER_multihashmap_get (rc->reserves,
                                          &key);
  if (NULL == rs)
  {
    rs = GNUNET_new (struct ReserveSummary);
    rs->reserve_pub = *reserve_pub;
    rs->total_out = *amount_with_fee;
    rs->total_fee = *closing_fee;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (amount_with_fee->currency,
                                          &rs->total_in));
    qs = load_auditor_reserve_summary (rs);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_free (rs);
      rc->qs = qs;
      return GNUNET_SYSERR;
    }
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CONTAINER_multihashmap_put (rc->reserves,
                                                      &key,
                                                      rs,
                                                      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  }
  else
  {
    struct TALER_Amount expected_fee;

    TALER_ARL_amount_add (&rs->total_out,
                          &rs->total_out,
                          amount_with_fee);
    TALER_ARL_amount_add (&rs->total_fee,
                          &rs->total_fee,
                          closing_fee);
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
  if (NULL == rs->sender_account)
  {
    GNUNET_break (GNUNET_NO == rs->had_ri);
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
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Additional closing operation for reserve `%s' of %s\n",
              TALER_B2S (reserve_pub),
              TALER_amount2s (amount_with_fee));
  if (TALER_ARL_do_abort ())
    return GNUNET_SYSERR;
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
static int
verify_reserve_balance (void *cls,
                        const struct GNUNET_HashCode *key,
                        void *value)
{
  struct ReserveContext *rc = cls;
  struct ReserveSummary *rs = value;
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct TALER_Amount balance;
  struct TALER_Amount nbalance;
  enum GNUNET_DB_QueryStatus qs;
  int ret;

  ret = GNUNET_OK;
  /* Check our reserve summary balance calculation shows that
     the reserve balance is acceptable (i.e. non-negative) */
  TALER_ARL_amount_add (&balance,
                        &rs->total_in,
                        &rs->balance_at_previous_audit);
  if (TALER_ARL_SR_INVALID_NEGATIVE ==
      TALER_ARL_amount_subtract_neg (&nbalance,
                                     &balance,
                                     &rs->total_out))
  {
    struct TALER_Amount loss;

    TALER_ARL_amount_subtract (&loss,
                               &rs->total_out,
                               &balance);
    TALER_ARL_amount_add (&total_balance_insufficient_loss,
                          &total_balance_insufficient_loss,
                          &loss);
    TALER_ARL_report (report_reserve_balance_insufficient_inconsistencies,
                      json_pack ("{s:o, s:o}",
                                 "reserve_pub",
                                 GNUNET_JSON_from_data_auto (&rs->reserve_pub),
                                 "loss",
                                 TALER_JSON_from_amount (&loss)));
    /* Continue with a reserve balance of zero */
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (balance.currency,
                                          &nbalance));
  }

  /* Now check OUR balance calculation vs. the one the exchange has
     in its database */
  reserve.pub = rs->reserve_pub;
  qs = TALER_ARL_edb->reserves_get (TALER_ARL_edb->cls,
                                    TALER_ARL_esession,
                                    &reserve);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    /* If the exchange doesn't have this reserve in the summary, it
       is like the exchange 'lost' that amount from its records,
       making an illegitimate gain over the amount it dropped.
       We don't add the amount to some total simply because it is
       not an actualized gain and could be trivially corrected by
       restoring the summary. *///
    TALER_ARL_report (report_reserve_balance_insufficient_inconsistencies,
                      json_pack ("{s:o, s:o}",
                                 "reserve_pub",
                                 GNUNET_JSON_from_data_auto (&rs->reserve_pub),
                                 "gain",
                                 TALER_JSON_from_amount (&nbalance)));
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
    if (0 != TALER_amount_cmp (&nbalance,
                               &reserve.balance))
    {
      struct TALER_Amount delta;

      if (0 < TALER_amount_cmp (&nbalance,
                                &reserve.balance))
      {
        /* balance > reserve.balance */
        TALER_ARL_amount_subtract (&delta,
                                   &nbalance,
                                   &reserve.balance);
        TALER_ARL_amount_add (&total_balance_summary_delta_plus,
                              &total_balance_summary_delta_plus,
                              &delta);
      }
      else
      {
        /* balance < reserve.balance */
        TALER_ARL_amount_subtract (&delta,
                                   &reserve.balance,
                                   &nbalance);
        TALER_ARL_amount_add (&total_balance_summary_delta_minus,
                              &total_balance_summary_delta_minus,
                              &delta);
      }
      TALER_ARL_report (report_reserve_balance_summary_wrong_inconsistencies,
                        json_pack ("{s:o, s:o, s:o}",
                                   "reserve_pub",
                                   GNUNET_JSON_from_data_auto (
                                     &rs->reserve_pub),
                                   "exchange",
                                   TALER_JSON_from_amount (&reserve.balance),
                                   "auditor",
                                   TALER_JSON_from_amount (&nbalance)));
    }
  }

  /* Check that reserve is being closed if it is past its expiration date
     (and the closing fee would not exceed the remaining balance) */
  if (CLOSING_GRACE_PERIOD.rel_value_us <
      GNUNET_TIME_absolute_get_duration (rs->a_expiration_date).rel_value_us)
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
        /* remaining balance (according to us) exceeds closing fee */
        TALER_ARL_amount_add (&total_balance_reserve_not_closed,
                              &total_balance_reserve_not_closed,
                              &nbalance);
        TALER_ARL_report (report_reserve_not_closed_inconsistencies,
                          json_pack ("{s:o, s:o, s:o}",
                                     "reserve_pub",
                                     GNUNET_JSON_from_data_auto (
                                       &rs->reserve_pub),
                                     "balance",
                                     TALER_JSON_from_amount (&nbalance),
                                     "expiration_time",
                                     TALER_ARL_json_from_time_abs (
                                       rs->a_expiration_date)));
      }
    }
    else
    {
      /* We failed to determine the closing fee, complain! */
      TALER_ARL_amount_add (&total_balance_reserve_not_closed,
                            &total_balance_reserve_not_closed,
                            &nbalance);
      TALER_ARL_report (report_reserve_not_closed_inconsistencies,
                        json_pack ("{s:o, s:o, s:o, s:s}",
                                   "reserve_pub",
                                   GNUNET_JSON_from_data_auto (
                                     &rs->reserve_pub),
                                   "balance",
                                   TALER_JSON_from_amount (&nbalance),
                                   "expiration_time",
                                   TALER_ARL_json_from_time_abs (
                                     rs->a_expiration_date),
                                   "diagnostic",
                                   "could not determine closing fee"));
    }
  }

  /* Add withdraw fees we encountered to totals */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Reserve reserve `%s' made %s in withdraw fees\n",
              TALER_B2S (&rs->reserve_pub),
              TALER_amount2s (&rs->total_fee));
  TALER_ARL_amount_add (&rs->a_withdraw_fee_balance,
                        &rs->a_withdraw_fee_balance,
                        &rs->total_fee);
  TALER_ARL_amount_add (&total_escrow_balance,
                        &total_escrow_balance,
                        &rs->total_in);
  TALER_ARL_amount_add (&total_withdraw_fee_income,
                        &total_withdraw_fee_income,
                        &rs->total_fee);
  {
    struct TALER_Amount r;

    if (TALER_ARL_SR_INVALID_NEGATIVE ==
        TALER_ARL_amount_subtract_neg (&r,
                                       &total_escrow_balance,
                                       &rs->total_out))
    {
      /* We could not reduce our total balance, i.e. exchange allowed IN TOTAL (!)
         to be withdrawn more than it was IN TOTAL ever given (exchange balance
         went negative!).  Woopsie. Calculate how badly it went and log. */
      report_amount_arithmetic_inconsistency ("global escrow balance",
                                              UINT64_MAX,
                                              &total_escrow_balance, /* what we had */
                                              &rs->total_out, /* what we needed */
                                              0 /* specific profit/loss does not apply to the total summary */);
      /* We unexpectedly went negative, so a sane value to continue from
         would be zero. */
      GNUNET_assert (GNUNET_OK ==
                     TALER_amount_get_zero (TALER_ARL_currency,
                                            &total_escrow_balance));
    }
    else
    {
      total_escrow_balance = r;
    }
  }

  if ( (0ULL == balance.value) &&
       (0U == balance.fraction) )
  {
    /* balance is zero, drop reserve details (and then do not update/insert) */
    if (rs->had_ri)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Final balance of reserve `%s' is %s, dropping it\n",
                  TALER_B2S (&rs->reserve_pub),
                  TALER_amount2s (&nbalance));
      qs = TALER_ARL_adb->del_reserve_info (TALER_ARL_adb->cls,
                                            TALER_ARL_asession,
                                            &rs->reserve_pub,
                                            &TALER_ARL_master_pub);
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
                  "Final balance of reserve `%s' is %s, no need to remember it\n",
                  TALER_B2S (&rs->reserve_pub),
                  TALER_amount2s (&nbalance));
    }
  }
  else
  {
    /* balance is non-zero, persist for future audits */
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Remembering final balance of reserve `%s' as %s\n",
                TALER_B2S (&rs->reserve_pub),
                TALER_amount2s (&nbalance));
    if (rs->had_ri)
      qs = TALER_ARL_adb->update_reserve_info (TALER_ARL_adb->cls,
                                               TALER_ARL_asession,
                                               &rs->reserve_pub,
                                               &TALER_ARL_master_pub,
                                               &nbalance,
                                               &rs->a_withdraw_fee_balance,
                                               rs->a_expiration_date);
    else
      qs = TALER_ARL_adb->insert_reserve_info (TALER_ARL_adb->cls,
                                               TALER_ARL_asession,
                                               &rs->reserve_pub,
                                               &TALER_ARL_master_pub,
                                               &nbalance,
                                               &rs->a_withdraw_fee_balance,
                                               rs->a_expiration_date,
                                               rs->sender_account);
    if (0 >= qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      ret = GNUNET_SYSERR;
      rc->qs = qs;
    }
  }

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
  enum GNUNET_DB_QueryStatus qsx;
  enum GNUNET_DB_QueryStatus qs;
  enum GNUNET_DB_QueryStatus qsp;

  (void) cls;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Analyzing reserves\n");
  qsp = TALER_ARL_adb->get_auditor_progress_reserve (TALER_ARL_adb->cls,
                                                     TALER_ARL_asession,
                                                     &TALER_ARL_master_pub,
                                                     &ppr);
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
    ppr_start = ppr;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Resuming reserve audit at %llu/%llu/%llu/%llu\n",
                (unsigned long long) ppr.last_reserve_in_serial_id,
                (unsigned long long) ppr.last_reserve_out_serial_id,
                (unsigned long long) ppr.last_reserve_recoup_serial_id,
                (unsigned long long) ppr.last_reserve_close_serial_id);
  }
  rc.qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  qsx = TALER_ARL_adb->get_reserve_summary (TALER_ARL_adb->cls,
                                            TALER_ARL_asession,
                                            &TALER_ARL_master_pub,
                                            &total_escrow_balance,
                                            &total_withdraw_fee_income);
  if (qsx < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsx);
    return qsx;
  }
  rc.reserves = GNUNET_CONTAINER_multihashmap_create (512,
                                                      GNUNET_NO);
  rc.revoked = GNUNET_CONTAINER_multihashmap_create (4,
                                                     GNUNET_NO);

  qs = TALER_ARL_edb->select_reserves_in_above_serial_id (
    TALER_ARL_edb->cls,
    TALER_ARL_esession,
    ppr.last_reserve_in_serial_id,
    &handle_reserve_in,
    &rc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  qs = TALER_ARL_edb->select_withdrawals_above_serial_id (
    TALER_ARL_edb->cls,
    TALER_ARL_esession,
    ppr.last_reserve_out_serial_id,
    &handle_reserve_out,
    &rc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  qs = TALER_ARL_edb->select_recoup_above_serial_id (
    TALER_ARL_edb->cls,
    TALER_ARL_esession,
    ppr.last_reserve_recoup_serial_id,
    &handle_recoup_by_reserve,
    &rc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  qs = TALER_ARL_edb->select_reserve_closed_above_serial_id (
    TALER_ARL_edb->cls,
    TALER_ARL_esession,
    ppr.last_reserve_close_serial_id,
    &handle_reserve_closed,
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

  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsx)
  {
    qs = TALER_ARL_adb->insert_reserve_summary (TALER_ARL_adb->cls,
                                                TALER_ARL_asession,
                                                &TALER_ARL_master_pub,
                                                &total_escrow_balance,
                                                &total_withdraw_fee_income);
  }
  else
  {
    qs = TALER_ARL_adb->update_reserve_summary (TALER_ARL_adb->cls,
                                                TALER_ARL_asession,
                                                &TALER_ARL_master_pub,
                                                &total_escrow_balance,
                                                &total_withdraw_fee_income);
  }
  if (0 >= qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qsp)
    qs = TALER_ARL_adb->update_auditor_progress_reserve (TALER_ARL_adb->cls,
                                                         TALER_ARL_asession,
                                                         &TALER_ARL_master_pub,
                                                         &ppr);
  else
    qs = TALER_ARL_adb->insert_auditor_progress_reserve (TALER_ARL_adb->cls,
                                                         TALER_ARL_asession,
                                                         &TALER_ARL_master_pub,
                                                         &ppr);
  if (0 >= qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Concluded reserve audit step at %llu/%llu/%llu/%llu\n",
              (unsigned long long) ppr.last_reserve_in_serial_id,
              (unsigned long long) ppr.last_reserve_out_serial_id,
              (unsigned long long) ppr.last_reserve_recoup_serial_id,
              (unsigned long long) ppr.last_reserve_close_serial_id);
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
    global_ret = 1;
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
    global_ret = 1;
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting audit\n");
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_escrow_balance));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_irregular_recoups));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_withdraw_fee_income));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_balance_insufficient_loss));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_balance_summary_delta_plus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_balance_summary_delta_minus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_arithmetic_delta_plus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_arithmetic_delta_minus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_balance_reserve_not_closed));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_bad_sig_loss));
  GNUNET_assert (NULL !=
                 (report_row_inconsistencies = json_array ()));
  GNUNET_assert (NULL !=
                 (denomination_key_validity_withdraw_inconsistencies
                    = json_array ()));
  GNUNET_assert (NULL !=
                 (report_reserve_balance_summary_wrong_inconsistencies
                    = json_array ()));
  GNUNET_assert (NULL !=
                 (report_reserve_balance_insufficient_inconsistencies
                    = json_array ()));
  GNUNET_assert (NULL !=
                 (report_reserve_not_closed_inconsistencies
                    = json_array ()));
  GNUNET_assert (NULL !=
                 (report_amount_arithmetic_inconsistencies
                    = json_array ()));
  GNUNET_assert (NULL !=
                 (report_bad_sig_losses = json_array ()));
  if (GNUNET_OK !=
      TALER_ARL_setup_sessions_and_run (&analyze_reserves,
                                        NULL))
  {
    global_ret = 1;
    return;
  }
  {
    json_t *report;

    report = json_pack ("{s:o, s:o, s:o, s:o, s:o,"
                        " s:o, s:o, s:o, s:o, s:o,"
                        " s:o, s:o, s:o, s:o, s:o,"
                        " s:o, s:o, s:o, s:o, s:I,"
                        " s:I, s:I, s:I, s:I, s:I,"
                        " s:I, s:I }",
                        /* blocks #1 */
                        "reserve_balance_insufficient_inconsistencies",
                        report_reserve_balance_insufficient_inconsistencies,
                        /* Tested in test-auditor.sh #3 */
                        "total_loss_balance_insufficient",
                        TALER_JSON_from_amount (
                          &total_balance_insufficient_loss),
                        /* Tested in test-auditor.sh #3 */
                        "reserve_balance_summary_wrong_inconsistencies",
                        report_reserve_balance_summary_wrong_inconsistencies,
                        "total_balance_summary_delta_plus",
                        TALER_JSON_from_amount (
                          &total_balance_summary_delta_plus),
                        "total_balance_summary_delta_minus",
                        TALER_JSON_from_amount (
                          &total_balance_summary_delta_minus),
                        /* blocks #2 */
                        "total_escrow_balance",
                        TALER_JSON_from_amount (&total_escrow_balance),
                        "total_withdraw_fee_income",
                        TALER_JSON_from_amount (
                          &total_withdraw_fee_income),
                        /* Tested in test-auditor.sh #21 */
                        "reserve_not_closed_inconsistencies",
                        report_reserve_not_closed_inconsistencies,
                        /* Tested in test-auditor.sh #21 */
                        "total_balance_reserve_not_closed",
                        TALER_JSON_from_amount (
                          &total_balance_reserve_not_closed),
                        /* Tested in test-auditor.sh #7 */
                        "bad_sig_losses",
                        report_bad_sig_losses,
                        /* blocks #3 */
                        /* Tested in test-auditor.sh #7 */
                        "total_bad_sig_loss",
                        TALER_JSON_from_amount (&total_bad_sig_loss),
                        /* Tested in test-revocation.sh #4 */
                        "row_inconsistencies",
                        report_row_inconsistencies,
                        /* Tested in test-auditor.sh #23 */
                        "denomination_key_validity_withdraw_inconsistencies",
                        denomination_key_validity_withdraw_inconsistencies,
                        "amount_arithmetic_inconsistencies",
                        report_amount_arithmetic_inconsistencies,
                        "total_arithmetic_delta_plus",
                        TALER_JSON_from_amount (
                          &total_arithmetic_delta_plus),
                        /* blocks #4 */
                        "total_arithmetic_delta_minus",
                        TALER_JSON_from_amount (
                          &total_arithmetic_delta_minus),
                        "auditor_start_time",
                        TALER_ARL_json_from_time_abs (
                          start_time),
                        "auditor_end_time",
                        TALER_ARL_json_from_time_abs (
                          GNUNET_TIME_absolute_get ()),
                        "total_irregular_recoups",
                        TALER_JSON_from_amount (
                          &total_irregular_recoups),
                        "start_ppr_reserve_in_serial_id",
                        (json_int_t) ppr_start.last_reserve_in_serial_id,
                        /* blocks #5 */
                        "start_ppr_reserve_out_serial_id",
                        (json_int_t) ppr_start.
                        last_reserve_out_serial_id,
                        "start_ppr_reserve_recoup_serial_id",
                        (json_int_t) ppr_start.
                        last_reserve_recoup_serial_id,
                        "start_ppr_reserve_close_serial_id",
                        (json_int_t) ppr_start.
                        last_reserve_close_serial_id,
                        "end_ppr_reserve_in_serial_id",
                        (json_int_t) ppr.last_reserve_in_serial_id,
                        "end_ppr_reserve_out_serial_id",
                        (json_int_t) ppr.last_reserve_out_serial_id,
                        /* blocks #6 */
                        "end_ppr_reserve_recoup_serial_id",
                        (json_int_t) ppr.last_reserve_recoup_serial_id,
                        "end_ppr_reserve_close_serial_id",
                        (json_int_t) ppr.last_reserve_close_serial_id
                        );
    GNUNET_break (NULL != report);
    TALER_ARL_done (report);
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
    GNUNET_GETOPT_option_base32_auto ('m',
                                      "exchange-key",
                                      "KEY",
                                      "public key of the exchange (Crockford base32 encoded)",
                                      &TALER_ARL_master_pub),
    GNUNET_GETOPT_option_timetravel ('T',
                                     "timetravel"),
    GNUNET_GETOPT_OPTION_END
  };

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-helper-auditor-reserves",
                                   "MESSAGE",
                                   NULL));
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc,
                          argv,
                          "taler-helper-auditor-reserves",
                          "Audit Taler exchange reserve handling",
                          options,
                          &run,
                          NULL))
    return 1;
  return global_ret;
}


/* end of taler-helper-auditor-reserves.c */
