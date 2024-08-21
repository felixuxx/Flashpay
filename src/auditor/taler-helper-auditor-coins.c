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
 * @file auditor/taler-helper-auditor-coins.c
 * @brief audits coins in an exchange database.
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
 * How many coin histories do we keep in RAM at any given point in time?
 * Expect a few kB per coin history to be used. Used bound memory consumption
 * of the auditor. Larger values reduce database accesses.
 */
#define MAX_COIN_HISTORIES (16 * 1024 * 1024)

/**
 * Use a 1 day grace period to deal with clocks not being perfectly synchronized.
 */
#define DEPOSIT_GRACE_PERIOD GNUNET_TIME_UNIT_DAYS

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
 * Checkpointing our progress for coins.
 */
static TALER_ARL_DEF_PP (coins_withdraw_serial_id);
static TALER_ARL_DEF_PP (coins_deposit_serial_id);
static TALER_ARL_DEF_PP (coins_melt_serial_id);
static TALER_ARL_DEF_PP (coins_refund_serial_id);
static TALER_ARL_DEF_PP (coins_recoup_serial_id);
static TALER_ARL_DEF_PP (coins_recoup_refresh_serial_id);
static TALER_ARL_DEF_PP (coins_purse_deposits_serial_id);
static TALER_ARL_DEF_PP (coins_purse_refunds_serial_id);


/**
 * Global coin balance sheet (for coins).
 */
static TALER_ARL_DEF_AB (coin_balance_risk);
static TALER_ARL_DEF_AB (total_escrowed);
static TALER_ARL_DEF_AB (coin_irregular_loss);
static TALER_ARL_DEF_AB (coin_melt_fee_revenue);
static TALER_ARL_DEF_AB (coin_deposit_fee_revenue);
static TALER_ARL_DEF_AB (coin_refund_fee_revenue);
static TALER_ARL_DEF_AB (total_recoup_loss);

/**
 * Profits the exchange made by bad amount calculations.
 */
static TALER_ARL_DEF_AB (coins_total_arithmetic_delta_plus);

/**
 * Losses the exchange made by bad amount calculations.
 */
static TALER_ARL_DEF_AB (coins_total_arithmetic_delta_minus);

/**
 * Total amount reported in all calls to #report_emergency_by_count().
 */
static TALER_ARL_DEF_AB (coins_reported_emergency_risk_by_count);

/**
 * Total amount reported in all calls to #report_emergency_by_amount().
 */
static TALER_ARL_DEF_AB (coins_reported_emergency_risk_by_amount);

/**
 * Total amount in losses reported in all calls to #report_emergency_by_amount().
 */
static TALER_ARL_DEF_AB (coins_emergencies_loss);

/**
 * Total amount in losses reported in all calls to #report_emergency_by_count().
 */
static TALER_ARL_DEF_AB (coins_emergencies_loss_by_count);

/**
 * Total amount lost by operations for which signatures were invalid.
 */
static TALER_ARL_DEF_AB (total_refresh_hanging);

/**
 * Coin and associated transaction history.
 */
struct CoinHistory
{
  /**
   * Public key of the coin.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * The transaction list for the @a coin_pub.
   */
  struct TALER_EXCHANGEDB_TransactionList *tl;
};

/**
 * Array of transaction histories for coins.  The index is based on the coin's
 * public key.  Entries are replaced whenever we have a collision.
 */
static struct CoinHistory coin_histories[MAX_COIN_HISTORIES];

/**
 * Should we run checks that only work for exchange-internal audits?
 */
static int internal_checks;

static struct GNUNET_DB_EventHandler *eh;

/**
 * The auditors's configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;


/**
 * Return the index we should use for @a coin_pub in #coin_histories.
 *
 * @param coin_pub a coin's public key
 * @return index for caching this coin's history in #coin_histories
 */
static unsigned int
coin_history_index (const struct TALER_CoinSpendPublicKeyP *coin_pub)
{
  uint32_t i;

  GNUNET_memcpy (&i,
                 coin_pub,
                 sizeof (i));
  return i % MAX_COIN_HISTORIES;
}


/**
 * Add a coin history to our in-memory cache.
 *
 * @param coin_pub public key of the coin to cache
 * @param tl history to store
 */
static void
cache_history (const struct TALER_CoinSpendPublicKeyP *coin_pub,
               struct TALER_EXCHANGEDB_TransactionList *tl)
{
  unsigned int i = coin_history_index (coin_pub);

  if (NULL != coin_histories[i].tl)
    TALER_ARL_edb->free_coin_transaction_list (TALER_ARL_edb->cls,
                                               coin_histories[i].tl);
  coin_histories[i].coin_pub = *coin_pub;
  coin_histories[i].tl = tl;
}


/**
 * Obtain a coin's history from our in-memory cache.
 *
 * @param coin_pub public key of the coin to cache
 * @return NULL if @a coin_pub is not in the cache
 */
static struct TALER_EXCHANGEDB_TransactionList *
get_cached_history (const struct TALER_CoinSpendPublicKeyP *coin_pub)
{
  unsigned int i = coin_history_index (coin_pub);

  if (0 ==
      GNUNET_memcmp (coin_pub,
                     &coin_histories[i].coin_pub))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Found verification of %s in cache\n",
                TALER_B2S (coin_pub));
    return coin_histories[i].tl;
  }
  return NULL;
}


/* ***************************** Report logic **************************** */

/**
 * Called in case we detect an emergency situation where the exchange
 * is paying out a larger amount on a denomination than we issued in
 * that denomination.  This means that the exchange's private keys
 * might have gotten compromised, and that we need to trigger an
 * emergency request to all wallets to deposit pending coins for the
 * denomination (and as an exchange suffer a huge financial loss).
 *
 * @param issue denomination key where the loss was detected
 * @param risk maximum risk that might have just become real (coins created by this @a issue)
 * @param loss actual losses already (actualized before denomination was revoked)
 */
