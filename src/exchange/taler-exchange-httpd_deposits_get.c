/*
  This file is part of TALER
  Copyright (C) 2014-2017, 2021 Taler Systems SA

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
 * @file taler-exchange-httpd_deposits_get.c
 * @brief Handle wire deposit tracking-related requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_signatures.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_deposits_get.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Closure for #handle_wtid_data.
 */
struct DepositWtidContext
{

  /**
   * Hash over the proposal data of the contract for which this deposit is made.
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct TALER_MerchantWireHashP h_wire;

  /**
   * The Merchant's public key.  The deposit inquiry request is to be
   * signed by the corresponding private key (using EdDSA).
   */
  struct TALER_MerchantPublicKeyP merchant;

  /**
   * The coin's public key.  This is the value that must have been
   * signed (blindly) by the Exchange.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Set by #handle_wtid data to the wire transfer ID.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * Set by #handle_wtid data to the coin's contribution to the wire transfer.
   */
  struct TALER_Amount coin_contribution;

  /**
   * Set by #handle_wtid data to the fee charged to the coin.
   */
  struct TALER_Amount coin_fee;

  /**
   * Set by #handle_wtid data to the wire transfer execution time.
   */
  struct GNUNET_TIME_Timestamp execution_time;

  /**
   * Set by #handle_wtid to the coin contribution to the transaction
   * (that is, @e coin_contribution minus @e coin_fee).
   */
  struct TALER_Amount coin_delta;

  /**
   * KYC status information for the receiving account.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * Set to #GNUNET_YES by #handle_wtid if the wire transfer is still pending
   * (and the above were not set).
   * Set to #GNUNET_SYSERR if there was a serious error.
   */
  enum GNUNET_GenericReturnValue pending;
};


/**
 * A merchant asked for details about a deposit.  Provide
 * them. Generates the 200 reply.
 *
 * @param connection connection to the client
 * @param ctx details to respond with
 * @return MHD result code
 */
static MHD_RESULT
reply_deposit_details (
  struct MHD_Connection *connection,
  const struct DepositWtidContext *ctx)
{
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  enum TALER_ErrorCode ec;

  if (TALER_EC_NONE !=
      (ec = TALER_exchange_online_confirm_wire_sign (
         &TEH_keys_exchange_sign_,
         &ctx->h_wire,
         &ctx->h_contract_terms,
         &ctx->wtid,
         &ctx->coin_pub,
         ctx->execution_time,
         &ctx->coin_delta,
         &pub,
         &sig)))
  {
    return TALER_MHD_reply_with_ec (connection,
                                    ec,
                                    NULL);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_data_auto ("wtid",
                                &ctx->wtid),
    GNUNET_JSON_pack_timestamp ("execution_time",
                                ctx->execution_time),
    TALER_JSON_pack_amount ("coin_contribution",
                            &ctx->coin_delta),
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &sig),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &pub));
}


/**
 * Execute a "deposits" GET.  Returns the transfer information
 * associated with the given deposit.
 *
 * If it returns a non-error code, the transaction logic MUST
 * NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF
 * it returns the soft error code, the function MAY be called again to
 * retry and MUST NOT queue a MHD response.
 *
 * @param cls closure of type `struct DepositWtidContext *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
deposits_get_transaction (void *cls,
                          struct MHD_Connection *connection,
                          MHD_RESULT *mhd_ret)
{
  struct DepositWtidContext *ctx = cls;
  enum GNUNET_DB_QueryStatus qs;
  bool pending;
  struct TALER_Amount fee;

  qs = TEH_plugin->lookup_transfer_by_deposit (TEH_plugin->cls,
                                               &ctx->h_contract_terms,
                                               &ctx->h_wire,
                                               &ctx->coin_pub,
                                               &ctx->merchant,
                                               &pending,
                                               &ctx->wtid,
                                               &ctx->execution_time,
                                               &ctx->coin_contribution,
                                               &fee,
                                               &ctx->kyc);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             NULL);
    }
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_EXCHANGE_DEPOSITS_GET_NOT_FOUND,
                                           NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  if (0 >
      TALER_amount_subtract (&ctx->coin_delta,
                             &ctx->coin_contribution,
                             &fee))
  {
    GNUNET_break (0);
    ctx->pending = GNUNET_SYSERR;
    return qs;
  }
  ctx->pending = (pending) ? GNUNET_YES : GNUNET_NO;
  return qs;
}


/**
 * Lookup and return the wire transfer identifier.
 *
 * @param connection the MHD connection to handle
 * @param ctx context of the signed request to execute
 * @return MHD result code
 */
