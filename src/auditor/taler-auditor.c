/*
  This file is part of TALER
  Copyright (C) 2016, 2017 Inria

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
 * @file auditor/taler-auditor.c
 * @brief audits an exchange database.
 * @author Christian Grothoff
 *
 * NOTE:
 * - This auditor does not verify that 'reserves_in' actually matches
 *   the wire transfers from the bank. This needs to be checked separately!
 * - Similarly, we do not check that the outgoing wire transfers match those
 *   given in the 'wire_out' table. This needs to be checked separately!
 *
 * KNOWN BUGS:
 * - calculate, store and report aggregation fee balance!
 * - error handling if denomination keys are used that are not known to the
 *   auditor is, eh, awful / non-existent. We just throw the DB's constraint
 *   violation back at the user. Great UX.
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_auditordb_plugin.h"
#include "taler_exchangedb_plugin.h"
#include "taler_json_lib.h"
#include "taler_wire_lib.h"
#include "taler_signatures.h"


/**
 * How many coin histories do we keep in RAM at any given point in
 * time? Used bound memory consumption of the auditor. Larger values
 * reduce database accesses.
 *
 * Set to a VERY low value here for testing. Practical values may be
 * in the millions.
 */
#define MAX_COIN_SUMMARIES 4

/**
 * Use a 1 day grace period to deal with clocks not being perfectly synchronized.
 */
#define DEPOSIT_GRACE_PERIOD GNUNET_TIME_UNIT_DAYS

/**
 * Return value from main().
 */
static int global_ret;

/**
 * Command-line option "-r": restart audit from scratch
 */
static int restart;

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
 * Last reserve_in serial ID seen.
 */
static struct TALER_AUDITORDB_ProgressPoint pp;


/* ***************************** Report logic **************************** */


/**
 * Called in case we detect an emergency situation where the exchange
 * is paying out a larger amount on a denomination than we issued in
 * that denomination.  This means that the exchange's private keys
 * might have gotten compromised, and that we need to trigger an
 * emergency request to all wallets to deposit pending coins for the
 * denomination (and as an exchange suffer a huge financial loss).
 *
 * @param dki denomination key where the loss was detected
 */
static void
report_emergency (const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki)
{
  /* TODO: properly implement #3887, including how to continue the
     audit after the emergency. */
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Emergency detected for denomination %s\n",
              GNUNET_h2s (&dki->properties.denom_hash));
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
  // TODO: implement proper reporting logic writing to file.
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Database inconsistency detected in table %s at row %llu: %s\n",
              table,
              (unsigned long long) rowid,
              diagnostic);
}


/**
 * Report a minor inconsistency in the exchange's database (i.e. something
 * relating to timestamps that should have no financial implications).
 *
 * @param table affected table
 * @param rowid affected row, UINT64_MAX if row is missing
 * @param diagnostic message explaining the problem
 */
static void
report_row_minor_inconsistency (const char *table,
                                uint64_t rowid,
                                const char *diagnostic)
{
  // TODO: implement proper reporting logic writing to file.
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Minor inconsistency detected in table %s at row %llu: %s\n",
              table,
              (unsigned long long) rowid,
              diagnostic);
}


/**
 * Report a global inconsistency with respect to a reserve.
 *
 * @param reserve_pub the affected reserve
 * @param expected expected amount
 * @param observed observed amount
 * @param diagnostic message explaining what @a expected and @a observed refer to
 */
static void
report_reserve_inconsistency (const struct TALER_ReservePublicKeyP *reserve_pub,
                              const struct TALER_Amount *expected,
                              const struct TALER_Amount *observed,
                              const char *diagnostic)
{
  // TODO: implement proper reporting logic writing to file, include amounts.
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Reserve inconsistency detected affecting reserve %s: %s\n",
              TALER_B2S (reserve_pub),
              diagnostic);
}


/**
 * Report a global inconsistency with respect to a wire transfer.
 *
 * @param reserve_pub the affected reserve
 * @param expected expected amount
 * @param observed observed amount
 * @param diagnostic message explaining what @a expected and @a observed refer to
 */
static void
report_wire_out_inconsistency (const json_t *destination,
                               uint64_t rowid,
                               const struct TALER_Amount *expected,
                               const struct TALER_Amount *observed,
                               const char *diagnostic)
{
  // TODO: implement proper reporting logic writing to file, include amounts.
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Wire out inconsistency detected: %s\n",
              diagnostic);
}


/**
 * Report a global inconsistency with respect to a coin's history.
 *
 * @param coin_pub the affected coin
 * @param expected expected amount
 * @param observed observed amount
 * @param diagnostic message explaining what @a expected and @a observed refer to
 */
static void
report_coin_inconsistency (const struct TALER_CoinSpendPublicKeyP *coin_pub,
                           const struct TALER_Amount *expected,
                           const struct TALER_Amount *observed,
                           const char *diagnostic)
{
  // TODO: implement proper reporting logic writing to file, include amounts.
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Coin inconsistency detected: %s\n",
              diagnostic);
}


/**
 * Report the final result on the reserve balances of the exchange.
 * The reserve must have @a total_balance in its escrow account just
 * to cover outstanding reserve funds (outstanding coins are on top).
 * The reserve has made @a total_fee_balance in profit from withdrawal
 * operations alone.
 *
 * Note that this is for the "ongoing" reporting period.  Historic
 * revenue (as stored via the "insert_historic_reserve_revenue")
 * is not included in the @a total_fee_balance.
 *
 * @param total_balance how much money (in total) is left in all of the
 *        reserves (that has not been withdrawn)
 * @param total_fee_balance how much money (in total) did the reserve
 *        make from withdrawal fees
 */
static void
report_reserve_balance (const struct TALER_Amount *total_balance,
                        const struct TALER_Amount *total_fee_balance)
{
  // TODO: implement proper reporting logic writing to file.
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              _("Total escrow balance to be held for reserves is %s\n"),
              TALER_amount2s (total_balance));
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              _("Total withdraw fees are at %s\n"),
              TALER_amount2s (total_fee_balance));
}


/**
 * Report state of denomination processing.
 *
 * @param total_balance total value of outstanding coins
 * @param total_risk total value of issued coins in active denominations
 * @param deposit_fees total deposit fees collected
 * @param melt_fees total melt fees collected
 * @param refund_fees total refund fees collected
 */
static void
report_denomination_balance (const struct TALER_Amount *total_balance,
                             const struct TALER_Amount *total_risk,
                             const struct TALER_Amount *deposit_fees,
                             const struct TALER_Amount *melt_fees,
                             const struct TALER_Amount *refund_fees)
{
  // TODO: implement proper reporting logic writing to file.
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              "Final balance for all denominations is %s\n",
              TALER_amount2s (total_balance));
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              "Risk from active operations is %s\n",
              TALER_amount2s (total_risk));
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              "Deposit fee profits are %s\n",
              TALER_amount2s (deposit_fees));
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              "Melt fee profits are %s\n",
              TALER_amount2s (melt_fees));
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              "Refund fee profits are %s\n",
              TALER_amount2s (refund_fees));
}


/* ************************* Transaction-global state ************************ */

/**
 * Results about denominations, cached per-transaction.
 */
static struct GNUNET_CONTAINER_MultiHashMap *denominations;


/**
 * Obtain information about a @a denom_pub.
 *
 * @param denom_pub key to look up
 * @param[out] dki set to detailed information about @a denom_pub, NULL if not found, must
 *                 NOT be freed by caller
 * @param[out] dh set to the hash of @a denom_pub, may be NULL
 * @return #GNUNET_OK on success, #GNUNET_NO for not found, #GNUNET_SYSERR for DB error
 */
static int
get_denomination_info (const struct TALER_DenominationPublicKey *denom_pub,
                       const struct TALER_EXCHANGEDB_DenominationKeyInformationP **dki,
                       struct GNUNET_HashCode *dh)
{
  struct GNUNET_HashCode hc;
  struct TALER_EXCHANGEDB_DenominationKeyInformationP *dkip;
  int ret;

  if (NULL == dh)
    dh = &hc;
  GNUNET_CRYPTO_rsa_public_key_hash (denom_pub->rsa_public_key,
                                     dh);
  if (NULL == denominations)
    denominations = GNUNET_CONTAINER_multihashmap_create (256,
                                                          GNUNET_NO);
  dkip = GNUNET_CONTAINER_multihashmap_get (denominations,
                                            dh);
  if (NULL != dkip)
  {
    /* cache hit */
    *dki = dkip;
    return GNUNET_OK;
  }
  dkip = GNUNET_new (struct TALER_EXCHANGEDB_DenominationKeyInformationP);
  ret = edb->get_denomination_info (edb->cls,
                                    esession,
                                    denom_pub,
                                    dkip);
  if (GNUNET_OK != ret)
  {
    GNUNET_free (dkip);
    GNUNET_break (GNUNET_NO == ret);
    *dki = NULL;
    return ret;
  }
  {
    struct TALER_Amount value;

    TALER_amount_ntoh (&value,
                       &dkip->properties.value);
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Tracking denomination `%s' (%s)\n",
                GNUNET_h2s (dh),
                TALER_amount2s (&value));
  }
  *dki = dkip;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONTAINER_multihashmap_put (denominations,
                                                    dh,
                                                    dkip,
                                                    GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  return GNUNET_OK;
}


/**
 * Free denomination key information.
 *
 * @param cls NULL
 * @param key unused
 * @param value the `struct TALER_EXCHANGEDB_DenominationKeyInformationP *` to free
 * @return #GNUNET_OK (continue to iterate)
 */
static int
free_dk_info (void *cls,
              const struct GNUNET_HashCode *key,
              void *value)
{
  struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki = value;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Done with denomination `%s'\n",
              GNUNET_h2s (key));
  GNUNET_free (dki);
  return GNUNET_OK;
}