static void
report_emergency_by_amount (
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue,
  const struct TALER_Amount *risk,
  const struct TALER_Amount *loss)
{
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Reporting emergency on denomination `%s' over loss of %s\n",
              GNUNET_h2s (&issue->denom_hash.hash),
              TALER_amount2s (loss));

  enum GNUNET_DB_QueryStatus qs;
  struct TALER_AUDITORDB_Emergency emergency = {
    .denom_loss = *loss,
    .denompub_h = *&issue->denom_hash,
    .denom_risk = *risk,
    .deposit_start = *&issue->start.abs_time,
    .deposit_end = *&issue->expire_deposit.abs_time,
    .value = *&issue->value
  };

  qs = TALER_ARL_adb->insert_emergency (
    TALER_ARL_adb->cls,
    &emergency);

  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    // FIXME: error handling
  }
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (
                          coins_reported_emergency_risk_by_amount),
                        &TALER_ARL_USE_AB (
                          coins_reported_emergency_risk_by_amount),
                        risk);
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (coins_emergencies_loss),
                        &TALER_ARL_USE_AB (coins_emergencies_loss),
                        loss);
}


/**
 * Called in case we detect an emergency situation where the exchange
 * is paying out a larger NUMBER of coins of a denomination than we
 * issued in that denomination.  This means that the exchange's
 * private keys might have gotten compromised, and that we need to
 * trigger an emergency request to all wallets to deposit pending
 * coins for the denomination (and as an exchange suffer a huge
 * financial loss).
 *
 * @param issue denomination key where the loss was detected
 * @param num_issued number of coins that were issued
 * @param num_known number of coins that have been deposited
 * @param risk amount that is at risk
 */
static void
report_emergency_by_count (
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue,
  uint64_t num_issued,
  uint64_t num_known,
  const struct TALER_Amount *risk)
{
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_AUDITORDB_EmergenciesByCount emergenciesByCount = {
    .denompub_h = issue->denom_hash,
    .num_issued = num_issued,
    .num_known = num_known,
    .start = issue->start.abs_time,
    .deposit_end = issue->expire_deposit.abs_time,
    .value = issue->value
  };

  qs = TALER_ARL_adb->insert_emergency_by_count (
    TALER_ARL_adb->cls,
    &emergenciesByCount);

  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    // FIXME: error handling
  }
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (
                          coins_reported_emergency_risk_by_count),
                        &TALER_ARL_USE_AB (
                          coins_reported_emergency_risk_by_count),
                        risk);
  for (uint64_t i = num_issued; i < num_known; i++)
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (coins_emergencies_loss_by_count),
                          &TALER_ARL_USE_AB (coins_emergencies_loss_by_count),
                          &issue->value);

}


/**
 * Report a (serious) inconsistency in the exchange's database with
 * respect to calculations involving amounts.
 *
 * @param operation what operation had the inconsistency
 * @param rowid affected row, 0 if row is missing
 * @param exchange amount calculated by exchange
 * @param auditor amount calculated by auditor
 * @param profitable 1 if @a exchange being larger than @a auditor is
 *           profitable for the exchange for this operation
 *           (and thus @a exchange being smaller than @ auditor
 *            representing a loss for the exchange);
 *           -1 if @a exchange being smaller than @a auditor is
 *           profitable for the exchange; and 0 if it is unclear
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

  {
    struct TALER_AUDITORDB_AmountArithmeticInconsistency aai = {
      .profitable = profitable,
      .operation = (char *) operation,
      .exchange_amount = *exchange,
      .auditor_amount = *auditor
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = TALER_ARL_adb->insert_amount_arithmetic_inconsistency (
      TALER_ARL_adb->cls,
      &aai);
    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      // FIXME: error handling!
    }
  }
  if (0 != profitable)
  {
    target = (1 == profitable)
      ? &TALER_ARL_USE_AB (coins_total_arithmetic_delta_plus)
      : &TALER_ARL_USE_AB (coins_total_arithmetic_delta_minus);
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
    .row_table = (char *) table,
    .row_id = rowid,
    .diagnostic = (char *) diagnostic
  };

  qs = TALER_ARL_adb->insert_row_inconsistency (
    TALER_ARL_adb->cls,
    &ri);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    // FIXME: error handling!
  }
}


/* ************* Analyze history of a coin ******************** */


/**
 * Obtain @a coin_pub's history, verify it, report inconsistencies
 * and store the result in our cache.
 *
 * @param coin_pub public key of the coin to check the history of
 * @param rowid a row identifying the transaction
 * @param operation operation matching @a rowid
 * @param value value of the respective coin's denomination
 * @return database status code, negative on failures
 */
static enum GNUNET_DB_QueryStatus
check_coin_history (const struct TALER_CoinSpendPublicKeyP *coin_pub,
                    uint64_t rowid,
                    const char *operation,
                    const struct TALER_Amount *value)
{
  struct TALER_EXCHANGEDB_TransactionList *tl;
  enum GNUNET_DB_QueryStatus qs = GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  struct TALER_Amount total;
  struct TALER_Amount spent;
  struct TALER_Amount refunded;
  struct TALER_Amount deposit_fee;
  bool have_refund;
  uint64_t etag_out;

  /* TODO: could use 'etag' mechanism to only fetch transactions
     we did not yet process, instead of going over them
     again and again. */
  {
    struct TALER_Amount balance;
    struct TALER_DenominationHashP h_denom_pub;

    qs = TALER_ARL_edb->get_coin_transactions (TALER_ARL_edb->cls,
                                               false,
                                               coin_pub,
                                               0,
                                               0,
                                               &etag_out,
                                               &balance,
                                               &h_denom_pub,
                                               &tl);
  }
  /*if (0 >= qs)
    return qs;*/
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (value->currency,
                                        &refunded));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (value->currency,
                                        &spent));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (value->currency,
                                        &deposit_fee));
  have_refund = false;
  for (struct TALER_EXCHANGEDB_TransactionList *pos = tl;
       NULL != pos;
       pos = pos->next)
  {
    switch (pos->type)
    {
    case TALER_EXCHANGEDB_TT_DEPOSIT:
      /* spent += pos->amount_with_fee */
      TALER_ARL_amount_add (&spent,
                            &spent,
                            &pos->details.deposit->amount_with_fee);
      deposit_fee = pos->details.deposit->deposit_fee;
      break;
    case TALER_EXCHANGEDB_TT_MELT:
      /* spent += pos->amount_with_fee */
      TALER_ARL_amount_add (&spent,
                            &spent,
                            &pos->details.melt->amount_with_fee);
      break;
    case TALER_EXCHANGEDB_TT_REFUND:
      /* refunded += pos->refund_amount - pos->refund_fee */
      TALER_ARL_amount_add (&refunded,
                            &refunded,
                            &pos->details.refund->refund_amount);
      TALER_ARL_amount_add (&spent,
                            &spent,
                            &pos->details.refund->refund_fee);
      have_refund = true;
      break;
    case TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP:
      /* refunded += pos->value */
      TALER_ARL_amount_add (&refunded,
                            &refunded,
                            &pos->details.old_coin_recoup->value);
      break;
    case TALER_EXCHANGEDB_TT_RECOUP:
      /* spent += pos->value */
      TALER_ARL_amount_add (&spent,
                            &spent,
                            &pos->details.recoup->value);
      break;
    case TALER_EXCHANGEDB_TT_RECOUP_REFRESH:
      /* spent += pos->value */
      TALER_ARL_amount_add (&spent,
                            &spent,
                            &pos->details.recoup_refresh->value);
      break;
    case TALER_EXCHANGEDB_TT_PURSE_DEPOSIT:
      /* spent += pos->value */
      TALER_ARL_amount_add (&spent,
                            &spent,
                            &pos->details.purse_deposit->amount);
      break;
    case TALER_EXCHANGEDB_TT_PURSE_REFUND:
      TALER_ARL_amount_add (&refunded,
                            &refunded,
                            &pos->details.purse_refund->refund_amount);
      TALER_ARL_amount_add (&spent,
                            &spent,
                            &pos->details.purse_refund->refund_fee);
      have_refund = true;
      break;
    case TALER_EXCHANGEDB_TT_RESERVE_OPEN:
      TALER_ARL_amount_add (&spent,
                            &spent,
                            &pos->details.reserve_open->coin_contribution);
      break;
    } /* switch (pos->type) */
  } /* for (...) */
  if (have_refund)
  {
    /* If we gave any refund, also discount ONE deposit fee */
    TALER_ARL_amount_add (&refunded,
                          &refunded,
                          &deposit_fee);
  }
  /* total coin value = original value plus refunds */
  TALER_ARL_amount_add (&total,
                        &refunded,
                        value);
  if (1 ==
      TALER_amount_cmp (&spent,
                        &total))
  {
    /* spent > total: bad */
    struct TALER_Amount loss;
    TALER_ARL_amount_subtract (&loss,
                               &spent,
                               &total);
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Loss detected for coin %s - %s\n",
                TALER_B2S (coin_pub),
                TALER_amount2s (&loss));
    report_amount_arithmetic_inconsistency (operation,
                                            rowid,
                                            &spent,
                                            &total,
                                            -1);
  }
  cache_history (coin_pub,
                 tl);
  return qs;
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
   * Information about the circulation.
   */
  struct TALER_AUDITORDB_DenominationCirculationData dcd;

  /**
   * Denomination key information for this denomination.
   */
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue;

  /**
   * True if this record already existed in the DB.
   * Used to decide between insert/update in
   * #sync_denomination().
   */
  bool in_db;

  /**
   * Should we report an emergency for this denomination, causing it to be
   * revoked (because more coins were deposited than issued)?
   */
  bool report_emergency;

  /**
   * True if this denomination was revoked.
   */
  bool was_revoked;
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
   * Transaction status code.
   */
  enum GNUNET_DB_QueryStatus qs;

};


/**
 * Initialize information about denomination from the database.
 *
 * @param denom_hash hash of the public key of the denomination
 * @param[out] ds summary to initialize
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
init_denomination (const struct TALER_DenominationHashP *denom_hash,
                   struct DenominationSummary *ds)
{
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_MasterSignatureP msig;
  uint64_t rowid;

  qs = TALER_ARL_adb->get_denomination_balance (TALER_ARL_adb->cls,
                                                denom_hash,
                                                &ds->dcd);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    ds->in_db = true;
  }
  else
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (TALER_ARL_currency,
                                          &ds->dcd.denom_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (TALER_ARL_currency,
                                          &ds->dcd.denom_loss));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (TALER_ARL_currency,
                                          &ds->dcd.denom_risk));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (TALER_ARL_currency,
                                          &ds->dcd.recoup_loss));
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting balance for denomination `%s' is %s (%llu)\n",
              GNUNET_h2s (&denom_hash->hash),
              TALER_amount2s (&ds->dcd.denom_balance),
              (unsigned long long) ds->dcd.num_issued);
  qs = TALER_ARL_edb->get_denomination_revocation (TALER_ARL_edb->cls,
                                                   denom_hash,
                                                   &msig,
                                                   &rowid);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (0 < qs)
  {
    /* check revocation signature */
    if (GNUNET_OK !=
        TALER_exchange_offline_denomination_revoke_verify (
          denom_hash,
          &TALER_ARL_master_pub,
          &msig))
    {
      report_row_inconsistency ("denomination revocations",
                                rowid,
                                "revocation signature invalid");
    }
    else
    {
      ds->was_revoked = true;
    }
  }
  return ds->in_db
         ? GNUNET_DB_STATUS_SUCCESS_ONE_RESULT
         : GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
}


/**
 * Obtain the denomination summary for the given @a dh
 *
 * @param cc our execution context
 * @param issue denomination key information for @a dh
 * @param dh the denomination hash to use for the lookup
 * @return NULL on error
 */
