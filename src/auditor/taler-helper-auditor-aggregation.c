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
 * @file auditor/taler-helper-auditor-aggregation.c
 * @brief audits an exchange's aggregations.
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
 * Return value from main().
 */
static int global_ret;

/**
 * Checkpointing our progress for aggregations.
 */
static struct TALER_AUDITORDB_ProgressPointAggregation ppa;

/**
 * Checkpointing our progress for aggregations.
 */
static struct TALER_AUDITORDB_ProgressPointAggregation ppa_start;

/**
 * Array of reports about row inconsitencies.
 */
static json_t *report_row_inconsistencies;

/**
 * Array of reports about irregular wire out entries.
 */
static json_t *report_wire_out_inconsistencies;

/**
 * Total delta between calculated and stored wire out transfers,
 * for positive deltas.
 */
static struct TALER_Amount total_wire_out_delta_plus;

/**
 * Total delta between calculated and stored wire out transfers
 * for negative deltas.
 */
static struct TALER_Amount total_wire_out_delta_minus;

/**
 * Array of reports about inconsistencies about coins.
 */
static json_t *report_coin_inconsistencies;

/**
 * Profits the exchange made by bad amount calculations on coins.
 */
static struct TALER_Amount total_coin_delta_plus;

/**
 * Losses the exchange made by bad amount calculations on coins.
 */
static struct TALER_Amount total_coin_delta_minus;

/**
 * Report about amount calculation differences (causing profit
 * or loss at the exchange).
 */
static json_t *report_amount_arithmetic_inconsistencies;

/**
 * Array of reports about wire fees being ambiguous in terms of validity periods.
 */
static json_t *report_fee_time_inconsistencies;

/**
 * Profits the exchange made by bad amount calculations.
 */
static struct TALER_Amount total_arithmetic_delta_plus;

/**
 * Losses the exchange made by bad amount calculations.
 */
static struct TALER_Amount total_arithmetic_delta_minus;

/**
 * Total aggregation fees earned.
 */
static struct TALER_Amount total_aggregation_fee_income;

/**
 * Array of reports about coin operations with bad signatures.
 */
static json_t *report_bad_sig_losses;

/**
 * Total amount lost by operations for which signatures were invalid.
 */
static struct TALER_Amount total_bad_sig_loss;


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
 */
