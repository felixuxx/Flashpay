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
 * @file auditor/taler-helper-auditor-aggregation.c
 * @brief audits an exchange's aggregations.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_auditordb_plugin.h"
#include "taler_exchangedb_lib.h"
#include "taler_bank_service.h"
#include "taler_signatures.h"
#include "taler_dbevents.h"
#include "report-lib.h"

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
 * Checkpointing our progress for aggregations.
 */
static TALER_ARL_DEF_PP (aggregation_last_wire_out_serial_id);

/**
 * Total aggregation fees (wire fees) earned.
 */
static TALER_ARL_DEF_AB (aggregation_total_wire_fee_revenue);

/**
 * Total delta between calculated and stored wire out transfers,
 * for positive deltas.
 */
static TALER_ARL_DEF_AB (aggregation_total_wire_out_delta_plus);

/**
 * Total delta between calculated and stored wire out transfers
 * for negative deltas.
 */
static TALER_ARL_DEF_AB (aggregation_total_wire_out_delta_minus);

/**
 * Profits the exchange made by bad amount calculations on coins.
 */
static TALER_ARL_DEF_AB (aggregation_total_coin_delta_plus);

/**
 * Losses the exchange made by bad amount calculations on coins.
 */
static TALER_ARL_DEF_AB (aggregation_total_coin_delta_minus);

/**
 * Profits the exchange made by bad amount calculations.
 */
static TALER_ARL_DEF_AB (aggregation_total_arithmetic_delta_plus);

/**
 * Losses the exchange made by bad amount calculations.
 */
static TALER_ARL_DEF_AB (aggregation_total_arithmetic_delta_minus);

/**
 * Total amount lost by operations for which signatures were invalid.
 */
static TALER_ARL_DEF_AB (aggregation_total_bad_sig_loss);

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
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
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
    enum GNUNET_DB_QueryStatus qs;
    struct TALER_AUDITORDB_AmountArithmeticInconsistency aai = {
      .profitable = profitable,
      .operation = (char *) operation,
      .exchange_amount = *exchange,
      .auditor_amount = *auditor
    };

    qs = TALER_ARL_adb->insert_amount_arithmetic_inconsistency (
      TALER_ARL_adb->cls,
      &aai);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return qs;
    }
  }
  if (0 != profitable)
  {
    target = (1 == profitable)
      ? &TALER_ARL_USE_AB (aggregation_total_arithmetic_delta_plus)
      : &TALER_ARL_USE_AB (aggregation_total_arithmetic_delta_minus);
    TALER_ARL_amount_add (target,
                          target,
                          &delta);
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Report a (serious) inconsistency in the exchange's database with
 * respect to calculations involving amounts of a coin.
 *
 * @param operation what operation had the inconsistency
 * @param coin_pub affected coin
 * @param exchange amount calculated by exchange
 * @param auditor amount calculated by auditor
 * @param profitable 1 if @a exchange being larger than @a auditor is
 *           profitable for the exchange for this operation,
 *           -1 if @a exchange being smaller than @a auditor is
 *           profitable for the exchange, and 0 if it is unclear
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
report_coin_arithmetic_inconsistency (
  const char *operation,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
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
    enum GNUNET_DB_QueryStatus qs;
    struct TALER_AUDITORDB_CoinInconsistency ci = {
      .operation = (char *) operation,
      .auditor_amount = *auditor,
      .exchange_amount = *exchange,
      .profitable = profitable,
      .coin_pub = coin_pub->eddsa_pub
    };

    qs = TALER_ARL_adb->insert_coin_inconsistency (
      TALER_ARL_adb->cls,
      &ci);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return qs;
    }
  }
  if (0 != profitable)
  {
    target = (1 == profitable)
      ? &TALER_ARL_USE_AB (aggregation_total_coin_delta_plus)
      : &TALER_ARL_USE_AB (aggregation_total_coin_delta_minus);
    TALER_ARL_amount_add (target,
                          target,
                          &delta);
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Report a (serious) inconsistency in the exchange's database.
 *
 * @param table affected table
 * @param rowid affected row, 0 if row is missing
 * @param diagnostic message explaining the problem
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
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
    return qs;
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/* *********************** Analyze aggregations ******************** */
/* This logic checks that the aggregator did the right thing
   paying each merchant what they were due (and on time). */


/**
 * Information about wire fees charged by the exchange.
 */
struct WireFeeInfo
{

  /**
   * Kept in a DLL.
   */
  struct WireFeeInfo *next;

  /**
   * Kept in a DLL.
   */
  struct WireFeeInfo *prev;

  /**
   * When does the fee go into effect (inclusive).
   */
  struct GNUNET_TIME_Timestamp start_date;

  /**
   * When does the fee stop being in effect (exclusive).
   */
  struct GNUNET_TIME_Timestamp end_date;

  /**
   * How high are the wire fees.
   */
  struct TALER_WireFeeSet fees;

};


/**
 * Closure for callbacks during #analyze_merchants().
 */
struct AggregationContext
{

  /**
   * DLL of wire fees charged by the exchange.
   */
  struct WireFeeInfo *fee_head;

  /**
   * DLL of wire fees charged by the exchange.
   */
  struct WireFeeInfo *fee_tail;

  /**
   * Final result status.
   */
  enum GNUNET_DB_QueryStatus qs;
};


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
   * Target account details of the receiver.
   */
  const char *payto_uri;

  /**
   * Execution time of the wire transfer.
   */
  struct GNUNET_TIME_Timestamp date;

  /**
   * Database transaction status.
   */
  enum GNUNET_DB_QueryStatus qs;

};