/**
 * Purge transaction global state cache, the transaction is
 * done and we do not want to have the state cross over to
 * the next transaction.
 */
static void
clear_transaction_state_cache ()
{
  if (NULL == denominations)
    return;
  GNUNET_CONTAINER_multihashmap_iterate (denominations,
                                         &free_dk_info,
                                         NULL);
  GNUNET_CONTAINER_multihashmap_destroy (denominations);
  denominations = NULL;
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
  struct TALER_Amount a_balance;

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
 * @param[in|out] rs reserve summary to (fully) initialize
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on DB errors
 */
static int
load_auditor_reserve_summary (struct ReserveSummary *rs)
{
  int ret;
  uint64_t rowid;

  ret = adb->get_reserve_info (adb->cls,
                               asession,
                               &rs->reserve_pub,
                               &master_pub,
                               &rowid,
                               &rs->a_balance,
                               &rs->a_withdraw_fee_balance,
                               &rs->a_expiration_date);
  if (GNUNET_SYSERR == ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_NO == ret)
  {
    rs->had_ri = GNUNET_NO;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (rs->total_in.currency,
                                          &rs->a_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (rs->total_in.currency,
                                          &rs->a_withdraw_fee_balance));
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Creating fresh reserve `%s' with starting balance %s\n",
                TALER_B2S (&rs->reserve_pub),
                TALER_amount2s (&rs->a_balance));
    return GNUNET_OK;
  }
  rs->had_ri = GNUNET_YES;
  if ( (GNUNET_YES !=
        TALER_amount_cmp_currency (&rs->a_balance,
                                   &rs->a_withdraw_fee_balance)) ||
       (GNUNET_YES !=
        TALER_amount_cmp_currency (&rs->total_in,
                                   &rs->a_balance)) )
  {
    report_row_inconsistency ("auditor-reserve-info",
                              rowid,
                              "currencies for reserve differ");
    /* TODO: find a sane way to continue... */
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Auditor remembers reserve `%s' has balance %s\n",
              TALER_B2S (&rs->reserve_pub),
              TALER_amount2s (&rs->a_balance));
  return GNUNET_OK;
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
   * Total balance in all reserves (updated).
   */
  struct TALER_Amount total_balance;

  /**
   * Total withdraw fees gotten in all reserves (updated).
   */
  struct TALER_Amount total_fee_balance;

};


/**
 * Function called with details about incoming wire transfers.
 *
 * @param cls our `struct ReserveContext`
 * @param rowid unique serial ID for the refresh session in our DB
 * @param reserve_pub public key of the reserve (also the WTID)
 * @param credit amount that was received
 * @param sender_account_details information about the sender's bank account
 * @param transfer_details information that uniquely identifies the wire transfer
 * @param execution_date when did we receive the funds
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
handle_reserve_in (void *cls,
                   uint64_t rowid,
                   const struct TALER_ReservePublicKeyP *reserve_pub,
                   const struct TALER_Amount *credit,
                   const json_t *sender_account_details,
                   const json_t *transfer_details,
                   struct GNUNET_TIME_Absolute execution_date)
{
  struct ReserveContext *rc = cls;
  struct GNUNET_HashCode key;
  struct ReserveSummary *rs;
  struct GNUNET_TIME_Absolute expiry;

  GNUNET_assert (rowid >= pp.last_reserve_in_serial_id); /* should be monotonically increasing */
  pp.last_reserve_in_serial_id = rowid + 1;
  GNUNET_CRYPTO_hash (reserve_pub,
                      sizeof (*reserve_pub),
                      &key);
  rs = GNUNET_CONTAINER_multihashmap_get (rc->reserves,
                                          &key);
  if (NULL == rs)
  {
    rs = GNUNET_new (struct ReserveSummary);
    rs->reserve_pub = *reserve_pub;
    rs->total_in = *credit;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (credit->currency,
                                          &rs->total_out));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (credit->currency,
                                          &rs->total_fee));
    if (GNUNET_OK !=
        load_auditor_reserve_summary (rs))
    {
      GNUNET_break (0);
      GNUNET_free (rs);
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
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_add (&rs->total_in,
                                     &rs->total_in,
                                     credit));
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Additional incoming wire transfer for reserve `%s' of %s\n",
              TALER_B2S (reserve_pub),
              TALER_amount2s (credit));
  expiry = GNUNET_TIME_absolute_add (execution_date,
                                     TALER_IDLE_RESERVE_EXPIRATION_TIME);
  rs->a_expiration_date = GNUNET_TIME_absolute_max (rs->a_expiration_date,
                                                    expiry);
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
 * @param denom_sig signature over the deposited coin
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
                    const struct TALER_DenominationSignature *denom_sig,
                    const struct TALER_ReservePublicKeyP *reserve_pub,
                    const struct TALER_ReserveSignatureP *reserve_sig,
                    struct GNUNET_TIME_Absolute execution_date,
                    const struct TALER_Amount *amount_with_fee)
{
  struct ReserveContext *rc = cls;
  struct TALER_WithdrawRequestPS wsrd;
  struct GNUNET_HashCode key;
  struct ReserveSummary *rs;
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;
  struct TALER_Amount withdraw_fee;
  struct GNUNET_TIME_Absolute valid_start;
  struct GNUNET_TIME_Absolute expire_withdraw;
  int ret;

  /* should be monotonically increasing */
  GNUNET_assert (rowid >= pp.last_reserve_out_serial_id);
  pp.last_reserve_out_serial_id = rowid + 1;

  /* lookup denomination pub data (make sure denom_pub is valid, establish fees) */
  ret = get_denomination_info (denom_pub,
                               &dki,
                               &wsrd.h_denomination_pub);
  if (GNUNET_SYSERR == ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_NO == ret)
  {
    report_row_inconsistency ("withdraw",
                              rowid,
                              "denomination key not found (foreign key constraint violated)");
    return GNUNET_OK;
  }

  /* check that execution date is within withdraw range for denom_pub  */
  valid_start = GNUNET_TIME_absolute_ntoh (dki->properties.start);
  expire_withdraw = GNUNET_TIME_absolute_ntoh (dki->properties.expire_withdraw);
  if ( (valid_start.abs_value_us > execution_date.abs_value_us) ||
       (expire_withdraw.abs_value_us < execution_date.abs_value_us) )
  {
    report_row_minor_inconsistency ("withdraw",
                                    rowid,
                                    "denomination key not valid at time of withdrawal");
  }

  /* check reserve_sig */
  wsrd.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW);
  wsrd.purpose.size = htonl (sizeof (wsrd));
  wsrd.reserve_pub = *reserve_pub;
  TALER_amount_hton (&wsrd.amount_with_fee,
                     amount_with_fee);
  wsrd.withdraw_fee = dki->properties.fee_withdraw;
  wsrd.h_coin_envelope = *h_blind_ev;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW,
                                  &wsrd.purpose,
                                  &reserve_sig->eddsa_signature,
                                  &reserve_pub->eddsa_pub))
  {
    report_row_inconsistency ("withdraw",
                              rowid,
                              "invalid signature for withdrawal");
    return GNUNET_OK;
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
    rs->total_out = *amount_with_fee;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (amount_with_fee->currency,
                                          &rs->total_in));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (amount_with_fee->currency,
                                          &rs->total_fee));
    if (GNUNET_OK !=
        load_auditor_reserve_summary (rs))
    {
      GNUNET_break (0);
      GNUNET_free (rs);
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
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_add (&rs->total_out,
                                     &rs->total_out,
                                     amount_with_fee));
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Reserve `%s' reduced by %s from withdraw\n",
              TALER_B2S (reserve_pub),
              TALER_amount2s (amount_with_fee));
  TALER_amount_ntoh (&withdraw_fee,
                     &dki->properties.fee_withdraw);
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_add (&rs->total_fee,
                                   &rs->total_fee,
                                   &withdraw_fee));

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
  int ret;

  ret = GNUNET_OK;
  reserve.pub = rs->reserve_pub;
  if (GNUNET_OK !=
      edb->reserve_get (edb->cls,
                        esession,
                        &reserve))
  {
    char *diag;

    GNUNET_asprintf (&diag,
                     "Failed to find summary for reserve `%s'\n",
                     TALER_B2S (&rs->reserve_pub));
    report_row_inconsistency ("reserve-summary",
                              UINT64_MAX,
                              diag);
    GNUNET_free (diag);
    return GNUNET_OK;
  }

  if (GNUNET_OK !=
      TALER_amount_add (&balance,
                        &rs->total_in,
                        &rs->a_balance))
  {
    report_reserve_inconsistency (&rs->reserve_pub,
                                  &rs->total_in,
                                  &rs->a_balance,
                                  "could not add old balance to new balance");
    goto cleanup;
  }

  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&balance,
                             &balance,
                             &rs->total_out))
  {
    report_reserve_inconsistency (&rs->reserve_pub,
                                  &rs->total_in,
                                  &rs->total_out,
                                  "available balance insufficient to cover transfers");
    goto cleanup;
  }
  if (0 != TALER_amount_cmp (&balance,
                             &reserve.balance))
  {
    report_reserve_inconsistency (&rs->reserve_pub,
                                  &balance,
                                  &reserve.balance,
                                  "computed balance does not match stored balance");
    goto cleanup;
  }

  if (0 == GNUNET_TIME_absolute_get_remaining (rs->a_expiration_date).rel_value_us)
  {
    /* TODO: handle case where reserve is expired! (#4956) */
    GNUNET_break (0); /* not implemented */
    /* NOTE: we may or may not have seen the wire-back transfer at this time,
       as the expiration may have just now happened.
       (That is, after we add the table structures and the logic to track
       such transfers...) */
  }

  /* Add withdraw fees we encountered to totals */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Reserve reserve `%s' made %s in withdraw fees\n",
              TALER_B2S (&rs->reserve_pub),
              TALER_amount2s (&rs->total_fee));
  if (GNUNET_YES !=
      TALER_amount_add (&rs->a_withdraw_fee_balance,
                        &rs->a_withdraw_fee_balance,
                        &rs->total_fee))
  {
    GNUNET_break (0);
    ret = GNUNET_SYSERR;
    goto cleanup;
  }
  if ( (GNUNET_YES !=
        TALER_amount_add (&rc->total_balance,
                          &rc->total_balance,
                          &rs->total_in)) ||
       (GNUNET_SYSERR ==
        TALER_amount_subtract (&rc->total_balance,
                               &rc->total_balance,
                               &rs->total_out)) ||
       (GNUNET_YES !=
        TALER_amount_add (&rc->total_fee_balance,
                          &rc->total_fee_balance,
                          &rs->total_fee)) )
  {
    GNUNET_break (0);
    ret = GNUNET_SYSERR;
    goto cleanup;
  }

  if ( (0ULL == balance.value) &&
       (0U == balance.fraction) )
  {
    /* TODO: balance is zero, drop reserve details (and then do not update/insert) */
    if (rs->had_ri)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Final balance of reserve `%s' is %s, dropping it\n",
                  TALER_B2S (&rs->reserve_pub),
                  TALER_amount2s (&balance));
      ret = adb->del_reserve_info (adb->cls,
                                   asession,
                                   &rs->reserve_pub,
                                   &master_pub);
      if (GNUNET_SYSERR == ret)
      {
        GNUNET_break (0);
        goto cleanup;
      }
      if (GNUNET_NO == ret)
      {
        GNUNET_break (0);
        ret = GNUNET_SYSERR;
        goto cleanup;
      }
    }
    else
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Final balance of reserve `%s' is %s, no need to remember it\n",
                  TALER_B2S (&rs->reserve_pub),
                  TALER_amount2s (&balance));
    }
    ret = GNUNET_OK;
    goto cleanup;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Remembering final balance of reserve `%s' as %s\n",
              TALER_B2S (&rs->reserve_pub),
              TALER_amount2s (&balance));

  if (rs->had_ri)
    ret = adb->update_reserve_info (adb->cls,
                                    asession,
                                    &rs->reserve_pub,
                                    &master_pub,
                                    &balance,
                                    &rs->a_withdraw_fee_balance,
                                    rs->a_expiration_date);
  else
    ret = adb->insert_reserve_info (adb->cls,
                                    asession,
                                    &rs->reserve_pub,
                                    &master_pub,
                                    &balance,
                                    &rs->a_withdraw_fee_balance,
                                    rs->a_expiration_date);

 cleanup:
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CONTAINER_multihashmap_remove (rc->reserves,
                                                       key,
                                                       rs));
  GNUNET_free (rs);
  return ret;
}