static MHD_RESULT
handle_track_transaction_request (
  struct MHD_Connection *connection,
  struct DepositWtidContext *ctx)
{
  MHD_RESULT mhd_ret;

  if (GNUNET_OK !=
      TEH_DB_run_transaction (connection,
                              "handle deposits GET",
                              TEH_MT_REQUEST_OTHER,
                              &mhd_ret,
                              &deposits_get_transaction,
                              ctx))
    return mhd_ret;
  if (GNUNET_SYSERR == ctx->pending)
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_INVARIANT_FAILURE,
                                       "wire fees exceed aggregate in database");
  if (GNUNET_YES == ctx->pending)
    return TALER_MHD_REPLY_JSON_PACK (
      connection,
      MHD_HTTP_ACCEPTED,
      GNUNET_JSON_pack_allow_null (
        (0 == ctx->kyc.payment_target_uuid)
        ? GNUNET_JSON_pack_string ("legitimization_uuid",
                                   NULL)
        : GNUNET_JSON_pack_uint64 ("legitimization_uuid",
                                   ctx->kyc.payment_target_uuid)),
      GNUNET_JSON_pack_bool ("kyc_ok",
                             ctx->kyc.ok),
      GNUNET_JSON_pack_timestamp ("execution_time",
                                  ctx->execution_time));
  return reply_deposit_details (connection,
                                ctx);
}


MHD_RESULT
TEH_handler_deposits_get (struct TEH_RequestContext *rc,
                          const char *const args[4])
{
  enum GNUNET_GenericReturnValue res;
  struct TALER_MerchantSignatureP merchant_sig;
  struct DepositWtidContext ctx;

  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &ctx.h_wire,
                                     sizeof (ctx.h_wire)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_DEPOSITS_GET_INVALID_H_WIRE,
                                       args[0]);
  }
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[1],
                                     strlen (args[1]),
                                     &ctx.merchant,
                                     sizeof (ctx.merchant)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_DEPOSITS_GET_INVALID_MERCHANT_PUB,
                                       args[1]);
  }
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[2],
                                     strlen (args[2]),
                                     &ctx.h_contract_terms,
                                     sizeof (ctx.h_contract_terms)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_DEPOSITS_GET_INVALID_H_CONTRACT_TERMS,
                                       args[2]);
  }
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[3],
                                     strlen (args[3]),
                                     &ctx.coin_pub,
                                     sizeof (ctx.coin_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_DEPOSITS_GET_INVALID_COIN_PUB,
                                       args[3]);
  }
  res = TALER_MHD_parse_request_arg_data (rc->connection,
                                          "merchant_sig",
                                          &merchant_sig,
                                          sizeof (merchant_sig));
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* internal error */
  if (GNUNET_NO == res)
    return MHD_YES; /* parse error */
  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  {
    if (GNUNET_OK !=
        TALER_merchant_deposit_verify (&ctx.merchant,
                                       &ctx.coin_pub,
                                       &ctx.h_contract_terms,
                                       &ctx.h_wire,
                                       &merchant_sig))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_FORBIDDEN,
                                         TALER_EC_EXCHANGE_DEPOSITS_GET_MERCHANT_SIGNATURE_INVALID,
                                         NULL);
    }
  }

  return handle_track_transaction_request (rc->connection,
                                           &ctx);
}


/* end of taler-exchange-httpd_deposits_get.c */
