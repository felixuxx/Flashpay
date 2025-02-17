/*
  This file is part of TALER
  Copyright (C) 2014-2018, 2021 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_transfers_get.c
 * @brief Handle wire transfer(s) GET requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_signatures.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_transfers_get.h"
#include "taler-exchange-httpd_responses.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"


/**
 * Information about one of the transactions that was
 * aggregated, to be returned in the /transfers response.
 */
struct AggregatedDepositDetail
{

  /**
   * We keep deposit details in a DLL.
   */
  struct AggregatedDepositDetail *next;

  /**
   * We keep deposit details in a DLL.
   */
  struct AggregatedDepositDetail *prev;

  /**
   * Hash of the contract terms.
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Coin's public key of the deposited coin.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Total value of the coin in the deposit (after
   * refunds).
   */
  struct TALER_Amount deposit_value;

  /**
   * Fees charged by the exchange for the deposit of this coin (possibly after reduction due to refunds).
   */
  struct TALER_Amount deposit_fee;

  /**
   * Total amount refunded for this coin.
   */
  struct TALER_Amount refund_total;
};


/**
 * A merchant asked for transaction details about a wire transfer.
 * Provide them. Generates the 200 reply.
 *
 * @param connection connection to the client
 * @param total total amount that was transferred
 * @param merchant_pub public key of the merchant
 * @param payto_uri destination account
 * @param wire_fee wire fee that was charged
 * @param exec_time execution time of the wire transfer
 * @param wdd_head linked list with details about the combined deposits
 * @return MHD result code
 */
static MHD_RESULT
reply_transfer_details (struct MHD_Connection *connection,
                        const struct TALER_Amount *total,
                        const struct TALER_MerchantPublicKeyP *merchant_pub,
                        const struct TALER_FullPayto payto_uri,
                        const struct TALER_Amount *wire_fee,
                        struct GNUNET_TIME_Timestamp exec_time,
                        const struct AggregatedDepositDetail *wdd_head)
{
  json_t *deposits;
  struct GNUNET_HashContext *hash_context;
  struct GNUNET_HashCode h_details;
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  struct TALER_FullPaytoHashP h_payto;

  deposits = json_array ();
  GNUNET_assert (NULL != deposits);
  hash_context = GNUNET_CRYPTO_hash_context_start ();
  for (const struct AggregatedDepositDetail *wdd_pos = wdd_head;
       NULL != wdd_pos;
       wdd_pos = wdd_pos->next)
  {
    TALER_exchange_online_wire_deposit_append (hash_context,
                                               &wdd_pos->h_contract_terms,
                                               exec_time,
                                               &wdd_pos->coin_pub,
                                               &wdd_pos->deposit_value,
                                               &wdd_pos->deposit_fee);
    if (0 !=
        json_array_append_new (
          deposits,
          GNUNET_JSON_PACK (
            GNUNET_JSON_pack_data_auto ("h_contract_terms",
                                        &wdd_pos->h_contract_terms),
            GNUNET_JSON_pack_data_auto ("coin_pub",
                                        &wdd_pos->coin_pub),

            GNUNET_JSON_pack_allow_null (
              TALER_JSON_pack_amount ("refund_total",
                                      TALER_amount_is_zero (
                                        &wdd_pos->refund_total)
                                      ? NULL
                                      : &wdd_pos->refund_total)),
            TALER_JSON_pack_amount ("deposit_value",
                                    &wdd_pos->deposit_value),
            TALER_JSON_pack_amount ("deposit_fee",
                                    &wdd_pos->deposit_fee))))
    {
      json_decref (deposits);
      GNUNET_CRYPTO_hash_context_abort (hash_context);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_JSON_ALLOCATION_FAILURE,
                                         "json_array_append_new() failed");
    }
  }
  GNUNET_CRYPTO_hash_context_finish (hash_context,
                                     &h_details);
  {
    enum TALER_ErrorCode ec;

    if (TALER_EC_NONE !=
        (ec = TALER_exchange_online_wire_deposit_sign (
           &TEH_keys_exchange_sign_,
           total,
           wire_fee,
           merchant_pub,
           payto_uri,
           &h_details,
           &pub,
           &sig)))
    {
      json_decref (deposits);
      return TALER_MHD_reply_with_ec (connection,
                                      ec,
                                      NULL);
    }
  }

  TALER_full_payto_hash (payto_uri,
                         &h_payto);
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    TALER_JSON_pack_amount ("total",
                            total),
    TALER_JSON_pack_amount ("wire_fee",
                            wire_fee),
    GNUNET_JSON_pack_data_auto ("merchant_pub",
                                merchant_pub),
    GNUNET_JSON_pack_data_auto ("h_payto",
                                &h_payto),
    GNUNET_JSON_pack_timestamp ("execution_time",
                                exec_time),
    GNUNET_JSON_pack_array_steal ("deposits",
                                  deposits),
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &sig),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &pub));
}