/**
 * Analyze reserves for being well-formed.
 *
 * @param cls NULL
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on invariant violation
 */
static int
analyze_reserves (void *cls)
{
  struct ReserveContext rc;
  int ret;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Analyzing reserves\n");
  ret = adb->get_reserve_summary (adb->cls,
                                  asession,
                                  &master_pub,
                                  &rc.total_balance,
                                  &rc.total_fee_balance);
  if (GNUNET_SYSERR == ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_NO == ret)
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (currency,
                                          &rc.total_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (currency,
                                          &rc.total_fee_balance));
  }

  rc.reserves = GNUNET_CONTAINER_multihashmap_create (512,
                                                      GNUNET_NO);

  if (GNUNET_SYSERR ==
      edb->select_reserves_in_above_serial_id (edb->cls,
                                               esession,
                                               pp.last_reserve_in_serial_id,
                                               &handle_reserve_in,
                                               &rc))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_SYSERR ==
      edb->select_reserves_out_above_serial_id (edb->cls,
                                                esession,
                                                pp.last_reserve_out_serial_id,
                                                &handle_reserve_out,
                                                &rc))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  /* TODO: iterate over table for reserve expiration refunds! (#4956) */

  GNUNET_CONTAINER_multihashmap_iterate (rc.reserves,
                                         &verify_reserve_balance,
                                         &rc);
  GNUNET_break (0 ==
                GNUNET_CONTAINER_multihashmap_size (rc.reserves));
  GNUNET_CONTAINER_multihashmap_destroy (rc.reserves);


  if (GNUNET_NO == ret)
  {
    ret = adb->insert_reserve_summary (adb->cls,
                                       asession,
                                       &master_pub,
                                       &rc.total_balance,
                                       &rc.total_fee_balance);
  }
  else
  {
    ret = adb->update_reserve_summary (adb->cls,
                                       asession,
                                       &master_pub,
                                       &rc.total_balance,
                                       &rc.total_fee_balance);
  }
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  report_reserve_balance (&rc.total_balance,
                          &rc.total_fee_balance);
  return GNUNET_OK;
}


/* *********************** Analyze aggregations ******************** */
/* This logic checks that the aggregator did the right thing
   paying each merchant what they were due (and on time). */


/**
 * Information we keep per loaded wire plugin.
 */
struct WirePlugin
{

  /**
   * Kept in a DLL.
   */
  struct WirePlugin *next;

  /**
   * Kept in a DLL.
   */
  struct WirePlugin *prev;

  /**
   * Name of the wire method.
   */
  char *type;

  /**
   * Handle to the wire plugin.
   */
  struct TALER_WIRE_Plugin *plugin;

};


/**
 * Closure for callbacks during #analyze_merchants().
 */
struct AggregationContext
{

  /**
   * DLL of wire plugins encountered.
   */
  struct WirePlugin *wire_head;

  /**
   * DLL of wire plugins encountered.
   */
  struct WirePlugin *wire_tail;

};


/**
 * Find the relevant wire plugin.
 *
 * @param ac context to search
 * @param type type of the wire plugin to load
 * @return NULL on error
 */