/**
 * Check coin's transaction history for plausibility.  Does NOT check
 * the signatures (those are checked independently), but does calculate
 * the amounts for the aggregation table and checks that the total
 * claimed coin value is within the value of the coin's denomination.
 *
 * @param coin_pub public key of the coin (for reporting)
 * @param h_contract_terms hash of the proposal for which we calculate the amount
 * @param merchant_pub public key of the merchant (who is allowed to issue refunds)
 * @param issue denomination information about the coin
 * @param tl_head head of transaction history to verify
 * @param[out] merchant_gain amount the coin contributes to the wire transfer to the merchant
 * @param[out] deposit_gain amount the coin contributes excluding refunds
 * @return database transaction status
 */
static enum GNUNET_DB_QueryStatus
check_transaction_history_for_deposit (
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue,
  const struct TALER_EXCHANGEDB_TransactionList *tl_head,
  struct TALER_Amount *merchant_gain,
  struct TALER_Amount *deposit_gain)
{
  struct TALER_Amount expenditures;
  struct TALER_Amount refunds;
  struct TALER_Amount spent;
  struct TALER_Amount *deposited = NULL;
  struct TALER_Amount merchant_loss;
  const struct TALER_Amount *deposit_fee;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Checking transaction history of coin %s\n",
              TALER_B2S (coin_pub));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &expenditures));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &refunds));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        merchant_gain));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TALER_ARL_currency,
                                        &merchant_loss));
  /* Go over transaction history to compute totals; note that we do not bother
     to reconstruct the order of the events, so instead of subtracting we
     compute positive (deposit, melt) and negative (refund) values separately
     here, and then subtract the negative from the positive at the end (after
     the loops). */
  deposit_fee = NULL;
  for (const struct TALER_EXCHANGEDB_TransactionList *tl = tl_head;
       NULL != tl;
       tl = tl->next)
  {
    const struct TALER_Amount *fee_claimed;

    switch (tl->type)
    {
    case TALER_EXCHANGEDB_TT_DEPOSIT:
      /* check wire and h_wire are consistent */
      if (NULL != deposited)
      {
        struct TALER_AUDITORDB_RowInconsistency ri = {
          .row_id = tl->serial_id,
          .diagnostic =
            "multiple deposits of the same coin into the same contract detected",
          .row_table = "deposits"
        };

        qs = TALER_ARL_adb->insert_row_inconsistency (
          TALER_ARL_adb->cls,
          &ri);

        if (qs < 0)
        {
          GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
          // FIXME: error handling
        }
      }
      deposited = &tl->details.deposit->amount_with_fee;       /* according to exchange*/
      fee_claimed = &tl->details.deposit->deposit_fee;       /* Fee according to exchange DB */
      TALER_ARL_amount_add (&expenditures,
                            &expenditures,
                            deposited);
      /* Check if this deposit is within the remit of the aggregation
         we are investigating, if so, include it in the totals. */
      if ((0 == GNUNET_memcmp (merchant_pub,
                               &tl->details.deposit->merchant_pub)) &&
          (0 == GNUNET_memcmp (h_contract_terms,
                               &tl->details.deposit->h_contract_terms)))
      {
        struct TALER_Amount amount_without_fee;

        TALER_ARL_amount_subtract (&amount_without_fee,
                                   deposited,
                                   fee_claimed);
        TALER_ARL_amount_add (merchant_gain,
                              merchant_gain,
                              &amount_without_fee);
        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "Detected applicable deposit of %s\n",
                    TALER_amount2s (&amount_without_fee));
        deposit_fee = fee_claimed;       /* We had a deposit, remember the fee, we may need it */
      }
      /* Check that the fees given in the transaction list and in dki match */
      if (0 !=
          TALER_amount_cmp (&issue->fees.deposit,
                            fee_claimed))
      {
        /* Disagreement in fee structure between auditor and exchange DB! */
        qs = report_amount_arithmetic_inconsistency ("deposit fee",
                                                     0,
                                                     fee_claimed,
                                                     &issue->fees.deposit,
                                                     1);
        if (0 > qs)
          return qs;
      }
      break;
    case TALER_EXCHANGEDB_TT_MELT:
      {
        const struct TALER_Amount *amount_with_fee;

        amount_with_fee = &tl->details.melt->amount_with_fee;
        fee_claimed = &tl->details.melt->melt_fee;
        TALER_ARL_amount_add (&expenditures,
                              &expenditures,
                              amount_with_fee);
        /* Check that the fees given in the transaction list and in dki match */
        if (0 !=
            TALER_amount_cmp (&issue->fees.refresh,
                              fee_claimed))
        {
          /* Disagreement in fee structure between exchange and auditor */
          qs = report_amount_arithmetic_inconsistency ("melt fee",
                                                       0,
                                                       fee_claimed,
                                                       &issue->fees.refresh,
                                                       1);
          if (0 > qs)
            return qs;
        }
        break;
      }
    case TALER_EXCHANGEDB_TT_REFUND:
      {
        const struct TALER_Amount *amount_with_fee;

        amount_with_fee = &tl->details.refund->refund_amount;
        fee_claimed = &tl->details.refund->refund_fee;
        TALER_ARL_amount_add (&refunds,
                              &refunds,
                              amount_with_fee);
        TALER_ARL_amount_add (&expenditures,
                              &expenditures,
                              fee_claimed);
        /* Check if this refund is within the remit of the aggregation
           we are investigating, if so, include it in the totals. */
        if ((0 == GNUNET_memcmp (merchant_pub,
                                 &tl->details.refund->merchant_pub)) &&
            (0 == GNUNET_memcmp (h_contract_terms,
                                 &tl->details.refund->h_contract_terms)))
        {
          GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                      "Detected applicable refund of %s\n",
                      TALER_amount2s (amount_with_fee));
          TALER_ARL_amount_add (&merchant_loss,
                                &merchant_loss,
                                amount_with_fee);
        }
        /* Check that the fees given in the transaction list and in dki match */
        if (0 !=
            TALER_amount_cmp (&issue->fees.refund,
                              fee_claimed))
        {
          /* Disagreement in fee structure between exchange and auditor! */
          qs = report_amount_arithmetic_inconsistency ("refund fee",
                                                       0,
                                                       fee_claimed,
                                                       &issue->fees.refund,
                                                       1);
          if (0 > qs)
            return qs;
        }
        break;
      }
    case TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP:
      {
        const struct TALER_Amount *amount_with_fee;

        amount_with_fee = &tl->details.old_coin_recoup->value;
        /* We count recoups of refreshed coins like refunds for the dirty old
           coin, as they equivalently _increase_ the remaining value on the
           _old_ coin */
        TALER_ARL_amount_add (&refunds,
                              &refunds,
                              amount_with_fee);
        break;
      }
    case TALER_EXCHANGEDB_TT_RECOUP:
      {
        const struct TALER_Amount *amount_with_fee;

        /* We count recoups of the coin as expenditures, as it
           equivalently decreases the remaining value of the recouped coin. */
        amount_with_fee = &tl->details.recoup->value;
        TALER_ARL_amount_add (&expenditures,
                              &expenditures,
                              amount_with_fee);
        break;
      }
    case TALER_EXCHANGEDB_TT_RECOUP_REFRESH:
      {
        const struct TALER_Amount *amount_with_fee;

        /* We count recoups of the coin as expenditures, as it
           equivalently decreases the remaining value of the recouped coin. */
        amount_with_fee = &tl->details.recoup_refresh->value;
        TALER_ARL_amount_add (&expenditures,
                              &expenditures,
                              amount_with_fee);
        break;
      }
    case TALER_EXCHANGEDB_TT_PURSE_DEPOSIT:
      {
        const struct TALER_Amount *amount_with_fee;

        amount_with_fee = &tl->details.purse_deposit->amount;
        if (! tl->details.purse_deposit->refunded)
          TALER_ARL_amount_add (&expenditures,
                                &expenditures,
                                amount_with_fee);
        break;
      }

    case TALER_EXCHANGEDB_TT_PURSE_REFUND:
      {
        const struct TALER_Amount *amount_with_fee;

        amount_with_fee = &tl->details.purse_refund->refund_amount;
        fee_claimed = &tl->details.purse_refund->refund_fee;
        TALER_ARL_amount_add (&refunds,
                              &refunds,
                              amount_with_fee);
        TALER_ARL_amount_add (&expenditures,
                              &expenditures,
                              fee_claimed);
        /* Check that the fees given in the transaction list and in dki match */
        if (0 !=
            TALER_amount_cmp (&issue->fees.refund,
                              fee_claimed))
        {
          /* Disagreement in fee structure between exchange and auditor! */
          qs = report_amount_arithmetic_inconsistency ("refund fee",
                                                       0,
                                                       fee_claimed,
                                                       &issue->fees.refund,
                                                       1);
          if (0 > qs)
            return qs;
        }
        break;
      }

    case TALER_EXCHANGEDB_TT_RESERVE_OPEN:
      {
        const struct TALER_Amount *amount_with_fee;

        amount_with_fee = &tl->details.reserve_open->coin_contribution;
        TALER_ARL_amount_add (&expenditures,
                              &expenditures,
                              amount_with_fee);
        break;
      }
    } /* switch (tl->type) */
  } /* for 'tl' */

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Deposits for this aggregation (after fees) are %s\n",
              TALER_amount2s (merchant_gain));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Aggregation loss due to refunds is %s\n",
              TALER_amount2s (&merchant_loss));
  *deposit_gain = *merchant_gain;
  if ((NULL != deposited) &&
      (NULL != deposit_fee) &&
      (0 == TALER_amount_cmp (&refunds,
                              deposited)))
  {
    /* We had a /deposit operation AND /refund operations adding up to the
       total deposited value including deposit fee. Thus, we should not
       subtract the /deposit fee from the merchant gain (as it was also
       refunded). */
    TALER_ARL_amount_add (merchant_gain,
                          merchant_gain,
                          deposit_fee);
  }
  {
    struct TALER_Amount final_gain;

    if (TALER_ARL_SR_INVALID_NEGATIVE ==
        TALER_ARL_amount_subtract_neg (&final_gain,
                                       merchant_gain,
                                       &merchant_loss))
    {
      /* refunds above deposits? Bad! */
      qs = report_coin_arithmetic_inconsistency ("refund (merchant)",
                                                 coin_pub,
                                                 merchant_gain,
                                                 &merchant_loss,
                                                 1);
      if (0 > qs)
        return qs;
      /* For the overall aggregation, we should not count this
         as a NEGATIVE contribution as that is not allowed; so
         let's count it as zero as that's the best we can do. */
      GNUNET_assert (GNUNET_OK ==
                     TALER_amount_set_zero (TALER_ARL_currency,
                                            merchant_gain));
    }
    else
    {
      *merchant_gain = final_gain;
    }
  }


  /* Calculate total balance change, i.e. expenditures (recoup, deposit, refresh)
     minus refunds (refunds, recoup-to-old) */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Subtracting refunds of %s from coin value loss\n",
              TALER_amount2s (&refunds));
  if (TALER_ARL_SR_INVALID_NEGATIVE ==
      TALER_ARL_amount_subtract_neg (&spent,
                                     &expenditures,
                                     &refunds))
  {
    /* refunds above expenditures? Bad! */
    qs = report_coin_arithmetic_inconsistency ("refund (balance)",
                                               coin_pub,
                                               &expenditures,
                                               &refunds,
                                               1);
    if (0 > qs)
      return qs;
  }
  else
  {
    /* Now check that 'spent' is less or equal than the total coin value */
    if (1 == TALER_amount_cmp (&spent,
                               &issue->value))
    {
      /* spent > value */
      qs = report_coin_arithmetic_inconsistency ("spend",
                                                 coin_pub,
                                                 &spent,
                                                 &issue->value,
                                                 -1);
      if (0 > qs)
        return qs;
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Final merchant gain after refunds is %s\n",
              TALER_amount2s (deposit_gain));
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Coin %s contributes %s to contract %s\n",
              TALER_B2S (coin_pub),
              TALER_amount2s (merchant_gain),
              GNUNET_h2s (&h_contract_terms->hash));
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Function called with the results of the lookup of the
 * transaction data associated with a wire transfer identifier.
 *
 * @param[in,out] cls a `struct WireCheckContext`
 * @param rowid which row in the table is the information from (for diagnostics)
 * @param merchant_pub public key of the merchant (should be same for all callbacks with the same @e cls)
 * @param account_pay_uri where did we transfer the funds?
 * @param h_payto hash over @a account_payto_uri as it is in the DB
 * @param exec_time execution time of the wire transfer (should be same for all callbacks with the same @e cls)
 * @param h_contract_terms which proposal was this payment about
 * @param denom_pub denomination of @a coin_pub
 * @param coin_pub which public key was this payment about
 * @param coin_value amount contributed by this coin in total (with fee),
 *                   but excluding refunds by this coin
 * @param deposit_fee applicable deposit fee for this coin, actual
 *        fees charged may differ if coin was refunded
 */
