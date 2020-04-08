/*
  This file is part of TALER
  Copyright (C) 2014-2017 Taler Systems SA

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
#include "taler-exchange-httpd_keystate.h"
#include "taler-exchange-httpd_deposits_get.h"
#include "taler-exchange-httpd_responses.h"


/**
 * A merchant asked for details about a deposit.  Provide
 * them. Generates the 200 reply.
 *
 * @param connection connection to the client
 * @param h_contract_terms hash of the contract
 * @param h_wire hash of wire account details
 * @param coin_pub public key of the coin
 * @param coin_contribution how much did the coin we asked about
 *        contribute to the total transfer value? (deposit value minus fee)
 * @param wtid raw wire transfer identifier
 * @param exec_time execution time of the wire transfer
 * @return MHD result code
 */
static int
reply_deposit_details (struct MHD_Connection *connection,
                       const struct GNUNET_HashCode *h_contract_terms,
                       const struct GNUNET_HashCode *h_wire,
                       const struct TALER_CoinSpendPublicKeyP *coin_pub,
                       const struct TALER_Amount *coin_contribution,
                       const struct TALER_WireTransferIdentifierRawP *wtid,
                       struct GNUNET_TIME_Absolute exec_time)
{
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  struct TALER_ConfirmWirePS cw = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE),
    .purpose.size = htonl (sizeof (cw)),
    .h_wire = *h_wire,
    .h_contract_terms = *h_contract_terms,
    .wtid = *wtid,
    .coin_pub = *coin_pub,
    .execution_time = GNUNET_TIME_absolute_hton (exec_time)
  };

  TALER_amount_hton (&cw.coin_contribution,
                     coin_contribution);
  if (GNUNET_OK !=
      TEH_KS_sign (&cw,
                   &pub,
                   &sig))
  {
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_BAD_CONFIGURATION,
                                       "no keys");
  }
  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_OK,
                                    "{s:o, s:o, s:o, s:o, s:o}",
                                    "wtid", GNUNET_JSON_from_data_auto (
                                      wtid),
                                    "execution_time",
                                    GNUNET_JSON_from_time_abs (exec_time),
                                    "coin_contribution",
                                    TALER_JSON_from_amount (
                                      coin_contribution),
                                    "exchange_sig",
                                    GNUNET_JSON_from_data_auto (&sig),
                                    "exchange_pub",
                                    GNUNET_JSON_from_data_auto (&pub));
}


/**
 * Closure for #handle_wtid_data.
 */
struct DepositWtidContext
{

  /**
   * Deposit details.
   */
  const struct TALER_DepositTrackPS *tps;

  /**
   * Public key of the merchant.
   */
  const struct TALER_MerchantPublicKeyP *merchant_pub;

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
  struct GNUNET_TIME_Absolute execution_time;

  /**
   * Set by #handle_wtid to the coin contribution to the transaction
   * (that is, @e coin_contribution minus @e coin_fee).
   */
  struct TALER_Amount coin_delta;

  /**
   * Set to #GNUNET_YES by #handle_wtid if the wire transfer is still pending
   * (and the above were not set).
   * Set to #GNUNET_SYSERR if there was a serious error.
   */
  int pending;
};


/**
 * Function called with the results of the lookup of the
 * wire transfer identifier information.
 *
 * @param cls our context for transmission, a `struct DepositWtidContext *`
 * @param wtid raw wire transfer identifier, NULL
 *         if the transaction was not yet done
 * @param coin_contribution how much did the coin we asked about
 *        contribute to the total transfer value? (deposit value including fee)
 * @param coin_fee how much did the exchange charge for the deposit fee
 * @param execution_time when was the transaction done, or
 *         when we expect it to be done (if @a wtid was NULL);
 *         #GNUNET_TIME_UNIT_FOREVER_ABS if the /deposit is unknown
 *         to the exchange
 */
static void
handle_wtid_data (void *cls,
                  const struct TALER_WireTransferIdentifierRawP *wtid,
                  const struct TALER_Amount *coin_contribution,
                  const struct TALER_Amount *coin_fee,
                  struct GNUNET_TIME_Absolute execution_time)
{
  struct DepositWtidContext *ctx = cls;