static struct TALER_WIRE_Plugin *
get_wire_plugin (struct AggregationContext *ac,
                 const char *type)
{
  struct WirePlugin *wp;
  struct TALER_WIRE_Plugin *plugin;

  for (wp = ac->wire_head; NULL != wp; wp = wp->next)
    if (0 == strcmp (type,
                     wp->type))
      return wp->plugin;
  plugin = TALER_WIRE_plugin_load (cfg,
                                   type);
  if (NULL == plugin)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to locate wire plugin for `%s'\n",
                type);
    return NULL;
  }
  wp = GNUNET_new (struct WirePlugin);
  wp->type = GNUNET_strdup (type);
  wp->plugin = plugin;
  GNUNET_CONTAINER_DLL_insert (ac->wire_head,
                               ac->wire_tail,
                               wp);
  return plugin;
}


/**
 * Closure for #wire_transfer_information_cb.
 */
struct WireCheckContext
{

  /**
   * Corresponding merchant context.
   */
  struct AggregationContext *ac;

  /**
   * Total deposits claimed by all transactions that were aggregated
   * under the given @e wtid.
   */
  struct TALER_Amount total_deposits;

  /**
   * Hash of the wire transfer details of the receiver.
   */
  struct GNUNET_HashCode h_wire;

  /**
   * Execution time of the wire transfer.
   */
  struct GNUNET_TIME_Absolute date;

  /**
   * Wire method used for the transfer.
   */
  const char *method;

  /**
   * Set to #GNUNET_SYSERR if there are inconsistencies.
   */
  int ok;

};


/**
 * Check coin's transaction history for plausibility.  Does NOT check
 * the signatures (those are checked independently), but does calculate
 * the amounts for the aggregation table and checks that the total
 * claimed coin value is within the value of the coin's denomination.
 *
 * @param coin_pub public key of the coin (for reporting)
 * @param h_proposal_data hash of the proposal for which we calculate the amount
 * @param merchant_pub public key of the merchant (who is allowed to issue refunds)
 * @param dki denomination information about the coin
 * @param tl_head head of transaction history to verify
 * @param[out] merchant_gain amount the coin contributes to the wire transfer to the merchant
 * @param[out] merchant_fees fees the exchange charged the merchant for the transaction(s)
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
check_transaction_history (const struct TALER_CoinSpendPublicKeyP *coin_pub,
                           const struct GNUNET_HashCode *h_proposal_data,
                           const struct TALER_MerchantPublicKeyP *merchant_pub,
                           const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki,
                           const struct TALER_EXCHANGEDB_TransactionList *tl_head,
                           struct TALER_Amount *merchant_gain,
                           struct TALER_Amount *merchant_fees)
{
  struct TALER_Amount expenditures;
  struct TALER_Amount refunds;
  struct TALER_Amount spent;
  struct TALER_Amount value;
  struct TALER_Amount merchant_loss;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Checking transaction history of coin %s\n",
              TALER_B2S (coin_pub));

  GNUNET_assert (NULL != tl_head);
  TALER_amount_get_zero (currency,
                         &expenditures);
  TALER_amount_get_zero (currency,
                         &refunds);
  TALER_amount_get_zero (currency,
                         merchant_gain);
  TALER_amount_get_zero (currency,
                         merchant_fees);
  TALER_amount_get_zero (currency,
                         &merchant_loss);
  /* Go over transaction history to compute totals; note that we do not
     know the order, so instead of subtracting we compute positive
     (deposit, melt) and negative (refund) values separately here,
     and then subtract the negative from the positive after the loop. */
  for (const struct TALER_EXCHANGEDB_TransactionList *tl = tl_head;NULL != tl;tl = tl->next)
  {
    const struct TALER_Amount *amount_with_fee;
    const struct TALER_Amount *fee;
    const struct TALER_AmountNBO *fee_dki;
    struct TALER_Amount tmp;

    switch (tl->type) {
    case TALER_EXCHANGEDB_TT_DEPOSIT:
      amount_with_fee = &tl->details.deposit->amount_with_fee;
      fee = &tl->details.deposit->deposit_fee;
      fee_dki = &dki->properties.fee_deposit;
      if (GNUNET_OK !=
          TALER_amount_add (&expenditures,
                            &expenditures,
                            amount_with_fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      /* Check if this deposit is within the remit of the aggregation
         we are investigating, if so, include it in the totals. */
      if ( (0 == memcmp (merchant_pub,
                         &tl->details.deposit->merchant_pub,
                         sizeof (struct TALER_MerchantPublicKeyP))) &&
           (0 == memcmp (h_proposal_data,
                         &tl->details.deposit->h_proposal_data,
                         sizeof (struct GNUNET_HashCode))) )
      {
        struct TALER_Amount amount_without_fee;

        if (GNUNET_OK !=
            TALER_amount_subtract (&amount_without_fee,
                                   amount_with_fee,
                                   fee))
        {
          GNUNET_break (0);
          return GNUNET_SYSERR;
        }
        if (GNUNET_OK !=
            TALER_amount_add (merchant_gain,
                              merchant_gain,
                              &amount_without_fee))
        {
          GNUNET_break (0);
          return GNUNET_SYSERR;
        }
        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "Detected applicable deposit of %s\n",
                    TALER_amount2s (&amount_without_fee));
        if (GNUNET_OK !=
            TALER_amount_add (merchant_fees,
                              merchant_fees,
                              fee))
        {
          GNUNET_break (0);
          return GNUNET_SYSERR;
        }
      }
      break;
    case TALER_EXCHANGEDB_TT_REFRESH_MELT:
      amount_with_fee = &tl->details.melt->amount_with_fee;
      fee = &tl->details.melt->melt_fee;
      fee_dki = &dki->properties.fee_refresh;
      if (GNUNET_OK !=
          TALER_amount_add (&expenditures,
                            &expenditures,
                            amount_with_fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      break;
    case TALER_EXCHANGEDB_TT_REFUND:
      amount_with_fee = &tl->details.refund->refund_amount;
      fee = &tl->details.refund->refund_fee;
      fee_dki = &dki->properties.fee_refund;
      if (GNUNET_OK !=
          TALER_amount_add (&refunds,
                            &refunds,
                            amount_with_fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          TALER_amount_add (&expenditures,
                            &expenditures,
                            fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      /* Check if this refund is within the remit of the aggregation
         we are investigating, if so, include it in the totals. */
      if ( (0 == memcmp (merchant_pub,
                         &tl->details.refund->merchant_pub,
                         sizeof (struct TALER_MerchantPublicKeyP))) &&
           (0 == memcmp (h_proposal_data,
                         &tl->details.refund->h_proposal_data,
                         sizeof (struct GNUNET_HashCode))) )
      {
        if (GNUNET_OK !=
            TALER_amount_add (&merchant_loss,
                              &merchant_loss,
                              amount_with_fee))
        {
          GNUNET_break (0);
          return GNUNET_SYSERR;
        }
        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "Detected applicable refund of %s\n",
                    TALER_amount2s (amount_with_fee));
        if (GNUNET_OK !=
            TALER_amount_add (merchant_fees,
                              merchant_fees,
                              fee))
        {
          GNUNET_break (0);
          return GNUNET_SYSERR;
        }
      }
      break;
    }

    /* Check that the fees given in the transaction list and in dki match */
    TALER_amount_ntoh (&tmp,
                       fee_dki);
    if (0 !=
        TALER_amount_cmp (&tmp,
                          fee))
    {
      /* Disagreement in fee structure within DB, should be impossible! */
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  } /* for 'tl' */

  /* Calculate total balance change, i.e. expenditures minus refunds */
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&spent,
                             &expenditures,
                             &refunds))
  {
    /* refunds above expenditures? Bad! */
    report_coin_inconsistency (coin_pub,
                               &expenditures,
                               &refunds,
                               "could not subtract refunded amount from expenditures");
    return GNUNET_SYSERR;
  }

  /* Now check that 'spent' is less or equal than total coin value */
  TALER_amount_ntoh (&value,
                     &dki->properties.value);
  if (1 == TALER_amount_cmp (&spent,
                             &value))
  {
    /* spent > value */
    report_coin_inconsistency (coin_pub,
                               &spent,
                               &value,
                               "accepted deposits (minus refunds) exceeds denomination value");
    return GNUNET_SYSERR;
  }

  /* Finally, update @a merchant_gain by subtracting what he "lost" from refunds */
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (merchant_gain,
                             merchant_gain,
                             &merchant_loss))
  {
    /* refunds above deposits? Bad! */
    report_coin_inconsistency (coin_pub,
                               merchant_gain,
                               &merchant_loss,
                               "merchant was granted more refunds than he deposited");
    return GNUNET_SYSERR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Coin %s contributes %s to contract %s\n",
              TALER_B2S (coin_pub),
              TALER_amount2s (merchant_gain),
              GNUNET_h2s (h_proposal_data));
  return GNUNET_OK;
}


/**
 * Function called with the results of the lookup of the
 * transaction data associated with a wire transfer identifier.
 *
 * @param cls a `struct WireCheckContext`
 * @param rowid which row in the table is the information from (for diagnostics)
 * @param merchant_pub public key of the merchant (should be same for all callbacks with the same @e cls)
 * @param wire_method which wire plugin was used for the transfer?
 * @param h_wire hash of wire transfer details of the merchant (should be same for all callbacks with the same @e cls)
 * @param exec_time execution time of the wire transfer (should be same for all callbacks with the same @e cls)
 * @param h_proposal_data which proposal was this payment about
 * @param coin_pub which public key was this payment about
 * @param coin_value amount contributed by this coin in total (with fee)
 * @param coin_fee applicable fee for this coin
 */
static void
wire_transfer_information_cb (void *cls,
                              uint64_t rowid,
                              const struct TALER_MerchantPublicKeyP *merchant_pub,
                              const char *wire_method,
                              const struct GNUNET_HashCode *h_wire,
                              struct GNUNET_TIME_Absolute exec_time,
                              const struct GNUNET_HashCode *h_proposal_data,
                              const struct TALER_CoinSpendPublicKeyP *coin_pub,
                              const struct TALER_Amount *coin_value,
                              const struct TALER_Amount *coin_fee)
{
  struct WireCheckContext *wcc = cls;
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;
  struct TALER_Amount contribution;
  struct TALER_Amount computed_value;
  struct TALER_Amount computed_fees;
  struct TALER_Amount coin_value_without_fee;
  struct TALER_EXCHANGEDB_TransactionList *tl;
  const struct TALER_CoinPublicInfo *coin;

  /* Obtain coin's transaction history */
  tl = edb->get_coin_transactions (edb->cls,
                                   esession,
                                   coin_pub);
  if (NULL == tl)
  {
    wcc->ok = GNUNET_SYSERR;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "no transaction history for coin claimed in aggregation");
    return;
  }

  /* Obtain general denomination information about the coin */
  coin = NULL;
  switch (tl->type)
  {
  case TALER_EXCHANGEDB_TT_DEPOSIT:
    coin = &tl->details.deposit->coin;
    break;
  case TALER_EXCHANGEDB_TT_REFRESH_MELT:
    coin = &tl->details.melt->coin;
    break;
  case TALER_EXCHANGEDB_TT_REFUND:
    coin = &tl->details.refund->coin;
    break;
  }
  GNUNET_assert (NULL != coin); /* hard check that switch worked */
  if (GNUNET_OK !=
      get_denomination_info (&coin->denom_pub,
                             &dki,
                             NULL))
  {
    /* This should be impossible from database constraints */
    GNUNET_break (0);
    edb->free_coin_transaction_list (edb->cls,
                                     tl);
    wcc->ok = GNUNET_SYSERR;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "could not find denomination key for coin claimed in aggregation");
    return;
  }

  /* Check transaction history to see if it supports aggregate valuation */
  check_transaction_history (coin_pub,
                             h_proposal_data,
                             merchant_pub,
                             dki,
                             tl,
                             &computed_value,
                             &computed_fees);
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&coin_value_without_fee,
                             coin_value,
                             coin_fee))
  {
    wcc->ok = GNUNET_SYSERR;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "inconsistent coin value and fee claimed in aggregation");
    return;
  }
  if (0 !=
      TALER_amount_cmp (&computed_value,
                        &coin_value_without_fee))
  {
    wcc->ok = GNUNET_SYSERR;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "coin transaction history and aggregation disagree about coin's contribution");
  }
  if (0 !=
      TALER_amount_cmp (&computed_fees,
                        coin_fee))
  {
    wcc->ok = GNUNET_SYSERR;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "coin transaction history and aggregation disagree about applicable fees");
  }
  edb->free_coin_transaction_list (edb->cls,
                                   tl);

  /* Check other details of wire transfer match */
  if (0 != strcmp (wire_method,
                   wcc->method))
  {
    wcc->ok = GNUNET_SYSERR;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "wire method of aggregate do not match wire transfer");
  }
  if (0 != memcmp (h_wire,
                   &wcc->h_wire,
                   sizeof (struct GNUNET_HashCode)))
  {
    wcc->ok = GNUNET_SYSERR;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "account details of aggregate do not match account details of wire transfer");
    return;
  }
  if (exec_time.abs_value_us != wcc->date.abs_value_us)
  {
    /* This should be impossible from database constraints */
    GNUNET_break (0);
    wcc->ok = GNUNET_SYSERR;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "date given in aggregate does not match wire transfer date");
    return;
  }
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&contribution,
                             coin_value,
                             coin_fee))
  {
    wcc->ok = GNUNET_SYSERR;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "could not calculate contribution of coin");
    return;
  }

  /* Add coin's contribution to total aggregate value */
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_add (&wcc->total_deposits,
                                   &wcc->total_deposits,
                                   &contribution));
}


/**
 * Check that a wire transfer made by the exchange is valid
 * (has matching deposits).
 *
 * @param cls a `struct AggregationContext`
 * @param rowid identifier of the respective row in the database
 * @param date timestamp of the wire transfer (roughly)
 * @param wtid wire transfer subject
 * @param wire wire transfer details of the receiver
 * @param amount amount that was wired
 */
static void
check_wire_out_cb (void *cls,
                   uint64_t rowid,
                   struct GNUNET_TIME_Absolute date,
                   const struct TALER_WireTransferIdentifierRawP *wtid,
                   const json_t *wire,
                   const struct TALER_Amount *amount)
{
  struct AggregationContext *ac = cls;
  struct WireCheckContext wcc;
  json_t *method;
  struct TALER_WIRE_Plugin *plugin;

  /* should be monotonically increasing */
  GNUNET_assert (rowid >= pp.last_wire_out_serial_id);
  pp.last_wire_out_serial_id = rowid + 1;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Checking wire transfer %s over %s performed on %s\n",
              TALER_B2S (wtid),
              TALER_amount2s (amount),
              GNUNET_STRINGS_absolute_time_to_string (date));
  wcc.ac = ac;
  method = json_object_get (wire,
                            "type");
  if ( (NULL == method) ||
       (! json_is_string (method)) )
  {
    report_row_inconsistency ("wire_out",
                              rowid,
                              "specified wire address lacks type");
    return;
  }
  wcc.method = json_string_value (method);
  wcc.ok = GNUNET_OK;
  wcc.date = date;
  TALER_amount_get_zero (amount->currency,
                         &wcc.total_deposits);
  TALER_JSON_hash (wire,
                   &wcc.h_wire);
  edb->lookup_wire_transfer (edb->cls,
                             esession,
                             wtid,
                             &wire_transfer_information_cb,
                             &wcc);
  if (GNUNET_OK != wcc.ok)
  {
    report_row_inconsistency ("wire_out",
                              rowid,
                              "audit of associated transactions failed");
  }
  plugin = get_wire_plugin (ac,
                            wcc.method);
  if (NULL == plugin)
  {
    report_row_inconsistency ("wire_out",
                              rowid,
                              "could not load required wire plugin to validate");
    return;
  }
  if (GNUNET_SYSERR ==
      plugin->amount_round (plugin->cls,
                            &wcc.total_deposits))
  {
    report_row_minor_inconsistency ("wire_out",
                                    rowid,
                                    "wire plugin failed to round given amount");
  }
  if (0 != TALER_amount_cmp (amount,
                             &wcc.total_deposits))
  {
    report_wire_out_inconsistency (wire,
                                   rowid,
                                   &wcc.total_deposits,
                                   amount,
                                   "computed amount inconsistent with wire amount");
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Wire transfer %s is OK\n",
              TALER_B2S (wtid));
}


/**
 * Analyze the exchange aggregator's payment processing.
 *
 * @param cls closure
 * @param int #GNUNET_OK on success, #GNUNET_SYSERR on hard errors
 */
static int
analyze_aggregations (void *cls)
{
  struct AggregationContext ac;
  struct WirePlugin *wc;
  int ret;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Analyzing aggregations\n");
  ret = GNUNET_OK;
  ac.wire_head = NULL;
  ac.wire_tail = NULL;
  if (GNUNET_SYSERR ==
      edb->select_wire_out_above_serial_id (edb->cls,
                                            esession,
                                            pp.last_wire_out_serial_id,
                                            &check_wire_out_cb,
                                            &ac))
  {
    GNUNET_break (0);
    ret = GNUNET_SYSERR;
  }
  while (NULL != (wc = ac.wire_head))
  {
    GNUNET_CONTAINER_DLL_remove (ac.wire_head,
                                 ac.wire_tail,
                                 wc);
    TALER_WIRE_plugin_unload (wc->plugin);
    GNUNET_free (wc->type);
    GNUNET_free (wc);
  }
  return ret;
}


/* ************************* Analyze coins ******************** */
/* This logic checks that the exchange did the right thing for each
   coin, checking deposits, refunds, refresh* and known_coins
   tables */


/**
 * Summary data we keep per denomination.
 */
struct DenominationSummary
{
  /**
   * Total value of outstanding (not deposited) coins issued with this
   * denomination key.
   */
  struct TALER_Amount denom_balance;

  /**
   * Total value of coins issued with this denomination key.
   */
  struct TALER_Amount denom_risk;

  /**
   * Denomination key information for this denomination.
   */
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;

  /**
   * #GNUNET_YES if this record already existed in the DB.
   * Used to decide between insert/update in
   * #sync_denomination().
   */
  int in_db;
};


/**
 * Closure for callbacks during #analyze_coins().
 */
struct CoinContext
{

  /**
   * Map for tracking information about denominations.
   */
  struct GNUNET_CONTAINER_MultiHashMap *denom_summaries;

  /**
   * Total outstanding balances across all denomination keys.
   */
  struct TALER_Amount total_denom_balance;

  /**
   * Total deposit fees earned so far.
   */
  struct TALER_Amount deposit_fee_balance;

  /**
   * Total melt fees earned so far.
   */
  struct TALER_Amount melt_fee_balance;

  /**
   * Total refund fees earned so far.
   */
  struct TALER_Amount refund_fee_balance;

  /**
   * Current financial risk of the exchange operator with respect
   * to key compromise.
   *
   * TODO: not yet properly used!
   */
  struct TALER_Amount risk;

  /**
   * Current write/replace offset in the circular @e summaries buffer.
   */
  unsigned int summaries_off;

  /**
   * #GNUNET_OK as long as we are fine to commit the result to the #adb.
   */
  int ret;

};


/**
 * Initialize information about denomination from the database.
 *
 * @param denom_hash hash of the public key of the denomination
 * @param[out] ds summary to initialize
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
init_denomination (const struct GNUNET_HashCode *denom_hash,
                   struct DenominationSummary *ds)
{
  int ret;

  ret = adb->get_denomination_balance (adb->cls,
                                       asession,
                                       denom_hash,
                                       &ds->denom_balance,
                                       &ds->denom_risk);
  if (GNUNET_OK == ret)
  {
    ds->in_db = GNUNET_YES;
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Starting balance for denomination `%s' is %s\n",
                GNUNET_h2s (denom_hash),
                TALER_amount2s (&ds->denom_balance));
    return GNUNET_OK;
  }
  if (GNUNET_SYSERR == ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &ds->denom_balance));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &ds->denom_risk));
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting balance for denomination `%s' is %s\n",
              GNUNET_h2s (denom_hash),
              TALER_amount2s (&ds->denom_balance));
  return GNUNET_OK;
}


/**
 * Obtain the denomination summary for the given @a dh
 *
 * @param cc our execution context
 * @param dki denomination key information for @a dh
 * @param dh the denomination hash to use for the lookup
 * @return NULL on error
 */
static struct DenominationSummary *
get_denomination_summary (struct CoinContext *cc,
                          const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki,
                          const struct GNUNET_HashCode *dh)
{
  struct DenominationSummary *ds;

  ds = GNUNET_CONTAINER_multihashmap_get (cc->denom_summaries,
                                          dh);
  if (NULL != ds)
    return ds;
  ds = GNUNET_new (struct DenominationSummary);
  ds->dki = dki;
  if (GNUNET_OK !=
      init_denomination (dh,
                         ds))
  {
    GNUNET_break (0);
    GNUNET_free (ds);
    return NULL;
  }
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONTAINER_multihashmap_put (cc->denom_summaries,
                                                    dh,
                                                    ds,
                                                    GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  return ds;
}


/**
 * Write information about the current knowledge about a denomination key
 * back to the database and update our global reporting data about the
 * denomination.  Also remove and free the memory of @a value.
 *
 * @param cls the `struct CoinContext`
 * @param key the hash of the denomination key
 * @param value a `struct DenominationSummary`
 * @return #GNUNET_OK (continue to iterate)
 */
static int
sync_denomination (void *cls,
                   const struct GNUNET_HashCode *denom_hash,
                   void *value)
{
  struct CoinContext *cc = cls;
  struct DenominationSummary *ds = value;
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki = ds->dki;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Absolute expire_deposit;
  struct GNUNET_TIME_Absolute expire_deposit_grace;
  int ret;

  now = GNUNET_TIME_absolute_get ();
  expire_deposit = GNUNET_TIME_absolute_ntoh (dki->properties.expire_deposit);
  /* add day grace period to deal with clocks not being perfectly synchronized */
  expire_deposit_grace = GNUNET_TIME_absolute_add (expire_deposit,
                                                   DEPOSIT_GRACE_PERIOD);
  if (now.abs_value_us > expire_deposit_grace.abs_value_us)
  {
    /* Denominationkey has expired, book remaining balance of
       outstanding coins as revenue; and reduce cc->risk exposure. */
    if (ds->in_db)
      ret = adb->del_denomination_balance (adb->cls,
                                           asession,
                                           denom_hash);
    else
      ret = GNUNET_OK;
    if ( (GNUNET_OK == ret) &&
         ( (0 != ds->denom_risk.value) ||
           (0 != ds->denom_risk.fraction) ) )
    {
      /* The denomination expired and carried a balance; we can now
         book the remaining balance as profit, and reduce our risk
         exposure by the accumulated risk of the denomination. */
      if (GNUNET_SYSERR ==
          TALER_amount_subtract (&cc->risk,
                                 &cc->risk,
                                 &ds->denom_risk))
      {
        /* Holy smokes, our risk assessment was inconsistent!
           This is really, really bad. */
        GNUNET_break (0);
        cc->ret = GNUNET_SYSERR;
      }
    }
    if ( (GNUNET_OK == ret) &&
         ( (0 != ds->denom_balance.value) ||
           (0 != ds->denom_balance.fraction) ) )
    {
      /* book denom_balance coin expiration profits! */
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Denomination `%s' expired, booking %s in expiration profits\n",
                  GNUNET_h2s (denom_hash),
                  TALER_amount2s (&ds->denom_balance));
      if (GNUNET_OK !=
          adb->insert_historic_denom_revenue (adb->cls,
                                              asession,
                                              &master_pub,
                                              denom_hash,
                                              expire_deposit,
                                              &ds->denom_balance))
      {
        /* Failed to store profits? Bad database */
        GNUNET_break (0);
        cc->ret = GNUNET_SYSERR;
      }
    }
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Final balance for denomination `%s' is %s\n",
                GNUNET_h2s (denom_hash),
                TALER_amount2s (&ds->denom_balance));
    if (ds->in_db)
      ret = adb->update_denomination_balance (adb->cls,
                                              asession,
                                              denom_hash,
                                              &ds->denom_balance,
                                              &ds->denom_risk);
    else
      ret = adb->insert_denomination_balance (adb->cls,
                                              asession,
                                              denom_hash,
                                              &ds->denom_balance,
                                              &ds->denom_risk);
  }
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    cc->ret = GNUNET_SYSERR;
  }
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CONTAINER_multihashmap_remove (cc->denom_summaries,
                                                       denom_hash,
                                                       ds));
  GNUNET_free (ds);
  return cc->ret;
}


/**
 * Function called with details about all withdraw operations.
 * Updates the denomination balance and the overall balance as
 * we now have additional coins that have been issued.
 *
 * Note that the signature was already checked in
 * #handle_reserve_out(), so we do not check it again here.
 *
 * @param cls our `struct CoinContext`
 * @param rowid unique serial ID for the refresh session in our DB
 * @param h_blind_ev blinded hash of the coin's public key
 * @param denom_pub public denomination key of the deposited coin
 * @param denom_sig signature over the deposited coin
 * @param reserve_pub public key of the reserve
 * @param reserve_sig signature over the withdraw operation (verified elsewhere)
 * @param execution_date when did the wallet withdraw the coin
 * @param amount_with_fee amount that was withdrawn
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
withdraw_cb (void *cls,
             uint64_t rowid,
             const struct GNUNET_HashCode *h_blind_ev,
             const struct TALER_DenominationPublicKey *denom_pub,
             const struct TALER_DenominationSignature *denom_sig,
             const struct TALER_ReservePublicKeyP *reserve_pub,
             const struct TALER_ReserveSignatureP *reserve_sig,
             struct GNUNET_TIME_Absolute execution_date,
             const struct TALER_Amount *amount_with_fee)
{
  struct CoinContext *cc = cls;
  struct DenominationSummary *ds;
  struct GNUNET_HashCode dh;
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;
  struct TALER_Amount value;

  GNUNET_assert (rowid >= pp.last_withdraw_serial_id); /* should be monotonically increasing */
  pp.last_withdraw_serial_id = rowid + 1;

  if (GNUNET_OK !=
      get_denomination_info (denom_pub,
                             &dki,
                             &dh))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  ds = get_denomination_summary (cc,
                                 dki,
                                 &dh);
  TALER_amount_ntoh (&value,
                     &dki->properties.value);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Issued coin in denomination `%s' of total value %s\n",
              GNUNET_h2s (&dh),
              TALER_amount2s (&value));
  if (GNUNET_OK !=
      TALER_amount_add (&ds->denom_balance,
                        &ds->denom_balance,
                        &value))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "New balance of denomination `%s' is %s\n",
              GNUNET_h2s (&dh),
              TALER_amount2s (&ds->denom_balance));
  if (GNUNET_OK !=
      TALER_amount_add (&cc->total_denom_balance,
                        &cc->total_denom_balance,
                        &value))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_amount_add (&cc->risk,
                        &cc->risk,
                        &value))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_amount_add (&ds->denom_risk,
                        &ds->denom_risk,
                        &value))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Function called with details about coins that were melted, with the
 * goal of auditing the refresh's execution.  Verifies the signature
 * and updates our information about coins outstanding (the old coin's
 * denomination has less, the fresh coins increased outstanding
 * balances).
 *
 * @param cls closure
 * @param rowid unique serial ID for the refresh session in our DB
 * @param denom_pub denomination public key of @a coin_pub
 * @param coin_pub public key of the coin
 * @param coin_sig signature from the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param num_newcoins how many coins were issued
 * @param noreveal_index which index was picked by the exchange in cut-and-choose
 * @param session_hash what is the session hash
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
refresh_session_cb (void *cls,
                    uint64_t rowid,
                    const struct TALER_DenominationPublicKey *denom_pub,
                    const struct TALER_CoinSpendPublicKeyP *coin_pub,
                    const struct TALER_CoinSpendSignatureP *coin_sig,
                    const struct TALER_Amount *amount_with_fee,
                    uint16_t num_newcoins,
                    uint16_t noreveal_index,
                    const struct GNUNET_HashCode *session_hash)
{
  struct CoinContext *cc = cls;
  struct TALER_RefreshMeltCoinAffirmationPS rmc;
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;
  struct DenominationSummary *dso;
  struct TALER_Amount amount_without_fee;
  struct TALER_Amount tmp;

  GNUNET_assert (rowid >= pp.last_melt_serial_id); /* should be monotonically increasing */
  pp.last_melt_serial_id = rowid + 1;

  if (GNUNET_OK !=
      get_denomination_info (denom_pub,
                             &dki,
                             NULL))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  /* verify melt signature */
  rmc.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_MELT);
  rmc.purpose.size = htonl (sizeof (rmc));
  rmc.session_hash = *session_hash;
  TALER_amount_hton (&rmc.amount_with_fee,
                     amount_with_fee);
  rmc.melt_fee = dki->properties.fee_refresh;
  rmc.coin_pub = *coin_pub;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_MELT,
                                  &rmc.purpose,
                                  &coin_sig->eddsa_signature,
                                  &coin_pub->eddsa_pub))
  {
    report_row_inconsistency ("melt",
                              rowid,
                              "invalid signature for coin melt");
    return GNUNET_OK;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Melting coin %s in denomination `%s' of value %s\n",
              TALER_B2S (coin_pub),
              GNUNET_h2s (&dki->properties.denom_hash),
              TALER_amount2s (amount_with_fee));

  {
    struct TALER_DenominationPublicKey new_dp[num_newcoins];
    const struct TALER_EXCHANGEDB_DenominationKeyInformationP *new_dki[num_newcoins];
    struct TALER_Amount refresh_cost;
    int err;

    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (amount_with_fee->currency,
                                          &refresh_cost));

    if (GNUNET_OK !=
        edb->get_refresh_order (edb->cls,
                                esession,
                                session_hash,
                                num_newcoins,
                                new_dp))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    /* Update outstanding amounts for all new coin's denominations, and check
       that the resulting amounts are consistent with the value being refreshed. */
    err = GNUNET_NO;
    for (unsigned int i=0;i<num_newcoins;i++)
    {
      /* lookup new coin denomination key */
      if (GNUNET_OK !=
          get_denomination_info (&new_dp[i],
                                 &new_dki[i],
                                 NULL))
      {
        GNUNET_break (0);
        err = GNUNET_YES;
      }
      GNUNET_CRYPTO_rsa_public_key_free (new_dp[i].rsa_public_key);
      new_dp[i].rsa_public_key = NULL;
    }
    if (err)
      return GNUNET_SYSERR;

    /* calculate total refresh cost */
    for (unsigned int i=0;i<num_newcoins;i++)
    {
      /* update cost of refresh */
      struct TALER_Amount fee;
      struct TALER_Amount value;

      TALER_amount_ntoh (&fee,
                         &new_dki[i]->properties.fee_withdraw);
      TALER_amount_ntoh (&value,
                         &new_dki[i]->properties.value);
      if ( (GNUNET_OK !=
            TALER_amount_add (&refresh_cost,
                              &refresh_cost,
                              &fee)) ||
           (GNUNET_OK !=
            TALER_amount_add (&refresh_cost,
                              &refresh_cost,
                              &value)) )
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
    }

    /* compute contribution of old coin */
    {
      struct TALER_Amount melt_fee;

      TALER_amount_ntoh (&melt_fee,
                         &dki->properties.fee_refresh);
      if (GNUNET_OK !=
          TALER_amount_subtract (&amount_without_fee,
                                 amount_with_fee,
                                 &melt_fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
    }

    /* check old coin covers complete expenses */
    if (1 == TALER_amount_cmp (&refresh_cost,
                               &amount_without_fee))
    {
      /* refresh_cost > amount_without_fee */
      report_row_inconsistency ("melt",
                                rowid,
                                "refresh costs exceed value of melt");
      return GNUNET_OK;
    }

    /* update outstanding denomination amounts */
    for (unsigned int i=0;i<num_newcoins;i++)
    {
      struct DenominationSummary *dsi;
      struct TALER_Amount value;

      dsi = get_denomination_summary (cc,
                                      new_dki[i],
                                      &new_dki[i]->properties.denom_hash);
      TALER_amount_ntoh (&value,
                         &new_dki[i]->properties.value);
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Created fresh coin in denomination `%s' of value %s\n",
                  GNUNET_h2s (&new_dki[i]->properties.denom_hash),
                  TALER_amount2s (&value));
      if (GNUNET_OK !=
          TALER_amount_add (&dsi->denom_balance,
                            &dsi->denom_balance,
                            &value))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          TALER_amount_add (&dsi->denom_risk,
                            &dsi->denom_risk,
                            &value))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "New balance of denomination `%s' is %s\n",
                  GNUNET_h2s (&new_dki[i]->properties.denom_hash),
                  TALER_amount2s (&dsi->denom_balance));
      if (GNUNET_OK !=
          TALER_amount_add (&cc->total_denom_balance,
                            &cc->total_denom_balance,
                            &value))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          TALER_amount_add (&cc->risk,
                            &cc->risk,
                            &value))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
    }
  }

  /* update old coin's denomination balance */
  dso = get_denomination_summary (cc,
                                  dki,
                                  &dki->properties.denom_hash);
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&tmp,
                             &dso->denom_balance,
                             amount_with_fee))
  {
    report_emergency (dki);
    return GNUNET_SYSERR;
  }
  dso->denom_balance = tmp;
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&cc->total_denom_balance,
                             &cc->total_denom_balance,
                             amount_with_fee))
  {
    /* This should not be possible, unless the AUDITOR
       has a bug in tracking total balance. */
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "New balance of denomination `%s' after melt is %s\n",
              GNUNET_h2s (&dki->properties.denom_hash),
              TALER_amount2s (&dso->denom_balance));

  /* update global up melt fees */
  {
    struct TALER_Amount rfee;

    TALER_amount_ntoh (&rfee,
                       &dki->properties.fee_refresh);
    if (GNUNET_OK !=
        TALER_amount_add (&cc->melt_fee_balance,
                          &cc->melt_fee_balance,
                          &rfee))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  }

  /* We're good! */
  return GNUNET_OK;
}