static struct DenominationSummary *
get_denomination_summary (
  struct CoinContext *cc,
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue,
  const struct TALER_DenominationHashP *dh)
{
  struct DenominationSummary *ds;

  ds = GNUNET_CONTAINER_multihashmap_get (cc->denom_summaries,
                                          &dh->hash);
  if (NULL != ds)
    return ds;
  ds = GNUNET_new (struct DenominationSummary);
  ds->issue = issue;
  if (0 > (cc->qs = init_denomination (dh,
                                       ds)))
  {
    GNUNET_break (0);
    GNUNET_free (ds);
    return NULL;
  }
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONTAINER_multihashmap_put (cc->denom_summaries,
                                                    &dh->hash,
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
 * @param denom_hash the hash of the denomination key
 * @param value a `struct DenominationSummary`
 * @return #GNUNET_OK (continue to iterate)
 */
static enum GNUNET_GenericReturnValue
sync_denomination (void *cls,
                   const struct GNUNET_HashCode *denom_hash,
                   void *value)
{
  struct CoinContext *cc = cls;
  struct TALER_DenominationHashP denom_h = {
    .hash = *denom_hash
  };
  struct DenominationSummary *ds = value;
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue = ds->issue;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Timestamp expire_deposit;
  struct GNUNET_TIME_Absolute expire_deposit_grace;
  enum GNUNET_DB_QueryStatus qs;

  now = GNUNET_TIME_absolute_get ();
  expire_deposit = issue->expire_deposit;
  /* add day grace period to deal with clocks not being perfectly synchronized */
  expire_deposit_grace = GNUNET_TIME_absolute_add (expire_deposit.abs_time,
                                                   DEPOSIT_GRACE_PERIOD);
  if (GNUNET_TIME_absolute_cmp (now,
                                >,
                                expire_deposit_grace))
  {
    /* Denomination key has expired, book remaining balance of
       outstanding coins as revenue; and reduce cc->risk exposure. */
    if (ds->in_db)
      qs = TALER_ARL_adb->del_denomination_balance (TALER_ARL_adb->cls,
                                                    &denom_h);
    else
      qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
    if ((GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs) &&
        (! TALER_amount_is_zero (&ds->dcd.denom_risk)))
    {
      /* The denomination expired and carried a balance; we can now
         book the remaining balance as profit, and reduce our risk
         exposure by the accumulated risk of the denomination. */
      TALER_ARL_amount_subtract (&TALER_ARL_USE_AB (coin_balance_risk),
                                 &TALER_ARL_USE_AB (coin_balance_risk),
                                 &ds->dcd.denom_risk);
      /* If the above fails, our risk assessment is inconsistent!
         This is really, really bad (auditor-internal invariant
         would be violated). Hence we can "safely" assert.  If
         this assertion fails, well, good luck: there is a bug
         in the auditor _or_ the auditor's database is corrupt. */
    }
    if ((GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs) &&
        (! TALER_amount_is_zero (&ds->dcd.denom_balance)))
    {
      /* book denom_balance coin expiration profits! */
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Denomination `%s' expired, booking %s in expiration profits\n",
                  GNUNET_h2s (denom_hash),
                  TALER_amount2s (&ds->dcd.denom_balance));
      if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          (qs = TALER_ARL_adb->insert_historic_denom_revenue (
             TALER_ARL_adb->cls,
             &denom_h,
             expire_deposit,
             &ds->dcd.denom_balance,
             &ds->dcd.recoup_loss)))
      {
        /* Failed to store profits? Bad database */
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        cc->qs = qs;
      }
    }
  }
  else
  {
    /* Not expired, just store current denomination summary
       to auditor database for next iteration */
    long long cnt;

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Final balance for denomination `%s' is %s (%llu)\n",
                GNUNET_h2s (denom_hash),
                TALER_amount2s (&ds->dcd.denom_balance),
                (unsigned long long) ds->dcd.num_issued);
    cnt = TALER_ARL_edb->count_known_coins (TALER_ARL_edb->cls,
                                            &denom_h);
    if (0 > cnt)
    {
      /* Failed to obtain count? Bad database */
      qs = (enum GNUNET_DB_QueryStatus) cnt;
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      cc->qs = qs;
    }
    else
    {
      if (ds->dcd.num_issued < (uint64_t) cnt)
      {
        /* more coins deposited than issued! very bad */
        report_emergency_by_count (issue,
                                   ds->dcd.num_issued,
                                   cnt,
                                   &ds->dcd.denom_risk);
      }
      if (ds->report_emergency)
      {
        /* Value of coins deposited exceed value of coins
           issued! Also very bad! */
        report_emergency_by_amount (issue,
                                    &ds->dcd.denom_risk,
                                    &ds->dcd.denom_loss);

      }
      if (ds->in_db)
        qs = TALER_ARL_adb->update_denomination_balance (TALER_ARL_adb->cls,
                                                         &denom_h,
                                                         &ds->dcd);
      else
        qs = TALER_ARL_adb->insert_denomination_balance (TALER_ARL_adb->cls,
                                                         &denom_h,
                                                         &ds->dcd);
    }
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cc->qs = qs;
  }
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CONTAINER_multihashmap_remove (cc->denom_summaries,
                                                       denom_hash,
                                                       ds));
  GNUNET_free (ds);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != cc->qs)
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


/**
 * Function called with details about all withdraw operations.
 * Updates the denomination balance and the overall balance as
 * we now have additional coins that have been issued.
 *
 * Note that the signature was already checked in
 * taler-helper-auditor-reserves.c::#handle_reserve_out(), so we do not check
 * it again here.
 *
 * @param cls our `struct CoinContext`
 * @param rowid unique serial ID for the refresh session in our DB
 * @param h_blind_ev blinded hash of the coin's public key
 * @param denom_pub public denomination key of the deposited coin
 * @param reserve_pub public key of the reserve
 * @param reserve_sig signature over the withdraw operation (verified elsewhere)
 * @param execution_date when did the wallet withdraw the coin
 * @param amount_with_fee amount that was withdrawn
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
withdraw_cb (void *cls,
             uint64_t rowid,
             const struct TALER_BlindedCoinHashP *h_blind_ev,
             const struct TALER_DenominationPublicKey *denom_pub,
             const struct TALER_ReservePublicKeyP *reserve_pub,
             const struct TALER_ReserveSignatureP *reserve_sig,
             struct GNUNET_TIME_Timestamp execution_date,
             const struct TALER_Amount *amount_with_fee)
{
  struct CoinContext *cc = cls;
  struct DenominationSummary *ds;
  struct TALER_DenominationHashP dh;
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue;
  enum GNUNET_DB_QueryStatus qs;

  /* Note: some optimization potential here: lots of fields we
     could avoid fetching from the database with a custom function. */
  (void) h_blind_ev;
  (void) reserve_pub;
  (void) reserve_sig;
  (void) execution_date;
  (void) amount_with_fee;

  GNUNET_assert (rowid >=
                 TALER_ARL_USE_PP (coins_withdraw_serial_id)); /* should be monotonically increasing */
  TALER_ARL_USE_PP (coins_withdraw_serial_id) = rowid + 1;

  qs = TALER_ARL_get_denomination_info (denom_pub,
                                        &issue,
                                        &dh);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    report_row_inconsistency ("withdraw",
                              rowid,
                              "denomination key not found");
    return GNUNET_OK;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    /* This really ought to be a transient DB error. */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cc->qs = qs;
    return GNUNET_SYSERR;
  }
  ds = get_denomination_summary (cc,
                                 issue,
                                 &dh);
  if (NULL == ds)
  {
    /* cc->qs is set by #get_denomination_summary() */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == cc->qs);
    return GNUNET_SYSERR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Issued coin in denomination `%s' of total value %s\n",
              GNUNET_h2s (&dh.hash),
              TALER_amount2s (&issue->value));
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "New balance of denomination `%s' is %s\n",
              GNUNET_h2s (&dh.hash),
              TALER_amount2s (&ds->dcd.denom_balance));
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_escrowed),
                        &TALER_ARL_USE_AB (total_escrowed),
                        &issue->value);
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_balance_risk),
                        &TALER_ARL_USE_AB (coin_balance_risk),
                        &issue->value);
  ds->dcd.num_issued++;
  TALER_ARL_amount_add (&ds->dcd.denom_balance,
                        &ds->dcd.denom_balance,
                        &issue->value);
  TALER_ARL_amount_add (&ds->dcd.denom_risk,
                        &ds->dcd.denom_risk,
                        &issue->value);
  return GNUNET_OK;
}


/**
 * Closure for #reveal_data_cb().
 */
struct RevealContext
{

  /**
   * Denomination public data of the new coins.
   */
  const struct TALER_EXCHANGEDB_DenominationKeyInformation **new_issues;

  /**
   * Set to the size of the @a new_issues array.
   */
  unsigned int num_freshcoins;

  /**
   * Which coin row are we currently processing (for report generation).
   */
  uint64_t rowid;

  /**
   * Error status. #GNUNET_OK if all is OK.
   * #GNUNET_NO if a denomination key was not found
   * #GNUNET_SYSERR if we had a database error.
   */
  enum GNUNET_GenericReturnValue err;

  /**
   * Database error, if @e err is #GNUNET_SYSERR.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Function called with information about a refresh order.
 *
 * @param cls closure with a `struct RevealContext *` in it
 * @param num_freshcoins size of the @a rrcs array
 * @param rrcs array of @a num_freshcoins information about coins to be created
 */
static void
reveal_data_cb (void *cls,
                uint32_t num_freshcoins,
                const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs)
{
  struct RevealContext *rctx = cls;

  rctx->num_freshcoins = num_freshcoins;
  rctx->new_issues = GNUNET_new_array (
    num_freshcoins,
    const struct TALER_EXCHANGEDB_DenominationKeyInformation *);

  /* Update outstanding amounts for all new coin's denominations */
  for (unsigned int i = 0; i < num_freshcoins; i++)
  {
    enum GNUNET_DB_QueryStatus qs;

    /* lookup new coin denomination key */
    qs = TALER_ARL_get_denomination_info_by_hash (&rrcs[i].h_denom_pub,
                                                  &rctx->new_issues[i]);
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      report_row_inconsistency ("refresh_reveal",
                                rctx->rowid,
                                "denomination key not found");
      rctx->err = GNUNET_NO; /* terminate here, but return "OK" to commit transaction */
    }
    else if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      rctx->qs = qs;
      rctx->err = GNUNET_SYSERR; /* terminate, return #GNUNET_SYSERR: abort transaction */
    }
  }
}


/**
 * Check that the @a coin_pub is a known coin with a proper
 * signature for denominatinon @a denom_pub. If not, report
 * a loss of @a loss_potential.
 *
 * @param operation which operation is this about
 * @param issue denomination key information about the coin
 * @param rowid which row is this operation in
 * @param coin_pub public key of a coin
 * @param denom_pub expected denomination of the coin
 * @param loss_potential how big could the loss be if the coin is
 *        not properly signed
 * @return database transaction status, on success
 *  #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT
 */
static enum GNUNET_DB_QueryStatus
check_known_coin (
  const char *operation,
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue,
  uint64_t rowid,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_Amount *loss_potential)
{
  struct TALER_CoinPublicInfo ci;
  enum GNUNET_DB_QueryStatus qs;

  if (NULL == get_cached_history (coin_pub))
  {
    qs = check_coin_history (coin_pub,
                             rowid,
                             operation,
                             &issue->value);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return qs;
    }
    GNUNET_break (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs);
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Checking denomination signature on %s\n",
              TALER_B2S (coin_pub));
  qs = TALER_ARL_edb->get_known_coin (TALER_ARL_edb->cls,
                                      coin_pub,
                                      &ci);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_YES !=
      TALER_test_coin_valid (&ci,
                             denom_pub))
  {
    struct TALER_AUDITORDB_BadSigLosses bsl = {
      .operation = (char *) operation,
      .loss = *loss_potential,
      .operation_specific_pub = coin_pub->eddsa_pub
    };

    qs = TALER_ARL_adb->insert_bad_sig_losses (
      TALER_ARL_adb->cls,
      &bsl);
    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      // FIXME: error handling!
    }
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_irregular_loss),
                          &TALER_ARL_USE_AB (coin_irregular_loss),
                          loss_potential);
  }
  TALER_denom_sig_free (&ci.denom_sig);
  return qs;
}