static void
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
  TALER_ARL_report (report_coin_inconsistencies,
                    json_pack ("{s:s, s:o, s:o, s:o, s:I}",
                               "operation", operation,
                               "coin_pub", GNUNET_JSON_from_data_auto (
                                 coin_pub),
                               "exchange", TALER_JSON_from_amount (exchange),
                               "auditor", TALER_JSON_from_amount (auditor),
                               "profitable", (json_int_t) profitable));
  if (0 != profitable)
  {
    target = (1 == profitable)
             ? &total_coin_delta_plus
             : &total_coin_delta_minus;
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
  struct GNUNET_TIME_Absolute start_date;

  /**
   * When does the fee stop being in effect (exclusive).
   */
  struct GNUNET_TIME_Absolute end_date;

  /**
   * How high is the wire fee.
   */
  struct TALER_Amount wire_fee;

  /**
   * How high is the closing fee.
   */
  struct TALER_Amount closing_fee;

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
   * Hash of the wire transfer details of the receiver.
   */
  struct GNUNET_HashCode h_wire;

  /**
   * Execution time of the wire transfer.
   */
  struct GNUNET_TIME_Absolute date;

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
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if the transaction must fail (hard error)
 */
static int
check_transaction_history_for_deposit (
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct GNUNET_HashCode *h_contract_terms,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_DenominationKeyValidityPS *issue,
  const struct TALER_EXCHANGEDB_TransactionList *tl_head,
  struct TALER_Amount *merchant_gain,
  struct TALER_Amount *deposit_gain)
{
  struct TALER_Amount expenditures;
  struct TALER_Amount refunds;
  struct TALER_Amount spent;
  struct TALER_Amount merchant_loss;
  const struct TALER_Amount *deposit_fee;
  int refund_deposit_fee;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Checking transaction history of coin %s\n",
              TALER_B2S (coin_pub));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &expenditures));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &refunds));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        merchant_gain));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &merchant_loss));
  /* Go over transaction history to compute totals; note that we do not bother
     to reconstruct the order of the events, so instead of subtracting we
     compute positive (deposit, melt) and negative (refund) values separately
     here, and then subtract the negative from the positive at the end (after
     the loops). *///
  refund_deposit_fee = GNUNET_NO;
  deposit_fee = NULL;
  for (const struct TALER_EXCHANGEDB_TransactionList *tl = tl_head;
       NULL != tl;
       tl = tl->next)
  {
    const struct TALER_Amount *amount_with_fee;
    const struct TALER_Amount *fee_claimed;

    switch (tl->type)
    {
    case TALER_EXCHANGEDB_TT_DEPOSIT:
      /* check wire and h_wire are consistent */
      {
        struct GNUNET_HashCode hw;

        if (GNUNET_OK !=
            TALER_JSON_merchant_wire_signature_hash (
              tl->details.deposit->receiver_wire_account,
              &hw))
        {
          report_row_inconsistency ("deposits",
                                    tl->serial_id,
                                    "wire account given is malformed");
        }
        else if (0 !=
                 GNUNET_memcmp (&hw,
                                &tl->details.deposit->h_wire))
        {
          report_row_inconsistency ("deposits",
                                    tl->serial_id,
                                    "h(wire) does not match wire");
        }
      }
      amount_with_fee = &tl->details.deposit->amount_with_fee; /* according to exchange*/
      fee_claimed = &tl->details.deposit->deposit_fee; /* Fee according to exchange DB */
      TALER_ARL_amount_add (&expenditures,
                            &expenditures,
                            amount_with_fee);
      /* Check if this deposit is within the remit of the aggregation
         we are investigating, if so, include it in the totals. */
      if ( (0 == GNUNET_memcmp (merchant_pub,
                                &tl->details.deposit->merchant_pub)) &&
           (0 == GNUNET_memcmp (h_contract_terms,
                                &tl->details.deposit->h_contract_terms)) )
      {
        struct TALER_Amount amount_without_fee;

        TALER_ARL_amount_subtract (&amount_without_fee,
                                   amount_with_fee,
                                   fee_claimed);
        TALER_ARL_amount_add (merchant_gain,
                              merchant_gain,
                              &amount_without_fee);
        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "Detected applicable deposit of %s\n",
                    TALER_amount2s (&amount_without_fee));
        deposit_fee = fee_claimed; /* We had a deposit, remember the fee, we may need it */
      }
      /* Check that the fees given in the transaction list and in dki match */
      {
        struct TALER_Amount fee_expected;

        /* Fee according to denomination data of auditor */
        TALER_amount_ntoh (&fee_expected,
                           &issue->fee_deposit);
        if (0 !=
            TALER_amount_cmp (&fee_expected,
                              fee_claimed))
        {
          /* Disagreement in fee structure between auditor and exchange DB! */
          report_amount_arithmetic_inconsistency ("deposit fee",
                                                  UINT64_MAX,
                                                  fee_claimed,
                                                  &fee_expected,
                                                  1);
        }
      }
      break;
    case TALER_EXCHANGEDB_TT_MELT:
      amount_with_fee = &tl->details.melt->amount_with_fee;
      fee_claimed = &tl->details.melt->melt_fee;
      TALER_ARL_amount_add (&expenditures,
                            &expenditures,
                            amount_with_fee);
      /* Check that the fees given in the transaction list and in dki match */
      {
        struct TALER_Amount fee_expected;

        TALER_amount_ntoh (&fee_expected,
                           &issue->fee_refresh);
        if (0 !=
            TALER_amount_cmp (&fee_expected,
                              fee_claimed))
        {
          /* Disagreement in fee structure between exchange and auditor */
          report_amount_arithmetic_inconsistency ("melt fee",
                                                  UINT64_MAX,
                                                  fee_claimed,
                                                  &fee_expected,
                                                  1);
        }
      }
      break;
    case TALER_EXCHANGEDB_TT_REFUND:
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
      if ( (0 == GNUNET_memcmp (merchant_pub,
                                &tl->details.refund->merchant_pub)) &&
           (0 == GNUNET_memcmp (h_contract_terms,
                                &tl->details.refund->h_contract_terms)) )
      {
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Detected applicable refund of %s\n",
                    TALER_amount2s (amount_with_fee));
        TALER_ARL_amount_add (&merchant_loss,
                              &merchant_loss,
                              amount_with_fee);
        /* If there is a refund, we give back the deposit fee */
        refund_deposit_fee = GNUNET_YES;
      }
      /* Check that the fees given in the transaction list and in dki match */
      {
        struct TALER_Amount fee_expected;

        TALER_amount_ntoh (&fee_expected,
                           &issue->fee_refund);
        if (0 !=
            TALER_amount_cmp (&fee_expected,
                              fee_claimed))
        {
          /* Disagreement in fee structure between exchange and auditor! */
          report_amount_arithmetic_inconsistency ("refund fee",
                                                  UINT64_MAX,
                                                  fee_claimed,
                                                  &fee_expected,
                                                  1);
        }
      }
      break;
    case TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP:
      amount_with_fee = &tl->details.old_coin_recoup->value;
      /* We count recoups of refreshed coins like refunds for the dirty old
         coin, as they equivalently _increase_ the remaining value on the
         _old_ coin */
      TALER_ARL_amount_add (&refunds,
                            &refunds,
                            amount_with_fee);
      break;
    case TALER_EXCHANGEDB_TT_RECOUP:
      /* We count recoups of the coin as expenditures, as it
         equivalently decreases the remaining value of the recouped coin. */
      amount_with_fee = &tl->details.recoup->value;
      TALER_ARL_amount_add (&expenditures,
                            &expenditures,
                            amount_with_fee);
      break;
    case TALER_EXCHANGEDB_TT_RECOUP_REFRESH:
      /* We count recoups of the coin as expenditures, as it
         equivalently decreases the remaining value of the recouped coin. */
      amount_with_fee = &tl->details.recoup_refresh->value;
      TALER_ARL_amount_add (&expenditures,
                            &expenditures,
                            amount_with_fee);
      break;
    }
  } /* for 'tl' */

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Deposits for this aggregation (after fees) are %s\n",
              TALER_amount2s (merchant_gain));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Aggregation loss due to refunds is %s\n",
              TALER_amount2s (&merchant_loss));
  *deposit_gain = *merchant_gain;
  if ( (GNUNET_YES == refund_deposit_fee) &&
       (NULL != deposit_fee) )
  {
    /* We had a /deposit operation AND a /refund operation,
       and should thus not charge the merchant the /deposit fee */
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
      report_coin_arithmetic_inconsistency ("refund (merchant)",
                                            coin_pub,
                                            merchant_gain,
                                            &merchant_loss,
                                            1);
      /* For the overall aggregation, we should not count this
         as a NEGATIVE contribution as that is not allowed; so
         let's count it as zero as that's the best we can do. */
      GNUNET_assert (GNUNET_OK ==
                     TALER_amount_get_zero (TALER_ARL_currency,
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
    report_coin_arithmetic_inconsistency ("refund (balance)",
                                          coin_pub,
                                          &expenditures,
                                          &refunds,
                                          1);
  }
  else
  {
    /* Now check that 'spent' is less or equal than the total coin value */
    struct TALER_Amount value;

    TALER_amount_ntoh (&value,
                       &issue->value);
    if (1 == TALER_amount_cmp (&spent,
                               &value))
    {
      /* spent > value */
      report_coin_arithmetic_inconsistency ("spend",
                                            coin_pub,
                                            &spent,
                                            &value,
                                            -1);
    }
  }


  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Final merchant gain after refunds is %s\n",
              TALER_amount2s (deposit_gain));
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Coin %s contributes %s to contract %s\n",
              TALER_B2S (coin_pub),
              TALER_amount2s (merchant_gain),
              GNUNET_h2s (h_contract_terms));
  return GNUNET_OK;
}