/**
 * Closure for #handle_transaction_data.
 */
struct WtidTransactionContext
{

  /**
   * Identifier of the wire transfer to track.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * Total amount of the wire transfer, as calculated by
   * summing up the individual amounts. To be rounded down
   * to calculate the real transfer amount at the end.
   * Only valid if @e is_valid is #GNUNET_YES.
   */
  struct TALER_Amount total;

  /**
   * Public key of the merchant, only valid if @e is_valid
   * is #GNUNET_YES.
   */
  struct TALER_MerchantPublicKeyP merchant_pub;

  /**
   * Wire fees applicable at @e exec_time.
   */
  struct TALER_WireFeeSet fees;

  /**
   * Execution time of the wire transfer
   */
  struct GNUNET_TIME_Timestamp exec_time;

  /**
   * Head of DLL with deposit details for transfers GET response.
   */
  struct AggregatedDepositDetail *wdd_head;

  /**
   * Tail of DLL with deposit details for transfers GET response.
   */
  struct AggregatedDepositDetail *wdd_tail;

  /**
   * Where were the funds wired?
   */
  struct TALER_FullPayto payto_uri;

  /**
   * JSON array with details about the individual deposits.
   */
  json_t *deposits;

  /**
   * Initially #GNUNET_NO, if we found no deposits so far.  Set to
   * #GNUNET_YES if we got transaction data, and the database replies
   * remained consistent with respect to @e merchant_pub and @e h_wire
   * (as they should).  Set to #GNUNET_SYSERR if we encountered an
   * internal error.
   */
  enum GNUNET_GenericReturnValue is_valid;

};


/**
 * Callback that totals up the applicable refunds.
 *
 * @param cls a `struct TALER_Amount` where we keep the total
 * @param amount_with_fee amount being refunded
 */
static enum GNUNET_GenericReturnValue
add_refunds (void *cls,
             const struct TALER_Amount *amount_with_fee)