/**
 * Function called with details about deposits that have been made,
 * with the goal of auditing the deposit's execution.
 *
 * As a side-effect, #get_coin_summary will report
 * inconsistencies in the deposited coin's balance.
 *
 * @param cls closure
 * @param rowid unique serial ID for the deposit in our DB
 * @param timestamp when did the deposit happen
 * @param merchant_pub public key of the merchant
 * @param denom_pub denomination public key of @a coin_pub
 * @param coin_pub public key of the coin
 * @param coin_sig signature from the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param h_proposal_data hash of the proposal data known to merchant and customer
 * @param refund_deadline by which the merchant adviced that he might want
 *        to get a refund
 * @param wire_deadline by which the merchant adviced that he would like the
 *        wire transfer to be executed
 * @param receiver_wire_account wire details for the merchant, NULL from iterate_matching_deposits()
 * @param done flag set if the deposit was already executed (or not)
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
deposit_cb (void *cls,
            uint64_t rowid,
            struct GNUNET_TIME_Absolute timestamp,
            const struct TALER_MerchantPublicKeyP *merchant_pub,
            const struct TALER_DenominationPublicKey *denom_pub,
            const struct TALER_CoinSpendPublicKeyP *coin_pub,
            const struct TALER_CoinSpendSignatureP *coin_sig,
            const struct TALER_Amount *amount_with_fee,
            const struct GNUNET_HashCode *h_proposal_data,
            struct GNUNET_TIME_Absolute refund_deadline,
            struct GNUNET_TIME_Absolute wire_deadline,
            const json_t *receiver_wire_account,
            int done)
{
  struct CoinContext *cc = cls;
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;
  struct DenominationSummary *ds;
  struct TALER_DepositRequestPS dr;
  struct TALER_Amount tmp;

  GNUNET_assert (rowid >= pp.last_deposit_serial_id); /* should be monotonically increasing */
  pp.last_deposit_serial_id = rowid + 1;

  if (GNUNET_OK !=
      get_denomination_info (denom_pub,
                             &dki,
                             NULL))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  /* Verify deposit signature */
  dr.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_DEPOSIT);
  dr.purpose.size = htonl (sizeof (dr));
  dr.h_proposal_data = *h_proposal_data;
  if (GNUNET_OK !=
      TALER_JSON_hash (receiver_wire_account,
                       &dr.h_wire))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  dr.timestamp = GNUNET_TIME_absolute_hton (timestamp);
  dr.refund_deadline = GNUNET_TIME_absolute_hton (refund_deadline);
  TALER_amount_hton (&dr.amount_with_fee,
                     amount_with_fee);
  dr.deposit_fee = dki->properties.fee_deposit;
  dr.merchant = *merchant_pub;
  dr.coin_pub = *coin_pub;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_DEPOSIT,
                                  &dr.purpose,
                                  &coin_sig->eddsa_signature,
                                  &coin_pub->eddsa_pub))
  {
    report_row_inconsistency ("deposit",
                              rowid,
                              "invalid signature for coin deposit");
    return GNUNET_OK;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Deposited coin %s in denomination `%s' of value %s\n",
              TALER_B2S (coin_pub),
              GNUNET_h2s (&dki->properties.denom_hash),
              TALER_amount2s (amount_with_fee));

  /* update old coin's denomination balance */
  ds = get_denomination_summary (cc,
                                 dki,
                                 &dki->properties.denom_hash);
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&tmp,
                             &ds->denom_balance,
                             amount_with_fee))
  {
    report_emergency (dki);
    return GNUNET_SYSERR;
  }
  ds->denom_balance = tmp;
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&cc->total_denom_balance,
                             &cc->total_denom_balance,
                             amount_with_fee))
  {
    /* This should not be possible, unless the AUDITOR
       has a bug in tracking total balance. */
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "New balance of denomination `%s' after deposit is %s\n",
              GNUNET_h2s (&dki->properties.denom_hash),
              TALER_amount2s (&ds->denom_balance));

  /* update global up melt fees */
  {
    struct TALER_Amount dfee;

    TALER_amount_ntoh (&dfee,
                       &dki->properties.fee_deposit);
    if (GNUNET_OK !=
        TALER_amount_add (&cc->deposit_fee_balance,
                          &cc->deposit_fee_balance,
                          &dfee))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  }

  return GNUNET_OK;
}