/**
 * Update the denom balance in @a dso reducing it by
 * @a amount_with_fee. If this is not possible, report
 * an emergency.  Also updates the balance.
 *
 * @param dso denomination summary to update
 * @param rowid responsible row (for logging)
 * @param amount_with_fee amount to subtract
 */
static void
reduce_denom_balance (struct DenominationSummary *dso,
                      uint64_t rowid,
                      const struct TALER_Amount *amount_with_fee)
{
  struct TALER_Amount tmp;

  if (TALER_ARL_SR_INVALID_NEGATIVE ==
      TALER_ARL_amount_subtract_neg (&tmp,
                                     &dso->dcd.denom_balance,
                                     amount_with_fee))
  {
    TALER_ARL_amount_add (&dso->dcd.denom_loss,
                          &dso->dcd.denom_loss,
                          amount_with_fee);
    dso->report_emergency = true;
  }
  else
  {
    dso->dcd.denom_balance = tmp;
  }
  if (-1 == TALER_amount_cmp (&TALER_ARL_USE_AB (total_escrowed),
                              amount_with_fee))
  {
    /* This can theoretically happen if for example the exchange
       never issued any coins (i.e. escrow balance is zero), but
       accepted a forged coin (i.e. emergency situation after
       private key compromise). In that case, we cannot even
       subtract the profit we make from the fee from the escrow
       balance. Tested as part of test-auditor.sh, case #18 */
    report_amount_arithmetic_inconsistency (
      "subtracting amount from escrow balance",
      rowid,
      &TALER_ARL_USE_AB (total_escrowed),
      amount_with_fee,
      0);
  }
  else
  {
    TALER_ARL_amount_subtract (&TALER_ARL_USE_AB (total_escrowed),
                               &TALER_ARL_USE_AB (total_escrowed),
                               amount_with_fee);
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "New balance of denomination `%s' is %s\n",
              GNUNET_h2s (&dso->issue->denom_hash.hash),
              TALER_amount2s (&dso->dcd.denom_balance));
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
 * @param h_age_commitment hash of the age commitment for the coin
 * @param coin_pub public key of the coin
 * @param coin_sig signature from the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param noreveal_index which index was picked by the exchange in cut-and-choose
 * @param rc what is the refresh commitment
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
refresh_session_cb (void *cls,
                    uint64_t rowid,
                    const struct TALER_DenominationPublicKey *denom_pub,
                    const struct TALER_AgeCommitmentHash *h_age_commitment,
                    const struct TALER_CoinSpendPublicKeyP *coin_pub,
                    const struct TALER_CoinSpendSignatureP *coin_sig,
                    const struct TALER_Amount *amount_with_fee,
                    uint32_t noreveal_index,
                    const struct TALER_RefreshCommitmentP *rc)
{
  struct CoinContext *cc = cls;
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue;
  struct DenominationSummary *dso;
  struct TALER_Amount amount_without_fee;
  enum GNUNET_DB_QueryStatus qs;

  (void) noreveal_index;
  GNUNET_assert (rowid >=
                 TALER_ARL_USE_PP (coins_melt_serial_id)); /* should be monotonically increasing */
  TALER_ARL_USE_PP (coins_melt_serial_id) = rowid + 1;
  qs = TALER_ARL_get_denomination_info (denom_pub,
                                        &issue,
                                        NULL);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    report_row_inconsistency ("melt",
                              rowid,
                              "denomination key not found");
    return GNUNET_OK;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cc->qs = qs;
    return GNUNET_SYSERR;
  }
  qs = check_known_coin ("melt",
                         issue,
                         rowid,
                         coin_pub,
                         denom_pub,
                         amount_with_fee);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cc->qs = qs;
    return GNUNET_SYSERR;
  }
  /* verify melt signature */
  {
    struct TALER_DenominationHashP h_denom_pub;

    TALER_denom_pub_hash (denom_pub,
                          &h_denom_pub);
    if (GNUNET_OK !=
        TALER_wallet_melt_verify (amount_with_fee,
                                  &issue->fees.refresh,
                                  rc,
                                  &h_denom_pub,
                                  h_age_commitment,
                                  coin_pub,
                                  coin_sig))
    {
      struct TALER_AUDITORDB_BadSigLosses bsl = {
        .operation = "melt",
        .loss = *amount_with_fee,
        .operation_specific_pub = coin_pub->eddsa_pub
      };

      GNUNET_break_op (0);
      qs = TALER_ARL_adb->insert_bad_sig_losses (
        TALER_ARL_adb->cls,
        &bsl);
      if (qs < 0)
      {
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        // FIXME: error handling
      }
      TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_irregular_loss),
                            &TALER_ARL_USE_AB (coin_irregular_loss),
                            amount_with_fee);
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Melting coin %s in denomination `%s' of value %s\n",
              TALER_B2S (coin_pub),
              GNUNET_h2s (&issue->denom_hash.hash),
              TALER_amount2s (amount_with_fee));

  {
    struct TALER_Amount refresh_cost;
    struct RevealContext reveal_ctx = {
      .rowid = rowid,
      .err = GNUNET_OK
    };

    qs = TALER_ARL_edb->get_refresh_reveal (TALER_ARL_edb->cls,
                                            rc,
                                            &reveal_data_cb,
                                            &reveal_ctx);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return GNUNET_SYSERR;
    }
    if ((GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs) ||
        (0 == reveal_ctx.num_freshcoins))
    {
      /* This can legitimately happen if reveal was not yet called or only
         with invalid data, even if the exchange is correctly operating. We
         still report it. */
      struct TALER_AUDITORDB_RefreshesHanging rh = {
        .row_id = rowid,
        .amount = *amount_with_fee,
        .coin_pub = coin_pub->eddsa_pub
      };

      qs = TALER_ARL_adb->insert_refreshes_hanging (
        TALER_ARL_adb->cls,
        &rh);
      if (qs < 0)
      {
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        // FIXME: error handling!
      }
      TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_refresh_hanging),
                            &TALER_ARL_USE_AB (total_refresh_hanging),
                            amount_with_fee);
      return GNUNET_OK;
    }
    if (GNUNET_SYSERR == reveal_ctx.err)
      cc->qs = reveal_ctx.qs;

    if (GNUNET_OK != reveal_ctx.err)
    {
      GNUNET_free (reveal_ctx.new_issues);
      if (GNUNET_SYSERR == reveal_ctx.err)
        return GNUNET_SYSERR;
      return GNUNET_OK;
    }

    /* Check that the resulting amounts are consistent with the value being
     refreshed by calculating the total refresh cost */
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (amount_with_fee->currency,
                                          &refresh_cost));
    for (unsigned int i = 0; i < reveal_ctx.num_freshcoins; i++)
    {
      const struct TALER_EXCHANGEDB_DenominationKeyInformation *ni
        = reveal_ctx.new_issues[i];
      /* update cost of refresh */

      TALER_ARL_amount_add (&refresh_cost,
                            &refresh_cost,
                            &ni->fees.withdraw);
      TALER_ARL_amount_add (&refresh_cost,
                            &refresh_cost,
                            &ni->value);
    }

    /* compute contribution of old coin */
    if (TALER_ARL_SR_POSITIVE !=
        TALER_ARL_amount_subtract_neg (&amount_without_fee,
                                       amount_with_fee,
                                       &issue->fees.refresh))
    {
      /* Melt fee higher than contribution of melted coin; this makes
         no sense (exchange should never have accepted the operation) */
      report_amount_arithmetic_inconsistency ("melt contribution vs. fee",
                                              rowid,
                                              amount_with_fee,
                                              &issue->fees.refresh,
                                              -1);
      /* To continue, best assumption is the melted coin contributed
         nothing (=> all withdrawal amounts will be counted as losses) */
      GNUNET_assert (GNUNET_OK ==
                     TALER_amount_set_zero (TALER_ARL_currency,
                                            &amount_without_fee));
    }

    /* check old coin covers complete expenses (of refresh operation) */
    if (1 == TALER_amount_cmp (&refresh_cost,
                               &amount_without_fee))
    {
      /* refresh_cost > amount_without_fee, which is bad (exchange lost) */
      GNUNET_break_op (0);
      report_amount_arithmetic_inconsistency ("melt (cost)",
                                              rowid,
                                              &amount_without_fee, /* 'exchange' */
                                              &refresh_cost, /* 'auditor' */
                                              1);
    }

    /* update outstanding denomination amounts for fresh coins withdrawn */
    for (unsigned int i = 0; i < reveal_ctx.num_freshcoins; i++)
    {
      const struct TALER_EXCHANGEDB_DenominationKeyInformation *ni
        = reveal_ctx.new_issues[i];
      struct DenominationSummary *dsi;

      dsi = get_denomination_summary (cc,
                                      ni,
                                      &ni->denom_hash);
      if (NULL == dsi)
      {
        report_row_inconsistency ("refresh_reveal",
                                  rowid,
                                  "denomination key for fresh coin unknown to auditor");
      }
      else
      {
        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "Created fresh coin in denomination `%s' of value %s\n",
                    GNUNET_h2s (&ni->denom_hash.hash),
                    TALER_amount2s (&ni->value));
        dsi->dcd.num_issued++;
        TALER_ARL_amount_add (&dsi->dcd.denom_balance,
                              &dsi->dcd.denom_balance,
                              &ni->value);
        TALER_ARL_amount_add (&dsi->dcd.denom_risk,
                              &dsi->dcd.denom_risk,
                              &ni->value);
        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "New balance of denomination `%s' is %s\n",
                    GNUNET_h2s (&ni->denom_hash.hash),
                    TALER_amount2s (&dsi->dcd.denom_balance));
        TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_escrowed),
                              &TALER_ARL_USE_AB (total_escrowed),
                              &ni->value);
        TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_balance_risk),
                              &TALER_ARL_USE_AB (coin_balance_risk),
                              &ni->value);
      }
    }
    GNUNET_free (reveal_ctx.new_issues);
  }

  /* update old coin's denomination balance */
  dso = get_denomination_summary (cc,
                                  issue,
                                  &issue->denom_hash);
  if (NULL == dso)
  {
    report_row_inconsistency ("refresh_reveal",
                              rowid,
                              "denomination key for dirty coin unknown to auditor");
  }
  else
  {
    reduce_denom_balance (dso,
                          rowid,
                          amount_with_fee);
  }

  /* update global melt fees */
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_melt_fee_revenue),
                        &TALER_ARL_USE_AB (coin_melt_fee_revenue),
                        &issue->fees.refresh);
  return GNUNET_OK;
}