{
  struct TALER_Amount *total = cls;

  if (0 >
      TALER_amount_add (total,
                        total,
                        amount_with_fee))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Function called with the results of the lookup of the individual deposits
 * that were aggregated for the given wire transfer.
 *
 * @param cls our context for transmission
 * @param rowid which row in the DB is the information from (for diagnostics), ignored
 * @param merchant_pub public key of the merchant (should be same for all callbacks with the same @e cls)
 * @param account_payto_uri where the funds were sent
 * @param h_payto hash over @a account_payto_uri as it is in the DB
 * @param exec_time execution time of the wire transfer (should be same for all callbacks with the same @e cls)
 * @param h_contract_terms which proposal was this payment about
 * @param denom_pub denomination public key of the @a coin_pub (ignored)
 * @param coin_pub which public key was this payment about
 * @param deposit_value amount contributed by this coin in total (including fee)
 * @param deposit_fee deposit fee charged by exchange for this coin
 */
static void
handle_deposit_data (
  void *cls,
  uint64_t rowid,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_FullPayto account_payto_uri,
  const struct TALER_FullPaytoHashP *h_payto,
  struct GNUNET_TIME_Timestamp exec_time,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_Amount *deposit_value,
  const struct TALER_Amount *deposit_fee)
{
  struct WtidTransactionContext *ctx = cls;
  struct TALER_Amount total_refunds;
  struct TALER_Amount dval;
  struct TALER_Amount dfee;
  enum GNUNET_DB_QueryStatus qs;

  (void) rowid;
  (void) denom_pub;
  (void) h_payto;
  if (GNUNET_SYSERR == ctx->is_valid)
    return;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (deposit_value->currency,
                                        &total_refunds));
  qs = TEH_plugin->select_refunds_by_coin (TEH_plugin->cls,
                                           coin_pub,
                                           merchant_pub,
                                           h_contract_terms,
                                           &add_refunds,
                                           &total_refunds);
  if (qs < 0)
  {
    GNUNET_break (0);
    ctx->is_valid = GNUNET_SYSERR;
    return;
  }
  if (1 ==
      TALER_amount_cmp (&total_refunds,
                        deposit_value))
  {
    /* Refunds exceeded total deposit? not OK! */
    GNUNET_break (0);
    ctx->is_valid = GNUNET_SYSERR;
    return;
  }
  if (0 ==
      TALER_amount_cmp (&total_refunds,
                        deposit_value))
  {
    /* total_refunds == deposit_value;
       in this case, the total contributed to the
       wire transfer is zero (as are fees) */
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (deposit_value->currency,
                                          &dval));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (deposit_value->currency,
                                          &dfee));

  }
  else
  {
    /* Compute deposit value by subtracting refunds */
    GNUNET_assert (0 <
                   TALER_amount_subtract (&dval,
                                          deposit_value,
                                          &total_refunds));
    if (-1 ==
        TALER_amount_cmp (&dval,
                          deposit_fee))
    {
      /* dval < deposit_fee, so after refunds less than
         the deposit fee remains; reduce deposit fee to
         the remaining value of the coin */
      dfee = dval;
    }
    else
    {
      /* Partial refund, deposit fee remains */
      dfee = *deposit_fee;
    }
  }

  if (GNUNET_NO == ctx->is_valid)
  {
    /* First one we encounter, setup general information in 'ctx' */
    ctx->merchant_pub = *merchant_pub;
    ctx->payto_uri.full_payto = GNUNET_strdup (account_payto_uri.full_payto);
    ctx->exec_time = exec_time;
    ctx->is_valid = GNUNET_YES;
    if (0 >
        TALER_amount_subtract (&ctx->total,
                               &dval,
                               &dfee))
    {
      GNUNET_break (0);
      ctx->is_valid = GNUNET_SYSERR;
      return;
    }
  }
  else
  {
    struct TALER_Amount delta;

    /* Subsequent data, check general information matches that in 'ctx';
       (it should, otherwise the deposits should not have been aggregated) */
    if ( (0 != GNUNET_memcmp (&ctx->merchant_pub,
                              merchant_pub)) ||
         (0 != TALER_full_payto_cmp (account_payto_uri,
                                     ctx->payto_uri)) )
    {
      GNUNET_break (0);
      ctx->is_valid = GNUNET_SYSERR;
      return;
    }
    if (0 >
        TALER_amount_subtract (&delta,
                               &dval,
                               &dfee))
    {
      GNUNET_break (0);
      ctx->is_valid = GNUNET_SYSERR;
      return;
    }
    if (0 >
        TALER_amount_add (&ctx->total,
                          &ctx->total,
                          &delta))
    {
      GNUNET_break (0);
      ctx->is_valid = GNUNET_SYSERR;
      return;
    }
  }

  {
    struct AggregatedDepositDetail *wdd;

    wdd = GNUNET_new (struct AggregatedDepositDetail);
    wdd->deposit_value = dval;
    wdd->deposit_fee = dfee;
    wdd->refund_total = total_refunds;
    wdd->h_contract_terms = *h_contract_terms;
    wdd->coin_pub = *coin_pub;
    GNUNET_CONTAINER_DLL_insert (ctx->wdd_head,
                                 ctx->wdd_tail,
                                 wdd);
  }
}


/**
 * Free data structure reachable from @a ctx, but not @a ctx itself.
 *
 * @param ctx context to free
 */