/**
 * Function called with the results of the lookup of the
 * transaction data associated with a wire transfer identifier.
 *
 * @param[in,out] cls a `struct WireCheckContext`
 * @param rowid which row in the table is the information from (for diagnostics)
 * @param merchant_pub public key of the merchant (should be same for all callbacks with the same @e cls)
 * @param h_wire hash of wire transfer details of the merchant (should be same for all callbacks with the same @e cls)
 * @param account_details where did we transfer the funds?
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
  const struct GNUNET_HashCode *h_wire,
  const json_t *account_details,
  struct GNUNET_TIME_Absolute exec_time,
  const struct GNUNET_HashCode *h_contract_terms,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_Amount *coin_value,
  const struct TALER_Amount *deposit_fee)
{
  struct WireCheckContext *wcc = cls;
  const struct TALER_DenominationKeyValidityPS *issue;
  struct TALER_Amount computed_value;
  struct TALER_Amount total_deposit_without_refunds;
  struct TALER_EXCHANGEDB_TransactionList *tl;
  struct TALER_CoinPublicInfo coin;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_HashCode hw;

  if (GNUNET_OK !=
      TALER_JSON_merchant_wire_signature_hash (account_details,
                                               &hw))
  {
    report_row_inconsistency ("aggregation",
                              rowid,
                              "failed to compute hash of given wire data");
  }
  else if (0 !=
           GNUNET_memcmp (&hw,
                          h_wire))
  {
    report_row_inconsistency ("aggregation",
                              rowid,
                              "database contains wrong hash code for wire details");
  }

  /* Obtain coin's transaction history */
  qs = TALER_ARL_edb->get_coin_transactions (TALER_ARL_edb->cls,
                                             TALER_ARL_esession,
                                             coin_pub,
                                             GNUNET_YES,
                                             &tl);
  if ( (qs < 0) ||
       (NULL == tl) )
  {
    wcc->qs = qs;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "no transaction history for coin claimed in aggregation");
    return;
  }
  qs = TALER_ARL_edb->get_known_coin (TALER_ARL_edb->cls,
                                      TALER_ARL_esession,
                                      coin_pub,
                                      &coin);
  if (qs <= 0)
  {
    /* this should be a foreign key violation at this point! */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    wcc->qs = qs;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "could not get coin details for coin claimed in aggregation");
    TALER_ARL_edb->free_coin_transaction_list (TALER_ARL_edb->cls,
                                               tl);
    return;
  }

  qs = TALER_ARL_get_denomination_info_by_hash (&coin.denom_pub_hash,
                                                &issue);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_CRYPTO_rsa_signature_free (coin.denom_sig.rsa_signature);
    TALER_ARL_edb->free_coin_transaction_list (TALER_ARL_edb->cls,
                                               tl);
    if (0 == qs)
      report_row_inconsistency ("aggregation",
                                rowid,
                                "could not find denomination key for coin claimed in aggregation");
    else
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
    TALER_ARL_report (report_bad_sig_losses,
                      json_pack ("{s:s, s:I, s:o, s:o}",
                                 "operation", "wire",
                                 "row", (json_int_t) rowid,
                                 "loss", TALER_JSON_from_amount (coin_value),
                                 "coin_pub", GNUNET_JSON_from_data_auto (
                                   &coin.coin_pub)));
    TALER_ARL_amount_add (&total_bad_sig_loss,
                          &total_bad_sig_loss,
                          coin_value);
    GNUNET_CRYPTO_rsa_signature_free (coin.denom_sig.rsa_signature);
    TALER_ARL_edb->free_coin_transaction_list (TALER_ARL_edb->cls,
                                               tl);
    report_row_inconsistency ("deposit",
                              rowid,
                              "coin denomination signature invalid");
    return;
  }
  GNUNET_CRYPTO_rsa_signature_free (coin.denom_sig.rsa_signature);
  coin.denom_sig.rsa_signature = NULL; /* just to be sure */
  GNUNET_assert (NULL != issue); /* mostly to help static analysis */
  /* Check transaction history to see if it supports aggregate
     valuation */
  if (GNUNET_OK !=
      check_transaction_history_for_deposit (coin_pub,
                                             h_contract_terms,
                                             merchant_pub,
                                             issue,
                                             tl,
                                             &computed_value,
                                             &total_deposit_without_refunds))
  {
    TALER_ARL_edb->free_coin_transaction_list (TALER_ARL_edb->cls,
                                               tl);
    wcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
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
      wcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      report_amount_arithmetic_inconsistency (
        "aggregation (fee structure)",
        rowid,
        coin_value,
        deposit_fee,
        -1);
      return;
    }
    if (0 !=
        TALER_amount_cmp (&total_deposit_without_refunds,
                          &coin_value_without_fee))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Expected coin contribution of %s to aggregate\n",
                  TALER_amount2s (&coin_value_without_fee));
      report_amount_arithmetic_inconsistency (
        "aggregation (contribution)",
        rowid,
        &coin_value_without_fee,
        &
        total_deposit_without_refunds,
        -1);
    }
  }
  /* Check other details of wire transfer match */
  if (0 != GNUNET_memcmp (h_wire,
                          &wcc->h_wire))
  {
    report_row_inconsistency ("aggregation",
                              rowid,
                              "target of outgoing wire transfer do not match hash of wire from deposit");
  }
  if (exec_time.abs_value_us != wcc->date.abs_value_us)
  {
    /* This should be impossible from database constraints */
    GNUNET_break (0);
    report_row_inconsistency ("aggregation",
                              rowid,
                              "date given in aggregate does not match wire transfer date");
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
              struct GNUNET_TIME_Absolute timestamp)
{
  struct WireFeeInfo *wfi;
  struct WireFeeInfo *pos;
  struct TALER_MasterSignatureP master_sig;