/**
 * Function called with details about coins that were refunding,
 * with the goal of auditing the refund's execution.  Adds the
 * refunded amount back to the outstanding balance of the respective
 * denomination.
 *
 * As a side-effect, #get_coin_summary will report
 * inconsistencies in the refunded coin's balance.
 *
 * @param cls closure
 * @param rowid unique serial ID for the refund in our DB
 * @param denom_pub denomination public key of @a coin_pub
 * @param coin_pub public key of the coin
 * @param merchant_pub public key of the merchant
 * @param merchant_sig signature of the merchant
 * @param h_proposal_data hash of the proposal data known to merchant and customer
 * @param rtransaction_id refund transaction ID chosen by the merchant
 * @param amount_with_fee amount that was deposited including fee
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
refund_cb (void *cls,
           uint64_t rowid,
           const struct TALER_DenominationPublicKey *denom_pub,
           const struct TALER_CoinSpendPublicKeyP *coin_pub,
           const struct TALER_MerchantPublicKeyP *merchant_pub,
           const struct TALER_MerchantSignatureP *merchant_sig,
           const struct GNUNET_HashCode *h_proposal_data,
           uint64_t rtransaction_id,
           const struct TALER_Amount *amount_with_fee)
{
  struct CoinContext *cc = cls;
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;
  struct DenominationSummary *ds;
  struct TALER_RefundRequestPS rr;
  struct TALER_Amount amount_without_fee;
  struct TALER_Amount refund_fee;

  GNUNET_assert (rowid >= pp.last_refund_serial_id); /* should be monotonically increasing */
  pp.last_refund_serial_id = rowid + 1;

  if (GNUNET_OK !=
      get_denomination_info (denom_pub,
                             &dki,
                             NULL))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  /* verify refund signature */
  rr.purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_REFUND);
  rr.purpose.size = htonl (sizeof (rr));
  rr.h_proposal_data = *h_proposal_data;
  rr.coin_pub = *coin_pub;
  rr.merchant = *merchant_pub;
  rr.rtransaction_id = GNUNET_htonll (rtransaction_id);
  TALER_amount_hton (&rr.refund_amount,
                     amount_with_fee);
  rr.refund_fee = dki->properties.fee_refund;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MERCHANT_REFUND,
                                  &rr.purpose,
                                  &merchant_sig->eddsa_sig,
                                  &merchant_pub->eddsa_pub))
  {
    report_row_inconsistency ("refund",
                              rowid,
                              "invalid signature for refund");
    return GNUNET_OK;
  }

  TALER_amount_ntoh (&refund_fee,
                     &dki->properties.fee_refund);
  if (GNUNET_OK !=
      TALER_amount_subtract (&amount_without_fee,
                             amount_with_fee,
                             &refund_fee))
  {
    report_row_inconsistency ("refund",
                              rowid,
                              "refunded amount smaller than refund fee");
    return GNUNET_OK;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Refunding coin %s in denomination `%s' value %s\n",
              TALER_B2S (coin_pub),
              GNUNET_h2s (&dki->properties.denom_hash),
              TALER_amount2s (amount_with_fee));

  /* update coin's denomination balance */
  ds = get_denomination_summary (cc,
                                 dki,
                                 &dki->properties.denom_hash);
  if (GNUNET_OK !=
      TALER_amount_add (&ds->denom_balance,
                        &ds->denom_balance,
                        &amount_without_fee))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_amount_add (&ds->denom_risk,
                        &ds->denom_risk,
                        &amount_without_fee))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_amount_add (&cc->total_denom_balance,
                        &cc->total_denom_balance,
                        &amount_without_fee))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_amount_add (&cc->risk,
                        &cc->risk,
                        &amount_without_fee))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "New balance of denomination `%s' after refund is %s\n",
              GNUNET_h2s (&dki->properties.denom_hash),
              TALER_amount2s (&ds->denom_balance));

  /* update total refund fee balance */
  if (GNUNET_OK !=
      TALER_amount_add (&cc->refund_fee_balance,
                        &cc->refund_fee_balance,
                        &refund_fee))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