static void
wire_transfer_information_cb (
  void *cls,
  uint64_t rowid,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const char *account_pay_uri,
  const struct TALER_PaytoHashP *h_payto,
  struct GNUNET_TIME_Timestamp exec_time,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_Amount *coin_value,
  const struct TALER_Amount *deposit_fee)
{
  struct WireCheckContext *wcc = cls;
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue;
  struct TALER_Amount computed_value;
  struct TALER_Amount total_deposit_without_refunds;
  struct TALER_EXCHANGEDB_TransactionList *tl;
  struct TALER_CoinPublicInfo coin;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_PaytoHashP hpt;
  uint64_t etag_out;

  if (0 > wcc->qs)
    return;
  TALER_payto_hash (account_pay_uri,
                    &hpt);
  if (0 !=
      GNUNET_memcmp (&hpt,
                     h_payto))
  {
    qs = report_row_inconsistency ("wire_targets",
                                   rowid,
                                   "h-payto does not match payto URI");
    if (0 > qs)
    {
      wcc->qs = qs;
      return;
    }
  }
  /* Obtain coin's transaction history */
  /* TODO: could use 'start' mechanism to only fetch transactions
     we did not yet process, instead of going over them
     again and again.*/

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
  if (0 > qs)
  {
    wcc->qs = qs;
    TALER_ARL_edb->free_coin_transaction_list (TALER_ARL_edb->cls,
                                               tl);
    return;
  }
  if (NULL == tl)
  {
    qs = report_row_inconsistency ("aggregation",
                                   rowid,
                                   "no transaction history for coin claimed in aggregation");
    if (0 > qs)
      wcc->qs = qs;
    return;
  }
  qs = TALER_ARL_edb->get_known_coin (TALER_ARL_edb->cls,
                                      coin_pub,
                                      &coin);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    wcc->qs = qs;
    return;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    /* this should be a foreign key violation at this point! */
    qs = report_row_inconsistency ("aggregation",
                                   rowid,
                                   "could not get coin details for coin claimed in aggregation");
    if (0 > qs)
      wcc->qs = qs;
    TALER_ARL_edb->free_coin_transaction_list (TALER_ARL_edb->cls,
                                               tl);
    return;
  }
  qs = TALER_ARL_get_denomination_info_by_hash (&coin.denom_pub_hash,
                                                &issue);
  if (0 > qs)
  {
    wcc->qs = qs;
    TALER_denom_sig_free (&coin.denom_sig);
    TALER_ARL_edb->free_coin_transaction_list (TALER_ARL_edb->cls,
                                               tl);
    return;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    TALER_denom_sig_free (&coin.denom_sig);
    TALER_ARL_edb->free_coin_transaction_list (TALER_ARL_edb->cls,
                                               tl);
    qs = report_row_inconsistency ("aggregation",
                                   rowid,
                                   "could not find denomination key for coin claimed in aggregation");
    if (0 > qs)
      wcc->qs = qs;
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Testing coin `%s' for validity\n",
              TALER_B2S (&coin.coin_pub));
  if (GNUNET_OK !=
      TALER_test_coin_valid (&coin,
                             denom_pub))
  {
    struct TALER_AUDITORDB_BadSigLosses bsl = {
      .row_id = rowid,
      .operation = "wire",
      .loss = *coin_value,
      .operation_specific_pub = coin.coin_pub.eddsa_pub
    };

    qs = TALER_ARL_adb->insert_bad_sig_losses (
      TALER_ARL_adb->cls,
      &bsl);
    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      wcc->qs = qs;
      TALER_denom_sig_free (&coin.denom_sig);
      TALER_ARL_edb->free_coin_transaction_list (TALER_ARL_edb->cls,
                                                 tl);
      return;
    }
    TALER_ARL_amount_add (&TALER_ARL_USE_AB (aggregation_total_bad_sig_loss),
                          &TALER_ARL_USE_AB (aggregation_total_bad_sig_loss),
                          coin_value);
    qs = report_row_inconsistency ("deposit",
                                   rowid,
                                   "coin denomination signature invalid");
    if (0 > qs)
    {
      wcc->qs = qs;
      TALER_denom_sig_free (&coin.denom_sig);
      TALER_ARL_edb->free_coin_transaction_list (TALER_ARL_edb->cls,
                                                 tl);
      return;
    }
  }
  TALER_denom_sig_free (&coin.denom_sig);
  GNUNET_assert (NULL != issue); /* mostly to help static analysis */
  /* Check transaction history to see if it supports aggregate
     valuation */
  qs = check_transaction_history_for_deposit (
    coin_pub,
    h_contract_terms,
    merchant_pub,
    issue,
    tl,
    &computed_value,
    &total_deposit_without_refunds);
  if (0 > qs)
  {
    TALER_ARL_edb->free_coin_transaction_list (TALER_ARL_edb->cls,
                                               tl);
    wcc->qs = qs;
    return;
  }
  TALER_ARL_edb->free_coin_transaction_list (TALER_ARL_edb->cls,
                                             tl);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Coin contributes %s to aggregate (deposits after fees and refunds)\n",
              TALER_amount2s (&computed_value));
  {
    struct TALER_Amount coin_value_without_fee;

    if (TALER_ARL_SR_INVALID_NEGATIVE ==
        TALER_ARL_amount_subtract_neg (&coin_value_without_fee,
                                       coin_value,
                                       deposit_fee))
    {
      qs = report_amount_arithmetic_inconsistency (
        "aggregation (fee structure)",
        rowid,
        coin_value,
        deposit_fee,
        -1);
      if (0 > qs)
      {
        wcc->qs = qs;
        return;
      }
    }
    if (0 !=
        TALER_amount_cmp (&total_deposit_without_refunds,
                          &coin_value_without_fee))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Expected coin contribution of %s to aggregate\n",
                  TALER_amount2s (&coin_value_without_fee));
      qs = report_amount_arithmetic_inconsistency (
        "aggregation (contribution)",
        rowid,
        &coin_value_without_fee,
        &total_deposit_without_refunds,
        -1);
      if (0 > qs)
      {
        wcc->qs = qs;
        return;
      }
    }
  }
  /* Check other details of wire transfer match */
  if (0 != strcmp (account_pay_uri,
                   wcc->payto_uri))
  {
    qs = report_row_inconsistency ("aggregation",
                                   rowid,
                                   "target of outgoing wire transfer do not match hash of wire from deposit");
    if (0 > qs)
    {
      wcc->qs = qs;
      return;
    }
  }
  if (GNUNET_TIME_timestamp_cmp (exec_time,
                                 !=,
                                 wcc->date))
  {
    /* This should be impossible from database constraints */
    GNUNET_break (0);
    qs = report_row_inconsistency ("aggregation",
                                   rowid,
                                   "date given in aggregate does not match wire transfer date");
    if (0 > qs)
    {
      wcc->qs = qs;
      return;
    }
  }

  /* Add coin's contribution to total aggregate value */
  {
    struct TALER_Amount res;

    TALER_ARL_amount_add (&res,
                          &wcc->total_deposits,
                          &computed_value);
    wcc->total_deposits = res;
  }
}


/**
 * Lookup the wire fee that the exchange charges at @a timestamp.
 *
 * @param ac context for caching the result
 * @param method method of the wire plugin
 * @param timestamp time for which we need the fee
 * @return NULL on error (fee unknown)
 */
static const struct TALER_Amount *
get_wire_fee (struct AggregationContext *ac,
              const char *method,
              struct GNUNET_TIME_Timestamp timestamp)
{
  struct WireFeeInfo *wfi;
  struct WireFeeInfo *pos;
  struct TALER_MasterSignatureP master_sig;
  enum GNUNET_DB_QueryStatus qs;

  /* Check if fee is already loaded in cache */
  for (pos = ac->fee_head; NULL != pos; pos = pos->next)
  {
    if (GNUNET_TIME_timestamp_cmp (pos->start_date,
                                   <=,
                                   timestamp) &&
        GNUNET_TIME_timestamp_cmp (pos->end_date,
                                   >,
                                   timestamp))
      return &pos->fees.wire;
    if (GNUNET_TIME_timestamp_cmp (pos->start_date,
                                   >,
                                   timestamp))
      break;
  }

  /* Lookup fee in exchange database */
  wfi = GNUNET_new (struct WireFeeInfo);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      TALER_ARL_edb->get_wire_fee (TALER_ARL_edb->cls,
                                   method,
                                   timestamp,
                                   &wfi->start_date,
                                   &wfi->end_date,
                                   &wfi->fees,
                                   &master_sig))
  {
    GNUNET_break (0);
    GNUNET_free (wfi);
    return NULL;
  }

  /* Check signature. (This is not terribly meaningful as the exchange can
     easily make this one up, but it means that we have proof that the master
     key was used for inconsistent wire fees if a merchant complains.) */
  {
    if (GNUNET_OK !=
        TALER_exchange_offline_wire_fee_verify (
          method,
          wfi->start_date,
          wfi->end_date,
          &wfi->fees,
          &TALER_ARL_master_pub,
          &master_sig))
    {
      report_row_inconsistency ("wire-fee",
                                timestamp.abs_time.abs_value_us,
                                "wire fee signature invalid at given time");
    }
  }

  /* Established fee, keep in sorted list */
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Wire fee is %s starting at %s\n",
              TALER_amount2s (&wfi->fees.wire),
              GNUNET_TIME_timestamp2s (wfi->start_date));
  if ((NULL == pos) ||
      (NULL == pos->prev))
    GNUNET_CONTAINER_DLL_insert (ac->fee_head,
                                 ac->fee_tail,
                                 wfi);
  else
    GNUNET_CONTAINER_DLL_insert_after (ac->fee_head,
                                       ac->fee_tail,
                                       pos->prev,
                                       wfi);
  /* Check non-overlaping fee invariant */
  if ((NULL != wfi->prev) &&
      GNUNET_TIME_timestamp_cmp (wfi->prev->end_date,
                                 >,
                                 wfi->start_date))
  {
    struct TALER_AUDITORDB_FeeTimeInconsistency ftib = {
      .diagnostic = "start date before previous end date",
      .time = wfi->start_date.abs_time,
      .type = (char *) method
    };

    qs = TALER_ARL_adb->insert_fee_time_inconsistency (
      TALER_ARL_adb->cls,
      &ftib);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      ac->qs = qs;
      return NULL;
    }
  }
  if ((NULL != wfi->next) &&
      GNUNET_TIME_timestamp_cmp (wfi->next->start_date,
                                 >=,
                                 wfi->end_date))
  {
    struct TALER_AUDITORDB_FeeTimeInconsistency ftia = {
      .diagnostic = "end date date after next start date",
      .time = wfi->end_date.abs_time,
      .type = (char *) method
    };

    qs = TALER_ARL_adb->insert_fee_time_inconsistency (
      TALER_ARL_adb->cls,
      &ftia);

    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      ac->qs = qs;
      return NULL;
    }
  }
  return &wfi->fees.wire;
}


/**
 * Check that a wire transfer made by the exchange is valid
 * (has matching deposits).
 *
 * @param cls a `struct AggregationContext`
 * @param rowid identifier of the respective row in the database
 * @param date timestamp of the wire transfer (roughly)
 * @param wtid wire transfer subject
 * @param payto_uri bank account details of the receiver
 * @param amount amount that was wired
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to stop iteration
 */
static enum GNUNET_GenericReturnValue
check_wire_out_cb (void *cls,
                   uint64_t rowid,
                   struct GNUNET_TIME_Timestamp date,
                   const struct TALER_WireTransferIdentifierRawP *wtid,
                   const char *payto_uri,
                   const struct TALER_Amount *amount)
{
  struct AggregationContext *ac = cls;
  struct WireCheckContext wcc;
  struct TALER_Amount final_amount;
  struct TALER_Amount exchange_gain;
  enum GNUNET_DB_QueryStatus qs;
  char *method;

  /* should be monotonically increasing */
  GNUNET_assert (rowid >=
                 TALER_ARL_USE_PP (aggregation_last_wire_out_serial_id));
  TALER_ARL_USE_PP (aggregation_last_wire_out_serial_id) = rowid + 1;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Checking wire transfer %s over %s performed on %s\n",
              TALER_B2S (wtid),
              TALER_amount2s (amount),
              GNUNET_TIME_timestamp2s (date));
  if (NULL == (method = TALER_payto_get_method (payto_uri)))
  {
    qs = report_row_inconsistency ("wire_out",
                                   rowid,
                                   "specified wire address lacks method");
    if (0 > qs)
      ac->qs = qs;
    return GNUNET_OK;
  }

  wcc.ac = ac;
  wcc.qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  wcc.date = date;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (amount->currency,
                                        &wcc.total_deposits));
  wcc.payto_uri = payto_uri;
  qs = TALER_ARL_edb->lookup_wire_transfer (TALER_ARL_edb->cls,
                                            wtid,
                                            &wire_transfer_information_cb,
                                            &wcc);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    ac->qs = qs;
    GNUNET_free (method);
    return GNUNET_SYSERR;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != wcc.qs)
  {
    /* Note: detailed information was already logged
       in #wire_transfer_information_cb, so here we
       only log for debugging */
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Inconsistency for wire_out %llu (WTID %s) detected\n",
                (unsigned long long) rowid,
                TALER_B2S (wtid));
  }


  /* Subtract aggregation fee from total (if possible) */
  {
    const struct TALER_Amount *wire_fee;

    wire_fee = get_wire_fee (ac,
                             method,
                             date);
    if (0 > ac->qs)
    {
      GNUNET_free (method);
      return GNUNET_SYSERR;
    }
    if (NULL == wire_fee)
    {
      report_row_inconsistency ("wire-fee",
                                date.abs_time.abs_value_us,
                                "wire fee unavailable for given time");
      /* If fee is unknown, we just assume the fee is zero */
      final_amount = wcc.total_deposits;
    }
    else if (TALER_ARL_SR_INVALID_NEGATIVE ==
             TALER_ARL_amount_subtract_neg (&final_amount,
                                            &wcc.total_deposits,
                                            wire_fee))
    {
      qs = report_amount_arithmetic_inconsistency (
        "wire out (fee structure)",
        rowid,
        &wcc.total_deposits,
        wire_fee,
        -1);
      /* If fee arithmetic fails, we just assume the fee is zero */
      if (0 > qs)
      {
        ac->qs = qs;
        GNUNET_free (method);
        return GNUNET_SYSERR;
      }
      final_amount = wcc.total_deposits;
    }
  }
  GNUNET_free (method);

  /* Round down to amount supported by wire method */
  GNUNET_break (GNUNET_SYSERR !=
                TALER_amount_round_down (&final_amount,
                                         &TALER_ARL_currency_round_unit));

  /* Calculate the exchange's gain as the fees plus rounding differences! */
  TALER_ARL_amount_subtract (&exchange_gain,
                             &wcc.total_deposits,
                             &final_amount);

  /* Sum up aggregation fees (we simply include the rounding gains) */
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (aggregation_total_wire_fee_revenue),
                        &TALER_ARL_USE_AB (aggregation_total_wire_fee_revenue),
                        &exchange_gain);

  /* Check that calculated amount matches actual amount */
  if (0 != TALER_amount_cmp (amount,
                             &final_amount))
  {
    struct TALER_Amount delta;

    if (0 < TALER_amount_cmp (amount,
                              &final_amount))
    {
      /* amount > final_amount */
      TALER_ARL_amount_subtract (&delta,
                                 amount,
                                 &final_amount);
      TALER_ARL_amount_add (&TALER_ARL_USE_AB (
                              aggregation_total_wire_out_delta_plus),
                            &TALER_ARL_USE_AB (
                              aggregation_total_wire_out_delta_plus),
                            &delta);
    }
    else
    {
      /* amount < final_amount */
      TALER_ARL_amount_subtract (&delta,
                                 &final_amount,
                                 amount);
      TALER_ARL_amount_add (&TALER_ARL_USE_AB (
                              aggregation_total_wire_out_delta_minus),
                            &TALER_ARL_USE_AB (
                              aggregation_total_wire_out_delta_minus),
                            &delta);
    }

    {
      struct TALER_AUDITORDB_WireOutInconsistency woi = {
        .destination_account = (char *) payto_uri,
        .diagnostic = "aggregated amount does not match expectations",
        .wire_out_row_id = rowid,
        .expected = final_amount,
        .claimed = *amount
      };

      qs = TALER_ARL_adb->insert_wire_out_inconsistency (
        TALER_ARL_adb->cls,
        &woi);

      if (qs < 0)
      {
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        ac->qs = qs;
        return GNUNET_SYSERR;
      }
    }
    return GNUNET_OK;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Aggregation unit %s is OK\n",
              TALER_B2S (wtid));
  return GNUNET_OK;
}


/**
 * Analyze the exchange aggregator's payment processing.
 *
 * @param cls closure
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
analyze_aggregations (void *cls)
{
  struct AggregationContext ac;
  struct WireFeeInfo *wfi;
  enum GNUNET_DB_QueryStatus qs;

  (void) cls;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Analyzing aggregations\n");
  qs = TALER_ARL_adb->get_auditor_progress (
    TALER_ARL_adb->cls,
    TALER_ARL_GET_PP (aggregation_last_wire_out_serial_id),
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
                "Resuming aggregation audit at %llu\n",
                (unsigned long long) TALER_ARL_USE_PP (
                  aggregation_last_wire_out_serial_id));
  }

  memset (&ac,
          0,
          sizeof (ac));
  qs = TALER_ARL_adb->get_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_GET_AB (aggregation_total_wire_fee_revenue),
    TALER_ARL_GET_AB (aggregation_total_arithmetic_delta_plus),
    TALER_ARL_GET_AB (aggregation_total_arithmetic_delta_minus),
    TALER_ARL_GET_AB (aggregation_total_bad_sig_loss),
    TALER_ARL_GET_AB (aggregation_total_wire_out_delta_plus),
    TALER_ARL_GET_AB (aggregation_total_wire_out_delta_minus),
    TALER_ARL_GET_AB (aggregation_total_coin_delta_plus),
    NULL);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  ac.qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  qs = TALER_ARL_edb->select_wire_out_above_serial_id (
    TALER_ARL_edb->cls,
    TALER_ARL_USE_PP (aggregation_last_wire_out_serial_id),
    &check_wire_out_cb,
    &ac);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    ac.qs = qs;
  }
  while (NULL != (wfi = ac.fee_head))
  {
    GNUNET_CONTAINER_DLL_remove (ac.fee_head,
                                 ac.fee_tail,
                                 wfi);
    GNUNET_free (wfi);
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    /* there were no wire out entries to be looked at, we are done */
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != ac.qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == ac.qs);
    return ac.qs;
  }
  qs = TALER_ARL_adb->insert_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_AB (aggregation_total_wire_fee_revenue),
    TALER_ARL_SET_AB (aggregation_total_arithmetic_delta_plus),
    TALER_ARL_SET_AB (aggregation_total_arithmetic_delta_minus),
    TALER_ARL_SET_AB (aggregation_total_bad_sig_loss),
    TALER_ARL_SET_AB (aggregation_total_wire_out_delta_plus),
    TALER_ARL_SET_AB (aggregation_total_wire_out_delta_minus),
    TALER_ARL_SET_AB (aggregation_total_coin_delta_plus),
    NULL);
  if (0 > qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  qs = TALER_ARL_adb->update_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_AB (aggregation_total_wire_fee_revenue),
    TALER_ARL_SET_AB (aggregation_total_arithmetic_delta_plus),
    TALER_ARL_SET_AB (aggregation_total_arithmetic_delta_minus),
    TALER_ARL_SET_AB (aggregation_total_bad_sig_loss),
    TALER_ARL_SET_AB (aggregation_total_wire_out_delta_plus),
    TALER_ARL_SET_AB (aggregation_total_wire_out_delta_minus),
    TALER_ARL_SET_AB (aggregation_total_coin_delta_plus),
    NULL);
  if (0 > qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  qs = TALER_ARL_adb->insert_auditor_progress (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_PP (aggregation_last_wire_out_serial_id),
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
    TALER_ARL_SET_PP (aggregation_last_wire_out_serial_id),
    NULL);
  if (0 > qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Concluded aggregation audit step at %llu\n",
              (unsigned long long) TALER_ARL_USE_PP (
                aggregation_last_wire_out_serial_id));

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
              "Received notification to wake aggregation helper\n");
  if (GNUNET_OK !=
      TALER_ARL_setup_sessions_and_run (&analyze_aggregations,
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
              "Launching aggregation auditor\n");
  if (GNUNET_OK !=
      TALER_ARL_init (c))
  {
    global_ret = EXIT_FAILURE;
    return;
  }

  if (test_mode != 1)
  {
    struct GNUNET_DB_EventHeaderP es = {
      .size = htons (sizeof (es)),
      .type = htons (TALER_DBEVENT_EXCHANGE_AUDITOR_WAKE_HELPER_AGGREGATION)
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
      TALER_ARL_setup_sessions_and_run (&analyze_aggregations,
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
 * The main function to audit the exchange's aggregation processing.
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
    "taler-helper-auditor-aggregation",
    gettext_noop ("Audit Taler exchange aggregation activity"),
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


/* end of taler-helper-auditor-aggregation.c */
