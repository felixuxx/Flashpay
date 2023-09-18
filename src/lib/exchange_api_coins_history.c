/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/exchange_api_coins_history.c
 * @brief Implementation of the POST /coins/$COIN_PUB/history requests
 * @author Christian Grothoff
 *
 * NOTE: this is an incomplete draft, never finished!
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP history codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A /coins/$RID/history Handle
 */
struct TALER_EXCHANGE_CoinsHistoryHandle
{

  /**
   * The keys of the exchange this request handle will use
   */
  struct TALER_EXCHANGE_Keys *keys;

  /**
   * The url for this request.
   */
  char *url;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Context for #TEH_curl_easy_post(). Keeps the data that must
   * persist for Curl to make the upload.
   */
  struct TALER_CURL_PostContext post_ctx;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_CoinsHistoryCallback cb;

  /**
   * Public key of the coin we are querying.
   */
  struct TALER_CoinPublicKeyP coin_pub;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * Context for coin helpers.
 */
struct CoinHistoryParseContext
{

  /**
   * Denomination of the coin.
   */
  const struct TALER_EXCHANGE_DenomPublicKey *dk;

  /**
   * Our coin public key.
   */
  const struct TALER_CoinSpendPublicKeyP *coin_pub;

  /**
   * Where to sum up total refunds.
   */
  struct TALER_Amount rtotal;