/**
 * Analyze the exchange's processing of coins.
 *
 * @param cls closure
 * @param int #GNUNET_OK on success, #GNUNET_SYSERR on hard errors
 */
static int
analyze_coins (void *cls)
{
  struct CoinContext cc;
  int dret;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Analyzing coins\n");
  /* setup 'cc' */
  cc.ret = GNUNET_OK;
  cc.denom_summaries = GNUNET_CONTAINER_multihashmap_create (256,
                                                           GNUNET_NO);
  dret = adb->get_balance_summary (adb->cls,
                                   asession,
                                   &master_pub,
                                   &cc.total_denom_balance,
                                   &cc.deposit_fee_balance,
                                   &cc.melt_fee_balance,
                                   &cc.refund_fee_balance,
                                   &cc.risk);
  if (GNUNET_SYSERR == dret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_NO == dret)
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (currency,
                                          &cc.total_denom_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (currency,
                                          &cc.deposit_fee_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (currency,
                                          &cc.melt_fee_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (currency,
                                          &cc.refund_fee_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (currency,
                                          &cc.risk));
  }

  /* process withdrawals */
  if (GNUNET_SYSERR ==
      edb->select_reserves_out_above_serial_id (edb->cls,
                                                esession,
                                                pp.last_withdraw_serial_id,
                                                &withdraw_cb,
                                                &cc))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  /* process refunds */
  if (GNUNET_SYSERR ==
      edb->select_refunds_above_serial_id (edb->cls,
                                           esession,
                                           pp.last_refund_serial_id,
                                           &refund_cb,
                                           &cc))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  /* process refreshs */
  if (GNUNET_SYSERR ==
      edb->select_refreshs_above_serial_id (edb->cls,
                                            esession,
                                            pp.last_melt_serial_id,
                                            &refresh_session_cb,
                                            &cc))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  /* process deposits */
  if (GNUNET_SYSERR ==
      edb->select_deposits_above_serial_id (edb->cls,
                                            esession,
                                            pp.last_deposit_serial_id,
                                            &deposit_cb,
                                            &cc))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  /* sync 'cc' back to disk */
  GNUNET_CONTAINER_multihashmap_iterate (cc.denom_summaries,
                                         &sync_denomination,
                                         &cc);
  GNUNET_CONTAINER_multihashmap_destroy (cc.denom_summaries);
  if (GNUNET_OK != cc.ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_YES == dret)
      dret = adb->update_balance_summary (adb->cls,
                                          asession,
                                          &master_pub,
                                          &cc.total_denom_balance,
                                          &cc.deposit_fee_balance,
                                          &cc.melt_fee_balance,
                                          &cc.refund_fee_balance,
                                          &cc.risk);
  else
    dret = adb->insert_balance_summary (adb->cls,
                                        asession,
                                        &master_pub,
                                        &cc.total_denom_balance,
                                        &cc.deposit_fee_balance,
                                        &cc.melt_fee_balance,
                                        &cc.refund_fee_balance,
                                        &cc.risk);
  if (GNUNET_OK != dret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  report_denomination_balance (&cc.total_denom_balance,
                               &cc.risk,
                               &cc.deposit_fee_balance,
                               &cc.melt_fee_balance,
                               &cc.refund_fee_balance);
  return GNUNET_OK;
}


/* *************************** General transaction logic ****************** */

/**
 * Type of an analysis function.  Each analysis function runs in
 * its own transaction scope and must thus be internally consistent.
 *
 * @param cls closure
 * @param int #GNUNET_OK on success, #GNUNET_SYSERR on hard errors
 */
typedef int
(*Analysis)(void *cls);


/**
 * Perform the given @a analysis incrementally, checkpointing our
 * progress in the auditor DB.
 *
 * @param analysis analysis to run
 * @param analysis_cls closure for @a analysis
 * @return #GNUNET_OK if @a analysis succeessfully committed,
 *         #GNUNET_SYSERR on hard errors
 */
static int
incremental_processing (Analysis analysis,
                        void *analysis_cls)
{
  int ret;
  int have_pp;

  have_pp = adb->get_auditor_progress (adb->cls,
                                       asession,
                                       &master_pub,
                                       &pp);
  if (GNUNET_SYSERR == have_pp)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_NO == have_pp)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                _("First analysis using this auditor, starting audit from scratch\n"));
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                _("Resuming audit at %llu/%llu/%llu/%llu/%llu/%llu/%llu\n"),
                (unsigned long long) pp.last_reserve_in_serial_id,
                (unsigned long long) pp.last_reserve_out_serial_id,
                (unsigned long long) pp.last_withdraw_serial_id,
                (unsigned long long) pp.last_deposit_serial_id,
                (unsigned long long) pp.last_melt_serial_id,
                (unsigned long long) pp.last_refund_serial_id,
                (unsigned long long) pp.last_wire_out_serial_id);
  }
  ret = analysis (analysis_cls);
  if (GNUNET_OK != ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Analysis phase failed, not recording progress\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_YES == have_pp)
    ret = adb->update_auditor_progress (adb->cls,
                                        asession,
                                        &master_pub,
                                        &pp);
  else
    ret = adb->insert_auditor_progress (adb->cls,
                                        asession,
                                        &master_pub,
                                        &pp);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              _("Concluded audit step at %llu/%llu/%llu/%llu/%llu/%llu/%llu\n\n"),
              (unsigned long long) pp.last_reserve_in_serial_id,
              (unsigned long long) pp.last_reserve_out_serial_id,
              (unsigned long long) pp.last_withdraw_serial_id,
              (unsigned long long) pp.last_deposit_serial_id,
              (unsigned long long) pp.last_melt_serial_id,
              (unsigned long long) pp.last_refund_serial_id,
              (unsigned long long) pp.last_wire_out_serial_id);
  return GNUNET_OK;
}