/**
 * Function called with details about deposits that have been made,
 * with the goal of auditing the deposit's execution.
 *
 * @param cls closure
 * @param rowid unique serial ID for the deposit in our DB
 * @param exchange_timestamp when did the exchange get the deposit
 * @param deposit deposit details
 * @param denom_pub denomination public key of @a coin_pub
 * @param done flag set if the deposit was already executed (or not)
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
deposit_cb (void *cls,
            uint64_t rowid,
            struct GNUNET_TIME_Timestamp exchange_timestamp,
            const struct TALER_EXCHANGEDB_Deposit *deposit,
            const struct TALER_DenominationPublicKey *denom_pub,
            bool done)
{
  struct CoinContext *cc = cls;
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue;
  struct DenominationSummary *ds;
  enum GNUNET_DB_QueryStatus qs;

  (void) done;
  (void) exchange_timestamp;
  GNUNET_assert (rowid >=
                 TALER_ARL_USE_PP (coins_deposit_serial_id)); /* should be monotonically increasing */
  TALER_ARL_USE_PP (coins_deposit_serial_id) = rowid + 1;

  qs = TALER_ARL_get_denomination_info (denom_pub,
                                        &issue,
                                        NULL);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    report_row_inconsistency ("deposits",
                              rowid,
                              "denomination key not found");
    return GNUNET_OK;
  }
  if (GNUNET_TIME_timestamp_cmp (deposit->refund_deadline,
                                 >,
                                 deposit->wire_deadline))
  {
    report_row_inconsistency ("deposits",
                              rowid,
                              "refund deadline past wire deadline");
  }

  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cc->qs = qs;
    return GNUNET_SYSERR;
  }
  qs = check_known_coin ("deposit",
                         issue,
                         rowid,
                         &deposit->coin.coin_pub,
                         denom_pub,
                         &deposit->amount_with_fee);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cc->qs = qs;
    return GNUNET_SYSERR;
  }

  /* Verify deposit signature */
  {
    struct TALER_MerchantWireHashP h_wire;
    struct TALER_DenominationHashP h_denom_pub;

    TALER_denom_pub_hash (denom_pub,
                          &h_denom_pub);
    TALER_merchant_wire_signature_hash (deposit->receiver_wire_account,
                                        &deposit->wire_salt,
                                        &h_wire);
    /* NOTE: This is one of the operations we might eventually
       want to do in parallel in the background to improve
       auditor performance! */
    if (GNUNET_OK !=
        TALER_wallet_deposit_verify (&deposit->amount_with_fee,
                                     &issue->fees.deposit,
                                     &h_wire,
                                     &deposit->h_contract_terms,
                                     deposit->no_wallet_data_hash
                                     ? NULL
                                     : &deposit->wallet_data_hash,
                                     &deposit->coin.h_age_commitment,
                                     &deposit->h_policy,
                                     &h_denom_pub,
                                     deposit->timestamp,
                                     &deposit->merchant_pub,
                                     deposit->refund_deadline,
                                     &deposit->coin.coin_pub,
                                     &deposit->csig))
    {
      struct TALER_AUDITORDB_BadSigLosses bsl = {
        .operation = "deposit",
        .loss = deposit->amount_with_fee,
        .operation_specific_pub = deposit->coin.coin_pub.eddsa_pub
      };

      qs = TALER_ARL_adb->insert_bad_sig_losses (
        TALER_ARL_adb->cls,
        &bsl);

      if (qs < 0)
      {
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        // FIXME: error handling!
      }
      TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_irregular_loss),
                            &TALER_ARL_USE_AB (coin_irregular_loss),
                            &deposit->amount_with_fee);
      return GNUNET_OK;
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Deposited coin %s in denomination `%s' of value %s\n",
              TALER_B2S (&deposit->coin.coin_pub),
              GNUNET_h2s (&issue->denom_hash.hash),
              TALER_amount2s (&deposit->amount_with_fee));

  /* update old coin's denomination balance */
  ds = get_denomination_summary (cc,
                                 issue,
                                 &issue->denom_hash);
  if (NULL == ds)
  {
    report_row_inconsistency ("deposit",
                              rowid,
                              "denomination key for deposited coin unknown to auditor");
  }
  else
  {
    reduce_denom_balance (ds,
                          rowid,
                          &deposit->amount_with_fee);
  }

  /* update global deposit fees */
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_deposit_fee_revenue),
                        &TALER_ARL_USE_AB (coin_deposit_fee_revenue),
                        &issue->fees.deposit);
  return GNUNET_OK;
}


/**
 * Function called with details about coins that were refunding,
 * with the goal of auditing the refund's execution.  Adds the
 * refunded amount back to the outstanding balance of the respective
 * denomination.
 *
 * @param cls closure
 * @param rowid unique serial ID for the refund in our DB
 * @param denom_pub denomination public key of @a coin_pub
 * @param coin_pub public key of the coin
 * @param merchant_pub public key of the merchant
 * @param merchant_sig signature of the merchant
 * @param h_contract_terms hash of the proposal data known to merchant and customer
 * @param rtransaction_id refund transaction ID chosen by the merchant
 * @param full_refund true if the refunds total up to the entire deposited value
 * @param amount_with_fee amount that was deposited including fee
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
refund_cb (void *cls,
           uint64_t rowid,
           const struct TALER_DenominationPublicKey *denom_pub,
           const struct TALER_CoinSpendPublicKeyP *coin_pub,
           const struct TALER_MerchantPublicKeyP *merchant_pub,
           const struct TALER_MerchantSignatureP *merchant_sig,
           const struct TALER_PrivateContractHashP *h_contract_terms,
           uint64_t rtransaction_id,
           bool full_refund,
           const struct TALER_Amount *amount_with_fee)
{
  struct CoinContext *cc = cls;
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue;
  struct DenominationSummary *ds;
  struct TALER_Amount amount_without_fee;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_assert (rowid >= TALER_ARL_USE_PP (coins_refund_serial_id)); /* should be monotonically increasing */
  TALER_ARL_USE_PP (coins_refund_serial_id) = rowid + 1;

  qs = TALER_ARL_get_denomination_info (denom_pub,
                                        &issue,
                                        NULL);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    report_row_inconsistency ("refunds",
                              rowid,
                              "denomination key not found");
    return GNUNET_OK;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return GNUNET_SYSERR;
  }

  /* verify refund signature */
  if (GNUNET_OK !=
      TALER_merchant_refund_verify (coin_pub,
                                    h_contract_terms,
                                    rtransaction_id,
                                    amount_with_fee,
                                    merchant_pub,
                                    merchant_sig))
  {
    struct TALER_AUDITORDB_BadSigLosses bsl = {
      .operation = "refund",
      .loss = *amount_with_fee,
      .operation_specific_pub = coin_pub->eddsa_pub
    };

    qs = TALER_ARL_adb->insert_bad_sig_losses (
      TALER_ARL_adb->cls,
      &bsl);
    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      // FIXME: error handling
    }
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_irregular_loss),
                          &TALER_ARL_USE_AB (coin_irregular_loss),
                          amount_with_fee);
    return GNUNET_OK;
  }

  if (TALER_ARL_SR_INVALID_NEGATIVE ==
      TALER_ARL_amount_subtract_neg (&amount_without_fee,
                                     amount_with_fee,
                                     &issue->fees.refund))
  {
    report_amount_arithmetic_inconsistency ("refund (fee)",
                                            rowid,
                                            &amount_without_fee,
                                            &issue->fees.refund,
                                            -1);
    return GNUNET_OK;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Refunding coin %s in denomination `%s' value %s\n",
              TALER_B2S (coin_pub),
              GNUNET_h2s (&issue->denom_hash.hash),
              TALER_amount2s (amount_with_fee));

  /* update coin's denomination balance */
  ds = get_denomination_summary (cc,
                                 issue,
                                 &issue->denom_hash);
  if (NULL == ds)
  {
    report_row_inconsistency ("refund",
                              rowid,
                              "denomination key for refunded coin unknown to auditor");
  }
  else
  {
    TALER_ARL_amount_add (&ds->dcd.denom_balance,
                          &ds->dcd.denom_balance,
                          &amount_without_fee);
    TALER_ARL_amount_add (&ds->dcd.denom_risk,
                          &ds->dcd.denom_risk,
                          &amount_without_fee);
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_escrowed),
                          &TALER_ARL_USE_AB (total_escrowed),
                          &amount_without_fee);
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_balance_risk),
                          &TALER_ARL_USE_AB (coin_balance_risk),
                          &amount_without_fee);
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "New balance of denomination `%s' after refund is %s\n",
                GNUNET_h2s (&issue->denom_hash.hash),
                TALER_amount2s (&ds->dcd.denom_balance));
  }
  /* update total refund fee balance */
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_refund_fee_revenue),
                        &TALER_ARL_USE_AB (coin_refund_fee_revenue),
                        &issue->fees.refund);
  if (full_refund)
  {
    TALER_ARL_amount_subtract (&TALER_ARL_USE_AB (coin_deposit_fee_revenue),
                               &TALER_ARL_USE_AB (coin_deposit_fee_revenue),
                               &issue->fees.deposit);
  }
  return GNUNET_OK;
}