static void
free_ctx (struct WtidTransactionContext *ctx)
{
  struct AggregatedDepositDetail *wdd;

  while (NULL != (wdd = ctx->wdd_head))
  {
    GNUNET_CONTAINER_DLL_remove (ctx->wdd_head,
                                 ctx->wdd_tail,
                                 wdd);
    GNUNET_free (wdd);
  }
  GNUNET_free (ctx->payto_uri.full_payto);
}


/**
 * Execute a "/transfers" GET operation.  Returns the deposit details of the
 * deposits that were aggregated to create the given wire transfer.
 *
 * If it returns a non-error code, the transaction logic MUST
 * NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF
 * it returns the soft error code, the function MAY be called again to
 * retry and MUST not queue a MHD response.
 *
 * @param cls closure
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
get_transfer_deposits (void *cls,
                       struct MHD_Connection *connection,
                       MHD_RESULT *mhd_ret)
{
  struct WtidTransactionContext *ctx = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_TIME_Timestamp wire_fee_start_date;
  struct GNUNET_TIME_Timestamp wire_fee_end_date;
  struct TALER_MasterSignatureP wire_fee_master_sig;

  /* resetting to NULL/0 in case transaction was repeated after
     serialization failure */
  free_ctx (ctx);
  qs = TEH_plugin->lookup_wire_transfer (TEH_plugin->cls,
                                         &ctx->wtid,
                                         &handle_deposit_data,
                                         ctx);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             "wire transfer");
    }
    return qs;
  }
  if (GNUNET_SYSERR == ctx->is_valid)
  {
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_INVARIANT_FAILURE,
                                           "wire history malformed");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_NO == ctx->is_valid)
  {
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_EXCHANGE_TRANSFERS_GET_WTID_NOT_FOUND,
                                           NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  {
    char *wire_method;

    wire_method = TALER_payto_get_method (ctx->payto_uri.full_payto);
    if (NULL == wire_method)
    {
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_INVARIANT_FAILURE,
                                             "payto:// without wire method encountered");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    qs = TEH_plugin->get_wire_fee (TEH_plugin->cls,
                                   wire_method,
                                   ctx->exec_time,
                                   &wire_fee_start_date,
                                   &wire_fee_end_date,
                                   &ctx->fees,
                                   &wire_fee_master_sig);
    GNUNET_free (wire_method);
  }
  if (0 >= qs)
  {
    if ( (GNUNET_DB_STATUS_HARD_ERROR == qs) ||
         (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs) )
    {
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_EXCHANGE_TRANSFERS_GET_WIRE_FEE_NOT_FOUND,
                                             NULL);
    }
    return qs;
  }
  if (0 >
      TALER_amount_subtract (&ctx->total,
                             &ctx->total,
                             &ctx->fees.wire))
  {
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_EXCHANGE_TRANSFERS_GET_WIRE_FEE_INCONSISTENT,
                                           NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


MHD_RESULT
TEH_handler_transfers_get (struct TEH_RequestContext *rc,
                           const char *const args[1])
{
  struct WtidTransactionContext ctx;
  MHD_RESULT mhd_ret;

  memset (&ctx,
          0,
          sizeof (ctx));
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &ctx.wtid,
                                     sizeof (ctx.wtid)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_TRANSFERS_GET_WTID_MALFORMED,
                                       args[0]);
  }
  if (GNUNET_OK !=
      TEH_DB_run_transaction (rc->connection,
                              "run transfers GET",
                              TEH_MT_REQUEST_OTHER,
                              &mhd_ret,
                              &get_transfer_deposits,
                              &ctx))
  {
    free_ctx (&ctx);
    return mhd_ret;
  }
  mhd_ret = reply_transfer_details (rc->connection,
                                    &ctx.total,
                                    &ctx.merchant_pub,
                                    ctx.payto_uri,
                                    &ctx.fees.wire,
                                    ctx.exec_time,
                                    ctx.wdd_head);
  free_ctx (&ctx);
  return mhd_ret;
}


/* end of taler-exchange-httpd_transfers_get.c */