  /**
   * Total amount encountered.
   */
  struct TALER_Amount *total;

};


/**
 * Signature of functions that operate on one of
 * the coin's history entries.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
typedef enum GNUNET_GenericReturnValue
(*CoinCheckHelper)(struct CoinHistoryParseContext *pc,
                   const struct TALER_Amount *amount,
                   json_t *transaction);


/**
 * Handle deposit entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_deposit (struct CoinHistoryParseContext *pc,
              const struct TALER_Amount *amount,
              json_t *transaction)
{
  struct TALER_MerchantWireHashP h_wire;
  struct TALER_PrivateContractHashP h_contract_terms;
  struct TALER_ExtensionPolicyHashP h_policy;
  bool no_h_policy;
  struct GNUNET_HashCode wallet_data_hash;
  bool no_wallet_data_hash;
  struct GNUNET_TIME_Timestamp wallet_timestamp;
  struct TALER_MerchantPublicKeyP merchant_pub;
  struct GNUNET_TIME_Timestamp refund_deadline = {0};
  struct TALER_CoinSpendSignatureP sig;
  struct TALER_AgeCommitmentHash hac;
  bool no_hac;
  struct TALER_Amount deposit_fee;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &sig),
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                 &h_contract_terms),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("wallet_data_hash",
                                   &wallet_data_hash),
      &no_wallet_data_hash),
    GNUNET_JSON_spec_fixed_auto ("h_wire",
                                 &h_wire),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                   &hac),
      &no_hac),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("h_policy",
                                   &h_policy),
      &no_h_policy),
    GNUNET_JSON_spec_timestamp ("timestamp",
                                &wallet_timestamp),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_timestamp ("refund_deadline",
                                  &refund_deadline),
      NULL),
    TALER_JSON_spec_amount_any ("deposit_fee",
                                &deposit_fee),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                 &merchant_pub),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_deposit_verify (
        amount,
        &deposit_fee,
        &h_wire,
        &h_contract_terms,
        no_wallet_data_hash ? NULL : &wallet_data_hash,
        no_hac ? NULL : &hac,
        no_h_policy ? NULL : &h_policy,
        &pc->dk->h_key,
        wallet_timestamp,
        &merchant_pub,
        refund_deadline,
        pc->coin_pub,
        &sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  /* check that deposit fee matches our expectations from /keys! */
  if ( (GNUNET_YES !=
        TALER_amount_cmp_currency (&deposit_fee,
                                   &pc->dk->fees.deposit)) ||
       (0 !=
        TALER_amount_cmp (&deposit_fee,
                          &pc->dk->fees.deposit)) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_YES;
}


/**
 * Handle melt entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_melt (struct CoinHistoryParseContext *pc,
           const struct TALER_Amount *amount,
           json_t *transaction)
{
  struct TALER_CoinSpendSignatureP sig;
  struct TALER_RefreshCommitmentP rc;
  struct TALER_AgeCommitmentHash h_age_commitment;
  bool no_hac;
  struct TALER_Amount melt_fee;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &sig),
    GNUNET_JSON_spec_fixed_auto ("rc",
                                 &rc),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                   &h_age_commitment),
      &no_hac),
    TALER_JSON_spec_amount_any ("melt_fee",
                                &melt_fee),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* check that melt fee matches our expectations from /keys! */
  if ( (GNUNET_YES !=
        TALER_amount_cmp_currency (&melt_fee,
                                   &pc->dk->fees.refresh)) ||
       (0 !=
        TALER_amount_cmp (&melt_fee,
                          &pc->dk->fees.refresh)) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_melt_verify (
        amount,
        &melt_fee,
        &rc,
        &pc->dk->h_key,
        no_hac
        ? NULL
        : &h_age_commitment,
        pc->coin_pub,
        &sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_YES;
}


/**
 * Handle refund entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_refund (struct CoinHistoryParseContext *pc,
             const struct TALER_Amount *amount,
             json_t *transaction)
{
  struct TALER_PrivateContractHashP h_contract_terms;
  struct TALER_MerchantPublicKeyP merchant_pub;
  struct TALER_MerchantSignatureP sig;
  struct TALER_Amount refund_fee;
  struct TALER_Amount sig_amount;
  uint64_t rtransaction_id;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount_any ("refund_fee",
                                &refund_fee),
    GNUNET_JSON_spec_fixed_auto ("merchant_sig",
                                 &sig),
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                 &h_contract_terms),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                 &merchant_pub),
    GNUNET_JSON_spec_uint64 ("rtransaction_id",
                             &rtransaction_id),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (0 >
      TALER_amount_add (&sig_amount,
                        &refund_fee,
                        amount))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_merchant_refund_verify (pc->coin_pub,
                                    &h_contract_terms,
                                    rtransaction_id,
                                    &sig_amount,
                                    &merchant_pub,
                                    &sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  /* NOTE: theoretically, we could also check that the given
     merchant_pub and h_contract_terms appear in the
     history under deposits.  However, there is really no benefit
     for the exchange to lie here, so not checking is probably OK
     (an auditor ought to check, though). Then again, we similarly
     had no reason to check the merchant's signature (other than a
     well-formendess check). */

  /* check that refund fee matches our expectations from /keys! */
  if ( (GNUNET_YES !=
        TALER_amount_cmp_currency (&refund_fee,
                                   &pc->dk->fees.refund)) ||
       (0 !=
        TALER_amount_cmp (&refund_fee,
                          &pc->dk->fees.refund)) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_NO;
}


/**
 * Handle recoup entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_recoup (struct CoinHistoryParseContext *pc,
             const struct TALER_Amount *amount,
             json_t *transaction)
{
  struct TALER_ReservePublicKeyP reserve_pub;
  struct GNUNET_TIME_Timestamp timestamp;
  union TALER_DenominationBlindingKeyP coin_bks;
  struct TALER_ExchangePublicKeyP exchange_pub;
  struct TALER_ExchangeSignatureP exchange_sig;
  struct TALER_CoinSpendSignatureP coin_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                 &exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 &exchange_pub),
    GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                 &reserve_pub),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &coin_sig),
    GNUNET_JSON_spec_fixed_auto ("coin_blind",
                                 &coin_bks),
    GNUNET_JSON_spec_timestamp ("timestamp",
                                &timestamp),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_exchange_online_confirm_recoup_verify (
        timestamp,
        amount,
        pc->coin_pub,
        &reserve_pub,
        &exchange_pub,
        &exchange_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_recoup_verify (&pc->dk->h_key,
                                  &coin_bks,
                                  pc->coin_pub,
                                  &coin_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_YES;
}


/**
 * Handle recoup-refresh entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_recoup_refresh (struct CoinHistoryParseContext *pc,
                     const struct TALER_Amount *amount,
                     json_t *transaction)
{
  /* This is the coin that was subjected to a recoup,
       the value being credited to the old coin. */
  struct TALER_CoinSpendPublicKeyP old_coin_pub;
  union TALER_DenominationBlindingKeyP coin_bks;
  struct GNUNET_TIME_Timestamp timestamp;
  struct TALER_ExchangePublicKeyP exchange_pub;
  struct TALER_ExchangeSignatureP exchange_sig;
  struct TALER_CoinSpendSignatureP coin_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                 &exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 &exchange_pub),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &coin_sig),
    GNUNET_JSON_spec_fixed_auto ("old_coin_pub",
                                 &old_coin_pub),
    GNUNET_JSON_spec_fixed_auto ("coin_blind",
                                 &coin_bks),
    GNUNET_JSON_spec_timestamp ("timestamp",
                                &timestamp),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_exchange_online_confirm_recoup_refresh_verify (
        timestamp,
        amount,
        pc->coin_pub,
        &old_coin_pub,
        &exchange_pub,
        &exchange_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_recoup_verify (&pc->dk->h_key,
                                  &coin_bks,
                                  pc->coin_pub,
                                  &coin_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_YES;
}


/**
 * Handle old coin recoup entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_old_coin_recoup (struct CoinHistoryParseContext *pc,
                      const struct TALER_Amount *amount,
                      json_t *transaction)
{
  /* This is the coin that was credited in a recoup,
       the value being credited to the this coin. */
  struct TALER_ExchangePublicKeyP exchange_pub;
  struct TALER_ExchangeSignatureP exchange_sig;
  struct TALER_CoinSpendPublicKeyP new_coin_pub;
  struct GNUNET_TIME_Timestamp timestamp;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                 &exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 &exchange_pub),
    GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                 &new_coin_pub),
    GNUNET_JSON_spec_timestamp ("timestamp",
                                &timestamp),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_exchange_online_confirm_recoup_refresh_verify (
        timestamp,
        amount,
        &new_coin_pub,
        pc->coin_pub,
        &exchange_pub,
        &exchange_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_NO;
}