/**
 * Function called with details about purse refunds that have been made, with
 * the goal of auditing the purse refund's execution.
 *
 * @param cls closure
 * @param rowid row of the purse-refund
 * @param amount_with_fee amount of the deposit into the purse
 * @param coin_pub coin that is to be refunded the @a given amount_with_fee
 * @param denom_pub denomination of @a coin_pub
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
purse_refund_coin_cb (
  void *cls,
  uint64_t rowid,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_DenominationPublicKey *denom_pub)
{
  struct CoinContext *cc = cls;
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue;
  struct DenominationSummary *ds;
  enum GNUNET_DB_QueryStatus qs;

  qs = TALER_ARL_get_denomination_info (denom_pub,
                                        &issue,
                                        NULL);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    report_row_inconsistency ("purse-refunds",
                              rowid,
                              "denomination key not found");
    return GNUNET_OK;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return GNUNET_SYSERR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Aborted purse-deposit of coin %s in denomination `%s' value %s\n",
              TALER_B2S (coin_pub),
              GNUNET_h2s (&issue->denom_hash.hash),
              TALER_amount2s (amount_with_fee));

  /* update coin's denomination balance */
  ds = get_denomination_summary (cc,
                                 issue,
                                 &issue->denom_hash);
  if (NULL == ds)
  {
    report_row_inconsistency ("purse-refund",
                              rowid,
                              "denomination key for purse-refunded coin unknown to auditor");
  }
  else
  {
    TALER_ARL_amount_add (&ds->dcd.denom_balance,
                          &ds->dcd.denom_balance,
                          amount_with_fee);
    TALER_ARL_amount_add (&ds->dcd.denom_risk,
                          &ds->dcd.denom_risk,
                          amount_with_fee);
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_escrowed),
                          &TALER_ARL_USE_AB (total_escrowed),
                          amount_with_fee);
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_balance_risk),
                          &TALER_ARL_USE_AB (coin_balance_risk),
                          amount_with_fee);
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "New balance of denomination `%s' after purse-refund is %s\n",
                GNUNET_h2s (&issue->denom_hash.hash),
                TALER_amount2s (&ds->dcd.denom_balance));
  }
  /* update total deposit fee balance */
  TALER_ARL_amount_subtract (&TALER_ARL_USE_AB (coin_deposit_fee_revenue),
                             &TALER_ARL_USE_AB (coin_deposit_fee_revenue),
                             &issue->fees.deposit);

  return GNUNET_OK;
}


/**
 * Function called with details about a purse that was refunded.  Adds the
 * refunded amounts back to the outstanding balance of the respective
 * denominations.
 *
 * @param cls closure
 * @param rowid unique serial ID for the refund in our DB
 * @param purse_pub public key of the purse
 * @param reserve_pub public key of the targeted reserve (ignored)
 * @param val targeted amount to be in the reserve (ignored)
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
purse_refund_cb (void *cls,
                 uint64_t rowid,
                 const struct TALER_PurseContractPublicKeyP *purse_pub,
                 const struct TALER_ReservePublicKeyP *reserve_pub,
                 const struct TALER_Amount *val)
{
  struct CoinContext *cc = cls;
  enum GNUNET_DB_QueryStatus qs;

  (void) val; /* irrelevant on refund */
  (void) reserve_pub; /* irrelevant, may even be NULL */
  GNUNET_assert (rowid >=
                 TALER_ARL_USE_PP (coins_purse_refunds_serial_id)); /* should be monotonically increasing */
  TALER_ARL_USE_PP (coins_purse_refunds_serial_id) = rowid + 1;
  qs = TALER_ARL_edb->select_purse_deposits_by_purse (TALER_ARL_edb->cls,
                                                      purse_pub,
                                                      &purse_refund_coin_cb,
                                                      cc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Check that the recoup operation was properly initiated by a coin
 * and update the denomination's losses accordingly.
 *
 * @param cc the context with details about the coin
 * @param operation name of the operation matching @a rowid
 * @param rowid row identifier used to uniquely identify the recoup operation
 * @param amount how much should be added back to the reserve
 * @param coin public information about the coin
 * @param denom_pub public key of the denomionation of @a coin
 * @param coin_sig signature with @e coin_pub of type #TALER_SIGNATURE_WALLET_COIN_RECOUP
 * @param coin_blind blinding factor used to blind the coin
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
check_recoup (struct CoinContext *cc,
              const char *operation,
              uint64_t rowid,
              const struct TALER_Amount *amount,
              const struct TALER_CoinPublicInfo *coin,
              const struct TALER_DenominationPublicKey *denom_pub,
              const struct TALER_CoinSpendSignatureP *coin_sig,
              const union GNUNET_CRYPTO_BlindingSecretP *coin_blind)
{
  struct DenominationSummary *ds;
  enum GNUNET_DB_QueryStatus qs;
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue;

  if (GNUNET_OK !=
      TALER_wallet_recoup_verify (&coin->denom_pub_hash,
                                  coin_blind,
                                  &coin->coin_pub,
                                  coin_sig))
  {
    report_row_inconsistency (operation,
                              rowid,
                              "recoup signature invalid");
  }
  if (GNUNET_OK !=
      TALER_test_coin_valid (coin,
                             denom_pub))
  {
    struct TALER_AUDITORDB_BadSigLosses bsl = {
      .operation = (char *) operation,
      .loss = *amount,
      // TODO: maybe adding the wrong pub
      bsl.operation_specific_pub = coin->coin_pub.eddsa_pub
    };

    qs = TALER_ARL_adb->insert_bad_sig_losses (
      TALER_ARL_adb->cls,
      &bsl);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      // FIXME: error handling
    }
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_irregular_loss),
                          &TALER_ARL_USE_AB (coin_irregular_loss),
                          amount);
  }
  qs = TALER_ARL_get_denomination_info_by_hash (&coin->denom_pub_hash,
                                                &issue);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    report_row_inconsistency (operation,
                              rowid,
                              "denomination key not found");
    return GNUNET_OK;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    /* The key not existing should be prevented by foreign key constraints,
       so must be a transient DB error. */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cc->qs = qs;
    return GNUNET_SYSERR;
  }
  qs = check_known_coin (operation,
                         issue,
                         rowid,
                         &coin->coin_pub,
                         denom_pub,
                         amount);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cc->qs = qs;
    return GNUNET_SYSERR;
  }
  ds = get_denomination_summary (cc,
                                 issue,
                                 &issue->denom_hash);
  if (NULL == ds)
  {
    report_row_inconsistency ("recoup",
                              rowid,
                              "denomination key for recouped coin unknown to auditor");
  }
  else
  {
    if (! ds->was_revoked)
    {
      struct TALER_AUDITORDB_BadSigLosses bsldnr = {
        .operation = (char *) operation,
        .loss = *amount,
        // TODO: hint missing?
        .operation_specific_pub = coin->coin_pub.eddsa_pub
      };

      qs = TALER_ARL_adb->insert_bad_sig_losses (
        TALER_ARL_adb->cls,
        &bsldnr);

      if (qs < 0)
      {
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        // FIXME: error handling!
      }
      TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_irregular_loss),
                            &TALER_ARL_USE_AB (coin_irregular_loss),
                            amount);
    }
    TALER_ARL_amount_add (&ds->dcd.recoup_loss,
                          &ds->dcd.recoup_loss,
                          amount);
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_recoup_loss),
                          &TALER_ARL_USE_AB (total_recoup_loss),
                          amount);
  }
  return GNUNET_OK;
}


/**
 * Function called about recoups the exchange has to perform.
 *
 * @param cls a `struct CoinContext *`
 * @param rowid row identifier used to uniquely identify the recoup operation
 * @param timestamp when did we receive the recoup request
 * @param amount how much should be added back to the reserve
 * @param reserve_pub public key of the reserve
 * @param coin public information about the coin
 * @param denom_pub denomination public key of @a coin
 * @param coin_sig signature with @e coin_pub of type #TALER_SIGNATURE_WALLET_COIN_RECOUP
 * @param coin_blind blinding factor used to blind the coin
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
recoup_cb (void *cls,
           uint64_t rowid,
           struct GNUNET_TIME_Timestamp timestamp,
           const struct TALER_Amount *amount,
           const struct TALER_ReservePublicKeyP *reserve_pub,
           const struct TALER_CoinPublicInfo *coin,
           const struct TALER_DenominationPublicKey *denom_pub,
           const struct TALER_CoinSpendSignatureP *coin_sig,
           const union GNUNET_CRYPTO_BlindingSecretP *coin_blind)
{
  struct CoinContext *cc = cls;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_assert (rowid >= TALER_ARL_USE_PP (coins_recoup_serial_id)); /* should be monotonically increasing */
  TALER_ARL_USE_PP (coins_recoup_serial_id) = rowid + 1;
  (void) timestamp;
  (void) reserve_pub;
  if (GNUNET_OK !=
      TALER_wallet_recoup_verify (&coin->denom_pub_hash,
                                  coin_blind,
                                  &coin->coin_pub,
                                  coin_sig))
  {
    struct TALER_AUDITORDB_BadSigLosses bsl = {
      .operation = "recoup",
      .loss = *amount,
      .operation_specific_pub = coin->coin_pub.eddsa_pub
    };

    qs = TALER_ARL_adb->insert_bad_sig_losses (
      TALER_ARL_adb->cls,
      &bsl);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      // FIXME: error handling!
    }
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_irregular_loss),
                          &TALER_ARL_USE_AB (coin_irregular_loss),
                          amount);
    return GNUNET_OK;
  }
  return check_recoup (cc,
                       "recoup",
                       rowid,
                       amount,
                       coin,
                       denom_pub,
                       coin_sig,
                       coin_blind);
}