  /* Check if fee is already loaded in cache */
  for (pos = ac->fee_head; NULL != pos; pos = pos->next)
  {
    if ( (pos->start_date.abs_value_us <= timestamp.abs_value_us) &&
         (pos->end_date.abs_value_us > timestamp.abs_value_us) )
      return &pos->wire_fee;
    if (pos->start_date.abs_value_us > timestamp.abs_value_us)
      break;
  }

  /* Lookup fee in exchange database */
  wfi = GNUNET_new (struct WireFeeInfo);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      TALER_ARL_edb->get_wire_fee (TALER_ARL_edb->cls,
                                   TALER_ARL_esession,
                                   method,
                                   timestamp,
                                   &wfi->start_date,
                                   &wfi->end_date,
                                   &wfi->wire_fee,
                                   &wfi->closing_fee,
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
    struct TALER_MasterWireFeePS wf = {
      .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_WIRE_FEES),
      .purpose.size = htonl (sizeof (wf)),
      .start_date = GNUNET_TIME_absolute_hton (wfi->start_date),
      .end_date = GNUNET_TIME_absolute_hton (wfi->end_date)
    };

    GNUNET_CRYPTO_hash (method,
                        strlen (method) + 1,
                        &wf.h_wire_method);
    TALER_amount_hton (&wf.wire_fee,
                       &wfi->wire_fee);
    TALER_amount_hton (&wf.closing_fee,
                       &wfi->closing_fee);
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_WIRE_FEES,
                                    &wf,
                                    &master_sig.eddsa_signature,
                                    &TALER_ARL_master_pub.eddsa_pub))
    {
      report_row_inconsistency ("wire-fee",
                                timestamp.abs_value_us,
                                "wire fee signature invalid at given time");
    }
  }

  /* Established fee, keep in sorted list */
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Wire fee is %s starting at %s\n",
              TALER_amount2s (&wfi->wire_fee),
              GNUNET_STRINGS_absolute_time_to_string (wfi->start_date));
  if ( (NULL == pos) ||
       (NULL == pos->prev) )
    GNUNET_CONTAINER_DLL_insert (ac->fee_head,
                                 ac->fee_tail,
                                 wfi);
  else
    GNUNET_CONTAINER_DLL_insert_after (ac->fee_head,
                                       ac->fee_tail,
                                       pos->prev,
                                       wfi);
  /* Check non-overlaping fee invariant */
  if ( (NULL != wfi->prev) &&
       (wfi->prev->end_date.abs_value_us > wfi->start_date.abs_value_us) )
  {
    TALER_ARL_report (report_fee_time_inconsistencies,
                      json_pack ("{s:s, s:s, s:o}",
                                 "type", method,
                                 "diagnostic",
                                 "start date before previous end date",
                                 "time", TALER_ARL_json_from_time_abs (
                                   wfi->start_date)));
  }
  if ( (NULL != wfi->next) &&
       (wfi->next->start_date.abs_value_us >= wfi->end_date.abs_value_us) )
  {
    TALER_ARL_report (report_fee_time_inconsistencies,
                      json_pack ("{s:s, s:s, s:o}",
                                 "type", method,
                                 "diagnostic",
                                 "end date date after next start date",
                                 "time", TALER_ARL_json_from_time_abs (
                                   wfi->end_date)));
  }
  return &wfi->wire_fee;
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
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to stop iteration
 */