  if (NULL == wtid)
  {
    ctx->pending = GNUNET_YES;
    ctx->execution_time = execution_time;
    return;
  }
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&ctx->coin_delta,
                             coin_contribution,
                             coin_fee))
  {
    GNUNET_break (0);
    ctx->pending = GNUNET_SYSERR;
    return;
  }
  ctx->wtid = *wtid;
  ctx->execution_time = execution_time;
  ctx->coin_contribution = *coin_contribution;
  ctx->coin_fee = *coin_fee;
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
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
deposits_get_transaction (void *cls,
                          struct MHD_Connection *connection,
                          struct TALER_EXCHANGEDB_Session *session,
                          int *mhd_ret)
{
  struct DepositWtidContext *ctx = cls;
  enum GNUNET_DB_QueryStatus qs;

  qs = TEH_plugin->lookup_transfer_by_deposit (TEH_plugin->cls,
                                               session,
                                               &ctx->tps->h_contract_terms,
                                               &ctx->tps->h_wire,
                                               &ctx->tps->coin_pub,
                                               ctx->merchant_pub,
                                               &handle_wtid_data,
                                               ctx);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_DEPOSITS_GET_DB_FETCH_FAILED,
                                             "failed to fetch transaction data");
    }
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_DEPOSITS_GET_NOT_FOUND,
                                           "transaction unknown");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return qs;
}


/**
 * Lookup and return the wire transfer identifier.
 *
 * @param connection the MHD connection to handle
 * @param tps signed request to execute
 * @param merchant_pub public key from the merchant
 * @return MHD result code
 */
static int
handle_track_transaction_request (
  struct MHD_Connection *connection,
  const struct TALER_DepositTrackPS *tps,
  const struct TALER_MerchantPublicKeyP *merchant_pub)
{
  int mhd_ret;
  struct DepositWtidContext ctx = {
    .pending = GNUNET_NO,
    .tps = tps,
    .merchant_pub = merchant_pub
  };

  if (GNUNET_OK !=
      TEH_DB_run_transaction (connection,
                              "handle deposits GET",
                              &mhd_ret,
                              &deposits_get_transaction,
                              &ctx))
    return mhd_ret;
  if (GNUNET_YES == ctx.pending)
    return TALER_MHD_reply_json_pack (connection,
                                      MHD_HTTP_ACCEPTED,
                                      "{s:o}",
                                      "execution_time",
                                      GNUNET_JSON_from_time_abs (
                                        ctx.execution_time));
  if (GNUNET_SYSERR == ctx.pending)
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_DEPOSITS_GET_DB_FEE_INCONSISTENT,
                                       "fees are inconsistent");
  return reply_deposit_details (connection,
                                &tps->h_contract_terms,
                                &tps->h_wire,
                                &tps->coin_pub,
                                &ctx.coin_delta,
                                &ctx.wtid,
                                ctx.execution_time);
}


/**
 * Handle a "/deposits/$H_WIRE/$MERCHANT_PUB/$H_CONTRACT_TERMS/$COIN_PUB"
 * request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param args array of additional options (length: 4, contains:
 *      h_wire, merchant_pub, h_contract_terms and coin_pub)
 * @return MHD result code
  */
int
TEH_handler_deposits_get (const struct TEH_RequestHandler *rh,
                          struct MHD_Connection *connection,
                          const char *const args[4])
{
  int res;
  struct TALER_MerchantSignatureP merchant_sig;
  struct TALER_DepositTrackPS tps = {
    .purpose.size = htonl (sizeof (tps)),
    .purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_TRACK_TRANSACTION)
  };

  (void) rh;
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &tps.h_wire,
                                     sizeof (tps.h_wire)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_DEPOSITS_INVALID_H_WIRE,
                                       "wire hash malformed");
  }
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[1],
                                     strlen (args[1]),
                                     &tps.merchant,
                                     sizeof (tps.merchant)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_DEPOSITS_INVALID_MERCHANT_PUB,
                                       "merchant public key malformed");
  }
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[2],
                                     strlen (args[2]),
                                     &tps.h_contract_terms,
                                     sizeof (tps.h_contract_terms)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_DEPOSITS_INVALID_H_CONTRACT_TERMS,
                                       "contract terms hash malformed");
  }
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[3],
                                     strlen (args[3]),
                                     &tps.coin_pub,
                                     sizeof (tps.coin_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_DEPOSITS_INVALID_COIN_PUB,
                                       "coin public key malformed");
  }
  res = TALER_MHD_parse_request_arg_data (connection,
                                          "merchant_sig",
                                          &merchant_sig,
                                          sizeof (merchant_sig));
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* internal error */
  if (GNUNET_NO == res)
    return MHD_YES; /* parse error */
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MERCHANT_TRACK_TRANSACTION,
                                  &tps,
                                  &merchant_sig.eddsa_sig,
                                  &tps.merchant.eddsa_pub))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_DEPOSITS_GET_MERCHANT_SIGNATURE_INVALID,
                                       "merchant_sig");
  }

  return handle_track_transaction_request (connection,
                                           &tps,
                                           &tps.merchant);
}


/* end of taler-exchange-httpd_deposits_get.c */