/**
 * Function called about recoups on refreshed coins the exchange has to
 * perform.
 *
 * @param cls a `struct CoinContext *`
 * @param rowid row identifier used to uniquely identify the recoup operation
 * @param timestamp when did we receive the recoup request
 * @param amount how much should be added back to the reserve
 * @param old_coin_pub original coin that was refreshed to create @a coin
 * @param old_denom_pub_hash hash of the public key of @a old_coin_pub
 * @param coin public information about the coin
 * @param denom_pub denomination public key of @a coin
 * @param coin_sig signature with @e coin_pub of type #TALER_SIGNATURE_WALLET_COIN_RECOUP
 * @param coin_blind blinding factor used to blind the coin
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
recoup_refresh_cb (void *cls,
                   uint64_t rowid,
                   struct GNUNET_TIME_Timestamp timestamp,
                   const struct TALER_Amount *amount,
                   const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
                   const struct TALER_DenominationHashP *old_denom_pub_hash,
                   const struct TALER_CoinPublicInfo *coin,
                   const struct TALER_DenominationPublicKey *denom_pub,
                   const struct TALER_CoinSpendSignatureP *coin_sig,
                   const union GNUNET_CRYPTO_BlindingSecretP *coin_blind)
{
  struct CoinContext *cc = cls;
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue;
  enum GNUNET_DB_QueryStatus qs;

  (void) timestamp;
  (void) old_coin_pub;
  GNUNET_assert (rowid >= TALER_ARL_USE_PP (coins_recoup_refresh_serial_id)); /* should be monotonically increasing */
  TALER_ARL_USE_PP (coins_recoup_refresh_serial_id) = rowid + 1;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Recoup-refresh amount is %s\n",
              TALER_amount2s (amount));

  /* Update old coin's denomination balance summary */
  qs = TALER_ARL_get_denomination_info_by_hash (old_denom_pub_hash,
                                                &issue);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS >= qs)
  {
    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      cc->qs = qs;
      return GNUNET_SYSERR;
    }
    report_row_inconsistency ("refresh-recoup",
                              rowid,
                              "denomination key of old coin not found");
  }
  else
  {
    struct DenominationSummary *dso;

    dso = get_denomination_summary (cc,
                                    issue,
                                    old_denom_pub_hash);
    if (NULL == dso)
    {
      report_row_inconsistency ("refresh_reveal",
                                rowid,
                                "denomination key for old coin unknown to auditor");
    }
    else
    {
      TALER_ARL_amount_add (&dso->dcd.denom_balance,
                            &dso->dcd.denom_balance,
                            amount);
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "New balance of denomination `%s' after refresh-recoup is %s\n",
                  GNUNET_h2s (&issue->denom_hash.hash),
                  TALER_amount2s (&dso->dcd.denom_balance));
    }
  }

  if (GNUNET_OK !=
      TALER_wallet_recoup_refresh_verify (&coin->denom_pub_hash,
                                          coin_blind,
                                          &coin->coin_pub,
                                          coin_sig))
  {
    struct TALER_AUDITORDB_BadSigLosses bsl = {
      .operation = "recoup-refresh",
      .loss = *amount,
      .operation_specific_pub = coin->coin_pub.eddsa_pub
    };

    qs = TALER_ARL_adb->insert_bad_sig_losses (
      TALER_ARL_adb->cls,
      &bsl);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      // FIXME: error handling
    }
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_irregular_loss),
                          &TALER_ARL_USE_AB (coin_irregular_loss),
                          amount);
    return GNUNET_OK;
  }
  return check_recoup (cc,
                       "recoup-refresh",
                       rowid,
                       amount,
                       coin,
                       denom_pub,
                       coin_sig,
                       coin_blind);
}


/**
 * Function called with the results of iterate_denomination_info(),
 * or directly (!).  Used to check that we correctly signed the
 * denomination and to warn if there are denominations not approved
 * by this auditor.
 *
 * @param cls closure, NULL
 * @param denom_pub public key, sometimes NULL (!)
 * @param issue issuing information with value, fees and other info about the denomination.
 */