static int
check_wire_out_cb (void *cls,
                   uint64_t rowid,
                   struct GNUNET_TIME_Absolute date,
                   const struct TALER_WireTransferIdentifierRawP *wtid,
                   const json_t *wire,
                   const struct TALER_Amount *amount)
{
  struct AggregationContext *ac = cls;
  struct WireCheckContext wcc;
  struct TALER_Amount final_amount;
  struct TALER_Amount exchange_gain;
  enum GNUNET_DB_QueryStatus qs;
  char *method;

  /* should be monotonically increasing */
  GNUNET_assert (rowid >= ppa.last_wire_out_serial_id);
  ppa.last_wire_out_serial_id = rowid + 1;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Checking wire transfer %s over %s performed on %s\n",
              TALER_B2S (wtid),
              TALER_amount2s (amount),
              GNUNET_STRINGS_absolute_time_to_string (date));
  if (NULL == (method = TALER_JSON_wire_to_method (wire)))
  {
    report_row_inconsistency ("wire_out",
                              rowid,
                              "specified wire address lacks method");
    return GNUNET_OK;
  }

  wcc.ac = ac;
  wcc.qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  wcc.date = date;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (amount->currency,
                                        &wcc.total_deposits));
  if (GNUNET_OK !=
      TALER_JSON_merchant_wire_signature_hash (wire,
                                               &wcc.h_wire))
  {
    GNUNET_break (0);
    GNUNET_free (method);
    return GNUNET_SYSERR;
  }
  qs = TALER_ARL_edb->lookup_wire_transfer (TALER_ARL_edb->cls,
                                            TALER_ARL_esession,
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
                "Inconsitency for wire_out %llu (WTID %s) detected\n",
                (unsigned long long) rowid,
                TALER_B2S (wtid));
  }


  /* Subtract aggregation fee from total (if possible) */
  {
    const struct TALER_Amount *wire_fee;

    wire_fee = get_wire_fee (ac,
                             method,
                             date);
    if (NULL == wire_fee)
    {
      report_row_inconsistency ("wire-fee",
                                date.abs_value_us,
                                "wire fee unavailable for given time");
      /* If fee is unknown, we just assume the fee is zero */
      final_amount = wcc.total_deposits;
    }
    else if (TALER_ARL_SR_INVALID_NEGATIVE ==
             TALER_ARL_amount_subtract_neg (&final_amount,
                                            &wcc.total_deposits,
                                            wire_fee))
    {
      report_amount_arithmetic_inconsistency (
        "wire out (fee structure)",
        rowid,
        &wcc.total_deposits,
        wire_fee,
        -1);
      /* If fee arithmetic fails, we just assume the fee is zero */
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
  TALER_ARL_amount_add (&total_aggregation_fee_income,
                        &total_aggregation_fee_income,
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
      TALER_ARL_amount_add (&total_wire_out_delta_plus,
                            &total_wire_out_delta_plus,
                            &delta);
    }
    else
    {
      /* amount < final_amount */
      TALER_ARL_amount_subtract (&delta,
                                 &final_amount,
                                 amount);
      TALER_ARL_amount_add (&total_wire_out_delta_minus,
                            &total_wire_out_delta_minus,
                            &delta);
    }

    TALER_ARL_report (report_wire_out_inconsistencies,
                      json_pack ("{s:O, s:I, s:o, s:o}",
                                 "destination_account", wire,
                                 "rowid", (json_int_t) rowid,
                                 "expected",
                                 TALER_JSON_from_amount (&final_amount),
                                 "claimed",
                                 TALER_JSON_from_amount (amount)));
    if (TALER_ARL_do_abort ())
      return GNUNET_SYSERR;
    return GNUNET_OK;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Aggregation unit %s is OK\n",
              TALER_B2S (wtid));
  if (TALER_ARL_do_abort ())
    return GNUNET_SYSERR;
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
  enum GNUNET_DB_QueryStatus qsx;
  enum GNUNET_DB_QueryStatus qs;
  enum GNUNET_DB_QueryStatus qsp;

  (void) cls;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Analyzing aggregations\n");
  qsp = TALER_ARL_adb->get_auditor_progress_aggregation (TALER_ARL_adb->cls,
                                                         TALER_ARL_asession,
                                                         &TALER_ARL_master_pub,
                                                         &ppa);
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
    ppa_start = ppa;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Resuming aggregation audit at %llu\n",
                (unsigned long long) ppa.last_wire_out_serial_id);
  }

  memset (&ac,
          0,
          sizeof (ac));
  qsx = TALER_ARL_adb->get_wire_fee_summary (TALER_ARL_adb->cls,
                                             TALER_ARL_asession,
                                             &TALER_ARL_master_pub,
                                             &total_aggregation_fee_income);
  if (0 > qsx)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsx);
    return qsx;
  }
  ac.qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  qs = TALER_ARL_edb->select_wire_out_above_serial_id (
    TALER_ARL_edb->cls,
    TALER_ARL_esession,
    ppa.last_wire_out_serial_id,
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
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsx)
    ac.qs = TALER_ARL_adb->insert_wire_fee_summary (
      TALER_ARL_adb->cls,
      TALER_ARL_asession,
      &TALER_ARL_master_pub,
      &total_aggregation_fee_income);
  else
    ac.qs = TALER_ARL_adb->update_wire_fee_summary (
      TALER_ARL_adb->cls,
      TALER_ARL_asession,
      &TALER_ARL_master_pub,
      &total_aggregation_fee_income);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != ac.qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == ac.qs);
    return ac.qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qsp)
    qs = TALER_ARL_adb->update_auditor_progress_aggregation (
      TALER_ARL_adb->cls,
      TALER_ARL_asession,
      &TALER_ARL_master_pub,
      &ppa);
  else
    qs = TALER_ARL_adb->insert_auditor_progress_aggregation (
      TALER_ARL_adb->cls,
      TALER_ARL_asession,
      &TALER_ARL_master_pub,
      &ppa);
  if (0 >= qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Concluded aggregation audit step at %llu\n",
              (unsigned long long) ppa.last_wire_out_serial_id);

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
  json_t *report;

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
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting audit\n");
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_aggregation_fee_income));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_wire_out_delta_plus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_wire_out_delta_minus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_arithmetic_delta_plus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_arithmetic_delta_minus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_coin_delta_plus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_coin_delta_minus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TALER_ARL_currency,
                                        &total_bad_sig_loss));
  GNUNET_assert (NULL !=
                 (report_row_inconsistencies
                    = json_array ()));
  GNUNET_assert (NULL !=
                 (report_wire_out_inconsistencies
                    = json_array ()));
  GNUNET_assert (NULL !=
                 (report_coin_inconsistencies
                    = json_array ()));
  GNUNET_assert (NULL !=
                 (report_amount_arithmetic_inconsistencies
                    = json_array ()));
  GNUNET_assert (NULL !=
                 (report_bad_sig_losses
                    = json_array ()));
  GNUNET_assert (NULL !=
                 (report_fee_time_inconsistencies
                    = json_array ()));
  if (GNUNET_OK !=
      TALER_ARL_setup_sessions_and_run (&analyze_aggregations,
                                        NULL))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Audit failed\n");
    TALER_ARL_done (NULL);
    global_ret = 1;
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Audit complete\n");
  report = json_pack ("{s:o, s:o, s:o, s:o, s:o,"
                      " s:o, s:o, s:o, s:o, s:o,"
                      " s:o, s:o, s:o, s:I, s:I,"
                      " s:o, s:o, s:o }",
                      /* blocks #1 */
                      "wire_out_inconsistencies",
                      report_wire_out_inconsistencies,
                      /* Tested in test-auditor.sh #23 */
                      "total_wire_out_delta_plus",
                      TALER_JSON_from_amount (
                        &total_wire_out_delta_plus),
                      /* Tested in test-auditor.sh #23 */
                      "total_wire_out_delta_minus",
                      TALER_JSON_from_amount (
                        &total_wire_out_delta_minus),
                      /* Tested in test-auditor.sh #28/32 */
                      "bad_sig_losses",
                      report_bad_sig_losses,
                      /* Tested in test-auditor.sh #28/32 */
                      "total_bad_sig_loss",
                      TALER_JSON_from_amount (&total_bad_sig_loss),
                      /* block #2 */
                      /* Tested in test-auditor.sh #15 */
                      "row_inconsistencies",
                      report_row_inconsistencies,
                      "coin_inconsistencies",
                      report_coin_inconsistencies,
                      "total_coin_delta_plus",
                      TALER_JSON_from_amount (&total_coin_delta_plus),
                      "total_coin_delta_minus",
                      TALER_JSON_from_amount (
                        &total_coin_delta_minus),
                      "amount_arithmetic_inconsistencies",
                      report_amount_arithmetic_inconsistencies,
                      /* block #3 */
                      "total_arithmetic_delta_plus",
                      TALER_JSON_from_amount (
                        &total_arithmetic_delta_plus),
                      "total_arithmetic_delta_minus",
                      TALER_JSON_from_amount (
                        &total_arithmetic_delta_minus),
                      "total_aggregation_fee_income",
                      TALER_JSON_from_amount (
                        &total_aggregation_fee_income),
                      "start_ppa_wire_out_serial_id",
                      (json_int_t) ppa_start.last_wire_out_serial_id,
                      "end_ppa_wire_out_serial_id",
                      (json_int_t) ppa.last_wire_out_serial_id,
                      /* block #4 */
                      "auditor_start_time",
                      TALER_ARL_json_from_time_abs (
                        start_time),
                      "auditor_end_time",
                      TALER_ARL_json_from_time_abs (
                        GNUNET_TIME_absolute_get ()),
                      "wire_fee_time_inconsistencies",
                      report_fee_time_inconsistencies
                      );
  GNUNET_break (NULL != report);
  TALER_ARL_done (report);
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
                 GNUNET_log_setup ("taler-helper-auditor-aggregation",
                                   "MESSAGE",
                                   NULL));
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc,
                          argv,
                          "taler-helper-auditor-aggregation",
                          "Audit Taler exchange aggregation activity",
                          options,
                          &run,
                          NULL))
    return 1;
  return global_ret;
}


/* end of taler-helper-auditor-aggregation.c */