/**
 * Handle purse deposit entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_purse_deposit (struct CoinHistoryParseContext *pc,
                    const struct TALER_Amount *amount,
                    json_t *transaction)
{
  struct TALER_PurseContractPublicKeyP purse_pub;
  struct TALER_CoinSpendSignatureP coin_sig;
  const char *exchange_base_url;
  bool refunded;
  struct TALER_AgeCommitmentHash phac = { 0 };
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("purse_pub",
                                 &purse_pub),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &coin_sig),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                   &coin_sig),
      NULL),
    GNUNET_JSON_spec_string ("exchange_base_url",
                             &exchange_base_url),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                   &phac),
      NULL),
    GNUNET_JSON_spec_bool ("refunded",
                           &refunded),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_purse_deposit_verify (
        exchange_base_url,
        &purse_pub,
        amount,
        &pc->dk->h_key,
        &phac,
        pc->coin_pub,
        &coin_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (refunded)
  {
    /* We wave the deposit fee. */
    if (0 >
        TALER_amount_add (&pc->rtotal,
                          &pc->rtotal,
                          &pc->dk->fees.deposit))
    {
      /* overflow in refund history? inconceivable! Bad exchange! */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_YES;
}


/**
 * Handle purse refund entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_purse_refund (struct CoinHistoryParseContext *pc,
                   const struct TALER_Amount *amount,
                   json_t *transaction)
{
  struct TALER_PurseContractPublicKeyP purse_pub;
  struct TALER_Amount refund_fee;
  struct TALER_ExchangePublicKeyP exchange_pub;
  struct TALER_ExchangeSignatureP exchange_sig;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount_any ("refund_fee",
                                &refund_fee),
    GNUNET_JSON_spec_fixed_auto ("purse_pub",
                                 &purse_pub),
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                 &exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 &exchange_pub),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_exchange_online_purse_refund_verify (
        amount,
        &refund_fee,
        pc->coin_pub,
        &purse_pub,
        &exchange_pub,
        &exchange_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if ( (GNUNET_YES !=
        TALER_amount_cmp_currency (&refund_fee,
                                   &pc->dk->fees.refund)) ||
       (0 !=
        TALER_amount_cmp (&refund_fee,
                          &pc->dk->fees.refund)) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_NO;
}


/**
 * Handle reserve deposit entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_reserve_open_deposit (struct CoinHistoryParseContext *pc,
                           const struct TALER_Amount *amount,
                           json_t *transaction)
{
  struct TALER_ReserveSignatureP reserve_sig;
  struct TALER_CoinSpendSignatureP coin_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &reserve_sig),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &coin_sig),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_reserve_open_deposit_verify (
        amount,
        &reserve_sig,
        pc->coin_pub,
        &coin_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_YES;
}


/**
 * Convenience function.  Verifies a coin's transaction history as
 * returned by the exchange.
 *
 * FIXME: add support for partial histories!
 * NOTE: this API will thus still change!
 *
 * @param dk fee structure for the coin
 * @param coin_pub public key of the coin
 * @param history history of the coin in json encoding
 * @param[out] total how much of the coin has been spent according to @a history
 * @return #GNUNET_OK if @a history is valid, #GNUNET_SYSERR if not
 */