static void
check_denomination (
  void *cls,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue)
{
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_AuditorSignatureP auditor_sig;

  (void) cls;
  (void) denom_pub;
  qs = TALER_ARL_edb->select_auditor_denom_sig (TALER_ARL_edb->cls,
                                                &issue->denom_hash,
                                                &TALER_ARL_auditor_pub,
                                                &auditor_sig);
  if (0 > qs)
  {
    GNUNET_break (0);
    return; /* skip! */
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Encountered denomination `%s' (%s) valid from %s (%llu-%llu) that this auditor is not auditing!\n",
                GNUNET_h2s (&issue->denom_hash.hash),
                TALER_amount2s (&issue->value),
                GNUNET_TIME_timestamp2s (issue->start),
                (unsigned long long) issue->start.abs_time.abs_value_us,
                (unsigned long long) issue->expire_legal.abs_time.abs_value_us);
    return; /* skip! */
  }
  if (GNUNET_OK !=
      TALER_auditor_denom_validity_verify (
        TALER_ARL_auditor_url,
        &issue->denom_hash,
        &TALER_ARL_master_pub,
        issue->start,
        issue->expire_withdraw,
        issue->expire_deposit,
        issue->expire_legal,
        &issue->value,
        &issue->fees,
        &TALER_ARL_auditor_pub,
        &auditor_sig))
  {
    struct TALER_AUDITORDB_DenominationsWithoutSigs dws = {
      .denompub_h = issue->denom_hash,
      .start_time = issue->start.abs_time,
      .end_time = issue->expire_legal.abs_time,
      .value = issue->value
    };

    qs = TALER_ARL_adb->insert_denominations_without_sigs (
      TALER_ARL_adb->cls,
      &dws);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      // FIXME: error handling!
    }
  }
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
purse_deposit_cb (
  void *cls,
  uint64_t rowid,
  const struct TALER_EXCHANGEDB_PurseDeposit *deposit,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  enum TALER_WalletAccountMergeFlags flags,
  const struct TALER_Amount *auditor_balance,
  const struct TALER_Amount *purse_total,
  const struct TALER_DenominationPublicKey *denom_pub)
{
  struct CoinContext *cc = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_DenominationHashP dh;
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue;
  struct DenominationSummary *ds;

  (void) flags;
  (void) auditor_balance;
  (void) purse_total;
  (void) reserve_pub;
  GNUNET_assert (rowid >=
                 TALER_ARL_USE_PP (coins_purse_deposits_serial_id));
  TALER_ARL_USE_PP (coins_purse_deposits_serial_id) = rowid + 1;
  qs = TALER_ARL_get_denomination_info (denom_pub,
                                        &issue,
                                        &dh);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    report_row_inconsistency ("purse-deposits",
                              rowid,
                              "denomination key not found");
    return GNUNET_OK;
  }
  qs = check_known_coin ("purse-deposit",
                         issue,
                         rowid,
                         &deposit->coin_pub,
                         denom_pub,
                         &deposit->amount);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cc->qs = qs;
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      TALER_wallet_purse_deposit_verify (
        NULL != deposit->exchange_base_url
        ? deposit->exchange_base_url
        : TALER_ARL_exchange_url,
        &deposit->purse_pub,
        &deposit->amount,
        &dh,
        &deposit->h_age_commitment,
        &deposit->coin_pub,
        &deposit->coin_sig))
  {
    struct TALER_AUDITORDB_BadSigLosses bsl = {
      .operation = "purse-deposit",
      .loss = deposit->amount,
      .operation_specific_pub = deposit->coin_pub.eddsa_pub
    };

    qs = TALER_ARL_adb->insert_bad_sig_losses (
      TALER_ARL_adb->cls,
      &bsl);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      // FIXME: error handling!
    }
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_irregular_loss),
                          &TALER_ARL_USE_AB (coin_irregular_loss),
                          &deposit->amount);
    return GNUNET_OK;
  }

  /* update coin's denomination balance */
  ds = get_denomination_summary (cc,
                                 issue,
                                 &issue->denom_hash);
  if (NULL == ds)
  {
    report_row_inconsistency ("purse-deposit",
                              rowid,
                              "denomination key for purse-deposited coin unknown to auditor");
  }
  else
  {
    reduce_denom_balance (ds,
                          rowid,
                          &deposit->amount);
  }

  /* update global deposit fees */
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (coin_deposit_fee_revenue),
                        &TALER_ARL_USE_AB (coin_deposit_fee_revenue),
                        &issue->fees.deposit);
  return GNUNET_OK;
}


/**
 * Analyze the exchange's processing of coins.
 *
 * @param cls closure
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
analyze_coins (void *cls)
{
  struct CoinContext cc;
  enum GNUNET_DB_QueryStatus qs;
  enum GNUNET_DB_QueryStatus qsx;
  enum GNUNET_DB_QueryStatus qsp;

  (void) cls;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Checking denominations...\n");
  qs = TALER_ARL_edb->iterate_denomination_info (TALER_ARL_edb->cls,
                                                 &check_denomination,
                                                 NULL);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Analyzing coins\n");
  qsp = TALER_ARL_adb->get_auditor_progress (
    TALER_ARL_adb->cls,
    TALER_ARL_GET_PP (coins_withdraw_serial_id),
    TALER_ARL_GET_PP (coins_deposit_serial_id),
    TALER_ARL_GET_PP (coins_melt_serial_id),
    TALER_ARL_GET_PP (coins_refund_serial_id),
    TALER_ARL_GET_PP (coins_recoup_serial_id),
    TALER_ARL_GET_PP (coins_recoup_refresh_serial_id),
    TALER_ARL_GET_PP (coins_purse_deposits_serial_id),
    TALER_ARL_GET_PP (coins_purse_refunds_serial_id),
    NULL);
  if (0 > qsp)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsp);
    return qsp;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsp)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "First analysis using this auditor, starting from scratch\n");
  }
  else
  {
    GNUNET_log (
      GNUNET_ERROR_TYPE_INFO,
      "Resuming coin audit at %llu/%llu/%llu/%llu/%llu/%llu/%llu\n",
      (unsigned long long) TALER_ARL_USE_PP (
        coins_deposit_serial_id),
      (unsigned long long) TALER_ARL_USE_PP (
        coins_melt_serial_id),
      (unsigned long long) TALER_ARL_USE_PP (
        coins_refund_serial_id),
      (unsigned long long) TALER_ARL_USE_PP (
        coins_withdraw_serial_id),
      (unsigned long long) TALER_ARL_USE_PP (
        coins_recoup_refresh_serial_id),
      (unsigned long long) TALER_ARL_USE_PP (
        coins_purse_deposits_serial_id),
      (unsigned long long) TALER_ARL_USE_PP (
        coins_purse_refunds_serial_id));
  }

  /* setup 'cc' */
  cc.qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  cc.denom_summaries = GNUNET_CONTAINER_multihashmap_create (256,
                                                             GNUNET_NO);
  qsx = TALER_ARL_adb->get_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_GET_AB (coin_balance_risk),
    TALER_ARL_GET_AB (total_escrowed),
    TALER_ARL_GET_AB (coin_irregular_loss),
    TALER_ARL_GET_AB (coin_melt_fee_revenue),
    TALER_ARL_GET_AB (coin_deposit_fee_revenue),
    TALER_ARL_GET_AB (coin_refund_fee_revenue),
    TALER_ARL_GET_AB (total_recoup_loss),
    TALER_ARL_GET_AB (coins_total_arithmetic_delta_plus),
    TALER_ARL_GET_AB (coins_total_arithmetic_delta_minus),
    TALER_ARL_GET_AB (coins_reported_emergency_risk_by_count),
    TALER_ARL_GET_AB (coins_reported_emergency_risk_by_amount),
    TALER_ARL_GET_AB (coins_emergencies_loss),
    TALER_ARL_GET_AB (total_refresh_hanging),
    NULL);
  if (0 > qsx)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsx);
    return qsx;
  }
  /* process withdrawals */
  if (0 >
      (qs = TALER_ARL_edb->select_withdrawals_above_serial_id (
         TALER_ARL_edb->cls,
         TALER_ARL_USE_PP (coins_withdraw_serial_id),
         &withdraw_cb,
         &cc)))
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (0 > cc.qs)
    return cc.qs;
  /* process refunds */
  if (0 >
      (qs = TALER_ARL_edb->select_refunds_above_serial_id (
         TALER_ARL_edb->cls,
         TALER_ARL_USE_PP (coins_refund_serial_id),
         &refund_cb,
         &cc)))
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (0 > cc.qs)
    return cc.qs;
  /* process purse_refunds */
  if (0 >
      (qs = TALER_ARL_edb->select_purse_decisions_above_serial_id (
         TALER_ARL_edb->cls,
         TALER_ARL_USE_PP (coins_purse_refunds_serial_id),
         true, /* only go for refunds! */
         &purse_refund_cb,
         &cc)))
  {

    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (0 > cc.qs)
    return cc.qs;

  /* process recoups */
  if (0 >
      (qs = TALER_ARL_edb->select_recoup_refresh_above_serial_id (
         TALER_ARL_edb->cls,
         TALER_ARL_USE_PP (coins_recoup_refresh_serial_id),
         &recoup_refresh_cb,
         &cc)))
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (0 > cc.qs)
    return cc.qs;
  if (0 >
      (qs = TALER_ARL_edb->select_recoup_above_serial_id (
         TALER_ARL_edb->cls,
         TALER_ARL_USE_PP (coins_recoup_serial_id),
         &recoup_cb,
         &cc)))
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (0 > cc.qs)
    return cc.qs;
  /* process refreshes */
  if (0 >
      (qs = TALER_ARL_edb->select_refreshes_above_serial_id (
         TALER_ARL_edb->cls,
         TALER_ARL_USE_PP (coins_melt_serial_id),
         &refresh_session_cb,
         &cc)))
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (0 > cc.qs)
    return cc.qs;
  /* process deposits */
  if (0 >
      (qs = TALER_ARL_edb->select_coin_deposits_above_serial_id (
         TALER_ARL_edb->cls,
         TALER_ARL_USE_PP (coins_deposit_serial_id),
         &deposit_cb,
         &cc)))
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (0 > cc.qs)
    return cc.qs;
  /* process purse_deposits */
  if (0 >
      (qs = TALER_ARL_edb->select_purse_deposits_above_serial_id (
         TALER_ARL_edb->cls,
         TALER_ARL_USE_PP (coins_purse_deposits_serial_id),
         &purse_deposit_cb,
         &cc)))
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (0 > cc.qs)
    return cc.qs;
  /* sync 'cc' back to disk */
  cc.qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  GNUNET_CONTAINER_multihashmap_iterate (cc.denom_summaries,
                                         &sync_denomination,
                                         &cc);
  GNUNET_CONTAINER_multihashmap_destroy (cc.denom_summaries);
  if (0 > cc.qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == cc.qs);
    return cc.qs;
  }

  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsx)
  {
    qs = TALER_ARL_adb->insert_balance (
      TALER_ARL_adb->cls,
      TALER_ARL_SET_AB (coin_balance_risk),
      TALER_ARL_SET_AB (total_escrowed),
      TALER_ARL_SET_AB (coin_irregular_loss),
      TALER_ARL_SET_AB (coin_melt_fee_revenue),
      TALER_ARL_SET_AB (coin_deposit_fee_revenue),
      TALER_ARL_SET_AB (coin_refund_fee_revenue),
      TALER_ARL_SET_AB (total_recoup_loss),
      TALER_ARL_SET_AB (coins_total_arithmetic_delta_plus),
      TALER_ARL_SET_AB (coins_total_arithmetic_delta_minus),
      TALER_ARL_SET_AB (coins_reported_emergency_risk_by_count),
      TALER_ARL_SET_AB (coins_reported_emergency_risk_by_amount),
      TALER_ARL_SET_AB (coins_emergencies_loss),
      TALER_ARL_SET_AB (total_refresh_hanging),
      NULL);
  }
  else
  {
    GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qsx);
    qs = TALER_ARL_adb->update_balance (
      TALER_ARL_adb->cls,
      TALER_ARL_SET_AB (coin_balance_risk),
      TALER_ARL_SET_AB (total_escrowed),
      TALER_ARL_SET_AB (coin_irregular_loss),
      TALER_ARL_SET_AB (coin_melt_fee_revenue),
      TALER_ARL_SET_AB (coin_deposit_fee_revenue),
      TALER_ARL_SET_AB (coin_refund_fee_revenue),
      TALER_ARL_SET_AB (total_recoup_loss),
      TALER_ARL_SET_AB (coins_total_arithmetic_delta_plus),
      TALER_ARL_SET_AB (coins_total_arithmetic_delta_minus),
      TALER_ARL_SET_AB (coins_reported_emergency_risk_by_count),
      TALER_ARL_SET_AB (coins_reported_emergency_risk_by_amount),
      TALER_ARL_SET_AB (coins_emergencies_loss),
      TALER_ARL_SET_AB (total_refresh_hanging),
      NULL);
  }
  if (0 >= qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsp)
  {
    qs = TALER_ARL_adb->insert_auditor_progress (
      TALER_ARL_adb->cls,
      TALER_ARL_SET_PP (coins_withdraw_serial_id),
      TALER_ARL_SET_PP (coins_deposit_serial_id),
      TALER_ARL_SET_PP (coins_melt_serial_id),
      TALER_ARL_SET_PP (coins_refund_serial_id),
      TALER_ARL_SET_PP (coins_recoup_serial_id),
      TALER_ARL_SET_PP (coins_recoup_refresh_serial_id),
      TALER_ARL_SET_PP (coins_purse_deposits_serial_id),
      TALER_ARL_SET_PP (coins_purse_refunds_serial_id),
      NULL);
  }
  else
  {
    GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qsp);
    qs = TALER_ARL_adb->update_auditor_progress (
      TALER_ARL_adb->cls,
      TALER_ARL_SET_PP (coins_withdraw_serial_id),
      TALER_ARL_SET_PP (coins_deposit_serial_id),
      TALER_ARL_SET_PP (coins_melt_serial_id),
      TALER_ARL_SET_PP (coins_refund_serial_id),
      TALER_ARL_SET_PP (coins_recoup_serial_id),
      TALER_ARL_SET_PP (coins_recoup_refresh_serial_id),
      TALER_ARL_SET_PP (coins_purse_deposits_serial_id),
      TALER_ARL_SET_PP (coins_purse_refunds_serial_id),
      NULL);
  }
  if (0 >= qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Concluded coin audit step at %llu/%llu/%llu/%llu/%llu/%llu/%llu\n",
              (unsigned long long) TALER_ARL_USE_PP (coins_deposit_serial_id),
              (unsigned long long) TALER_ARL_USE_PP (coins_melt_serial_id),
              (unsigned long long) TALER_ARL_USE_PP (coins_refund_serial_id),
              (unsigned long long) TALER_ARL_USE_PP (coins_withdraw_serial_id),
              (unsigned long long) TALER_ARL_USE_PP (
                coins_recoup_refresh_serial_id),
              (unsigned long long) TALER_ARL_USE_PP (
                coins_purse_deposits_serial_id),
              (unsigned long long) TALER_ARL_USE_PP (
                coins_purse_refunds_serial_id));
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
              "Received notification to wake coins helper\n");
  if (GNUNET_OK !=
      TALER_ARL_setup_sessions_and_run (&analyze_coins,
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
              "Launching coins auditor\n");
  if (GNUNET_OK != TALER_ARL_init (c))
  {
    global_ret = EXIT_FAILURE;
    return;
  }
  if (test_mode != 1)
  {
    struct GNUNET_DB_EventHeaderP es = {
      .size = htons (sizeof (es)),
      .type = htons (TALER_DBEVENT_EXCHANGE_AUDITOR_WAKE_HELPER_COINS)
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
      TALER_ARL_setup_sessions_and_run (&analyze_coins,
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
 * The main function to audit operations on coins.
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
    "taler-helper-auditor-coins",
    gettext_noop ("Audit Taler coin processing"),
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


/* end of taler-helper-auditor-coins.c */