/**
 * Perform the given @a analysis within a transaction scope.
 * Commit on success.
 *
 * @param analysis analysis to run
 * @param analysis_cls closure for @a analysis
 * @return #GNUNET_OK if @a analysis succeessfully committed,
 *         #GNUNET_NO if we had an error on commit (retry may help)
 *         #GNUNET_SYSERR on hard errors
 */
static int
transact (Analysis analysis,
          void *analysis_cls)
{
  int ret;

  ret = adb->start (adb->cls,
                    asession);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  ret = edb->start (edb->cls,
                    esession);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  ret = incremental_processing (analysis,
                                analysis_cls);
  if (GNUNET_OK == ret)
  {
    ret = edb->commit (edb->cls,
                       esession);
    if (GNUNET_OK != ret)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Exchange DB commit failed, rolling back transaction\n");
      adb->rollback (adb->cls,
                     asession);
    }
    else
    {
      ret = adb->commit (adb->cls,
                         asession);
      if (GNUNET_OK != ret)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
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
  clear_transaction_state_cache ();
  return ret;
}


/**
 * Initialize DB sessions and run the analysis.
 */
static void
setup_sessions_and_run ()
{
  esession = edb->get_session (edb->cls);
  if (NULL == esession)
  {
    fprintf (stderr,
             "Failed to initialize exchange session.\n");
    global_ret = 1;
    return;
  }
  asession = adb->get_session (adb->cls);
  if (NULL == asession)
  {
    fprintf (stderr,
             "Failed to initialize auditor session.\n");
    global_ret = 1;
    return;
  }

  transact (&analyze_reserves,
            NULL);
  transact (&analyze_aggregations,
            NULL);
  transact (&analyze_coins,
            NULL);
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
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Launching auditor\n");
  cfg = c;
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
                  adb->drop_tables (adb->cls));
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

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting audit\n");
  setup_sessions_and_run ();
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Audit complete\n");
  TALER_AUDITORDB_plugin_unload (adb);
  TALER_EXCHANGEDB_plugin_unload (edb);
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
    GNUNET_GETOPT_OPTION_MANDATORY
    (GNUNET_GETOPT_OPTION_SET_BASE32_AUTO ('m',
                                           "exchange-key",
                                           "KEY",
                                           "public key of the exchange (Crockford base32 encoded)",
                                           &master_pub)),
    GNUNET_GETOPT_OPTION_SET_ONE ('r',
                                  "restart",
                                  "restart audit from the beginning",
                                  &restart),
    GNUNET_GETOPT_OPTION_END
  };

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-auditor",
                                   "INFO",
                                   NULL));
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc,
			  argv,
                          "taler-auditor",
			  "Audit Taler exchange database",
			  options,
			  &run,
			  NULL))
    return 1;
  return global_ret;
}


/* end of taler-auditor.c */