static enum GNUNET_GenericReturnValue
verify_coin_history (
  const struct TALER_EXCHANGE_DenomPublicKey *dk,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const json_t *history,
  struct TALER_Amount *total)
{
  const char *currency = dk->value.currency;
  const struct
  {
    const char *type;
    CoinCheckHelper helper;
  } map[] = {
    { "DEPOSIT", &help_deposit },
    { "MELT", &help_melt },
    { "REFUND", &help_refund },
    { "RECOUP", &help_recoup },
    { "RECOUP-REFRESH", &help_recoup_refresh },
    { "OLD-COIN-RECOUP", &help_old_coin_recoup },
    { "PURSE-DEPOSIT", &help_purse_deposit },
    { "PURSE-REFUND", &help_purse_refund },
    { "RESERVE-OPEN-DEPOSIT", &help_reserve_open_deposit },
    { NULL, NULL }
  };
  struct CoinHistoryParseContext pc = {
    .dk = dk,
    .coin_pub = coin_pub,
    .total = total
  };
  size_t len;

  if (NULL == history)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  len = json_array_size (history);
  if (0 == len)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (currency,
                                        total));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (currency,
                                        &pc.rtotal));
  for (size_t off = 0; off<len; off++)
  {
    enum GNUNET_GenericReturnValue add;
    json_t *transaction;
    struct TALER_Amount amount;
    const char *type;
    struct GNUNET_JSON_Specification spec_glob[] = {
      TALER_JSON_spec_amount_any ("amount",
                                  &amount),
      GNUNET_JSON_spec_string ("type",
                               &type),
      GNUNET_JSON_spec_end ()
    };

    transaction = json_array_get (history,
                                  off);
    if (GNUNET_OK !=
        GNUNET_JSON_parse (transaction,
                           spec_glob,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    if (GNUNET_YES !=
        TALER_amount_cmp_currency (&amount,
                                   &pc.rtotal))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Operation of type %s with amount %s\n",
                type,
                TALER_amount2s (&amount));
    add = GNUNET_SYSERR;
    for (unsigned int i = 0; NULL != map[i].type; i++)
    {
      if (0 == strcasecmp (type,
                           map[i].type))
      {
        add = map[i].helper (&pc,
                             &amount,
                             transaction);
        break;
      }
    }
    switch (add)
    {
    case GNUNET_SYSERR:
      /* entry type not supported, new version on server? */
      GNUNET_break_op (0);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Unexpected type `%s' in response\n",
                  type);
      return GNUNET_SYSERR;
    case GNUNET_YES:
      /* This amount should be added to the total */
      if (0 >
          TALER_amount_add (total,
                            total,
                            &amount))
      {
        /* overflow in history already!? inconceivable! Bad exchange! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      break;
    case GNUNET_NO:
      /* This amount should be subtracted from the total.

         However, for the implementation, we first *add* up all of
         these negative amounts, as we might get refunds before
         deposits from a semi-evil exchange.  Then, at the end, we do
         the subtraction by calculating "total = total - rtotal" */
      if (0 >
          TALER_amount_add (&pc.rtotal,
                            &pc.rtotal,
                            &amount))
      {
        /* overflow in refund history? inconceivable! Bad exchange! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      break;
    } /* end of switch(add) */
  }
  /* Finally, subtract 'rtotal' from total to handle the subtractions */
  if (0 >
      TALER_amount_subtract (total,
                             total,
                             &pc.rtotal))
  {
    /* underflow in history? inconceivable! Bad exchange! */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Verify that @a coin_sig does NOT appear in
 * the history of @a proof and thus whatever transaction
 * is authorized by @a coin_sig is a conflict with
 * @a proof.
 *
 * @param proof a proof to check
 * @param coin_sig signature that must not be in @a proof
 * @return #GNUNET_OK if @a coin_sig is not in @a proof
 */
// FIXME: should be used...
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_coin_signature_conflict_ (
  const json_t *proof,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  json_t *history;
  size_t off;
  json_t *entry;

  history = json_object_get (proof,
                             "history");
  if (NULL == history)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  json_array_foreach (history, off, entry)
  {
    struct TALER_CoinSpendSignatureP cs;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                   &cs),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (entry,
                           spec,
                           NULL, NULL))
      continue; /* entry without coin signature */
    if (0 ==
        GNUNET_memcmp (&cs,
                       coin_sig))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
}


/**
 * Check that the provided @a proof indeeds indicates
 * a conflict for @a coin_pub.
 *
 * @param keys exchange keys
 * @param proof provided conflict proof
 * @param dk denomination of @a coin_pub that the client
 *           used
 * @param coin_pub public key of the coin
 * @param required balance required on the coin for the operation
 * @return #GNUNET_OK if @a proof holds
 */
// FIXME: should be used!
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_coin_conflict_ (
  const struct TALER_EXCHANGE_Keys *keys,
  const json_t *proof,
  const struct TALER_EXCHANGE_DenomPublicKey *dk,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_Amount *required)
{
  enum TALER_ErrorCode ec;

  ec = TALER_JSON_get_error_code (proof);
  switch (ec)
  {
  case TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS:
    /* Nothing to check anymore here, proof needs to be
       checked in the GET /coins/$COIN_PUB handler */
    break;
  case TALER_EC_EXCHANGE_GENERIC_COIN_CONFLICTING_DENOMINATION_KEY:
    // FIXME: write check!
    break;
  default:
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * We received an #MHD_HTTP_OK history code. Handle the JSON
 * response.
 *
 * @param rsh handle of the request
 * @param j JSON response
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_coins_history_ok (struct TALER_EXCHANGE_CoinsHistoryHandle *rsh,
                         const json_t *j)
{
  const json_t *history;
  unsigned int len;
  struct TALER_EXCHANGE_CoinHistory rs = {
    .hr.reply = j,
    .hr.http_status = MHD_HTTP_OK
  };
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount_any ("balance",
                                &rs.details.ok.balance),
    GNUNET_JSON_spec_array_const ("history",
                                  &history),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (j,
                         spec,
                         NULL,
                         NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  len = json_array_size (history);
  {
    struct TALER_EXCHANGE_CoinHistoryEntry *rhistory;

    rhistory = GNUNET_new_array (len,
                                 struct TALER_EXCHANGE_CoinHistoryEntry);
    if (GNUNET_OK !=
        parse_coin_history (rsh->keys,
                            history,
                            &rsh->coin_pub,
                            rs.details.ok.balance.currency,
                            &rs.details.ok.total_in,
                            &rs.details.ok.total_out,
                            len,
                            rhistory))
    {
      GNUNET_break_op (0);
      free_coin_history (len,
                         rhistory);
      GNUNET_JSON_parse_free (spec);
      return GNUNET_SYSERR;
    }
    if (NULL != rsh->cb)
    {
      rs.details.ok.history = rhistory;
      rs.details.ok.history_len = len;
      rsh->cb (rsh->cb_cls,
               &rs);
      rsh->cb = NULL;
    }
    free_coin_history (len,
                       rhistory);
  }
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /coins/$RID/history request.
 *
 * @param cls the `struct TALER_EXCHANGE_CoinsHistoryHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_coins_history_finished (void *cls,
                               long response_code,
                               const void *response)
{
  struct TALER_EXCHANGE_CoinsHistoryHandle *rsh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_CoinHistory rs = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  rsh->job = NULL;
  switch (response_code)
  {
  case 0:
    rs.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        handle_coins_history_ok (rsh,
                                 j))
    {
      rs.hr.http_status = 0;
      rs.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    GNUNET_break (0);
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_FORBIDDEN:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    GNUNET_break (0);
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for coins history\n",
                (unsigned int) response_code,
                (int) rs.hr.ec);
    break;
  }
  if (NULL != rsh->cb)
  {
    rsh->cb (rsh->cb_cls,
             &rs);
    rsh->cb = NULL;
  }
  TALER_EXCHANGE_coins_history_cancel (rsh);
}


struct TALER_EXCHANGE_CoinsHistoryHandle *
TALER_EXCHANGE_coins_history (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_CoinPrivateKeyP *coin_priv,
  uint64_t start_off,
  TALER_EXCHANGE_CoinsHistoryCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_CoinsHistoryHandle *rsh;
  CURL *eh;
  char arg_str[sizeof (struct TALER_CoinPublicKeyP) * 2 + 64];
  struct curl_slist *job_headers;

  rsh = GNUNET_new (struct TALER_EXCHANGE_CoinsHistoryHandle);
  rsh->cb = cb;
  rsh->cb_cls = cb_cls;
  GNUNET_CRYPTO_eddsa_key_get_public (&coin_priv->eddsa_priv,
                                      &rsh->coin_pub.eddsa_pub);
  {
    char pub_str[sizeof (struct TALER_CoinPublicKeyP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &rsh->coin_pub,
      sizeof (rsh->coin_pub),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    if (0 != start_off)
      GNUNET_snprintf (arg_str,
                       sizeof (arg_str),
                       "coins/%s/history?start=%llu",
                       pub_str,
                       (unsigned long long) start_off);
    else
      GNUNET_snprintf (arg_str,
                       sizeof (arg_str),
                       "coins/%s/history",
                       pub_str);
  }
  rsh->url = TALER_url_join (url,
                             arg_str,
                             NULL);
  if (NULL == rsh->url)
  {
    GNUNET_free (rsh);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (rsh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (rsh->url);
    GNUNET_free (rsh);
    return NULL;
  }

  {
    struct TALER_CoinSignatureP coin_sig;
    char *sig_hdr;
    char *hdr;

    TALER_wallet_coin_history_sign (start_off,
                                    coin_priv,
                                    &coin_sig);

    sig_hdr = GNUNET_STRINGS_data_to_string_alloc (
      &coin_sig,
      sizeof (coin_sig));
    GNUNET_asprintf (&hdr,
                     "%s: %s",
                     TALER_COIN_HISTORY_SIGNATURE_HEADER,
                     sig_hdr);
    GNUNET_free (sig_hdr);
    job_headers = curl_slist_append (NULL,
                                     hdr);
    GNUNET_free (hdr);
    if (NULL == job_headers)
    {
      GNUNET_break (0);
      return NULL;
    }
  }

  rsh->keys = TALER_EXCHANGE_keys_incref (keys);
  rsh->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   job_headers,
                                   &handle_coins_history_finished,
                                   rsh);
  curl_slist_free_all (job_headers);
  return rsh;
}


void
TALER_EXCHANGE_coins_history_cancel (
  struct TALER_EXCHANGE_CoinsHistoryHandle *rsh)
{
  if (NULL != rsh->job)
  {
    GNUNET_CURL_job_cancel (rsh->job);
    rsh->job = NULL;
  }
  TALER_curl_easy_post_finished (&rsh->post_ctx);
  GNUNET_free (rsh->url);
  TALER_EXCHANGE_keys_decref (rsh->keys);
  GNUNET_free (rsh);
}


/* end of exchange_api_coins_history.c */
