/*
  This file is part of TALER
  Copyright (C) 2014-2018 Taler Systems SA

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
 * @brief Handle wire transfer /track/transfer requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_signatures.h"
#include "taler-exchange-httpd_keystate.h"
#include "taler-exchange-httpd_transfers_get.h"
#include "taler-exchange-httpd_responses.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"


/**
 * Detail for /wire/deposit response.
 */
struct TEH_TrackTransferDetail
{

  /**
   * We keep deposit details in a DLL.
   */
  struct TEH_TrackTransferDetail *next;

  /**
   * We keep deposit details in a DLL.
   */
  struct TEH_TrackTransferDetail *prev;

  /**
   * Hash of the proposal data.
   */
  struct GNUNET_HashCode h_contract_terms;

  /**
   * Coin's public key.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Total value of the coin.
   */
  struct TALER_Amount deposit_value;

  /**
   * Fees charged by the exchange for the deposit.
   */
  struct TALER_Amount deposit_fee;
};


/**
 * A merchant asked for transaction details about a wire transfer.
 * Provide them. Generates the 200 reply.
 *
 * @param connection connection to the client
 * @param total total amount that was transferred
 * @param merchant_pub public key of the merchant
 * @param h_wire destination account
 * @param wire_fee wire fee that was charged
 * @param exec_time execution time of the wire transfer
 * @param wdd_head linked list with details about the combined deposits
 * @return MHD result code
 */
static int
reply_track_transfer_details (struct MHD_Connection *connection,
                              const struct TALER_Amount *total,
                              const struct
                              TALER_MerchantPublicKeyP *merchant_pub,
                              const struct GNUNET_HashCode *h_wire,
                              const struct TALER_Amount *wire_fee,
                              struct GNUNET_TIME_Absolute exec_time,
                              const struct TEH_TrackTransferDetail *wdd_head)
{
  const struct TEH_TrackTransferDetail *wdd_pos;
  json_t *deposits;
  struct TALER_WireDepositDetailP dd;
  struct GNUNET_HashContext *hash_context;
  struct TALER_WireDepositDataPS wdp;
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;

  GNUNET_TIME_round_abs (&exec_time);
  deposits = json_array ();
  hash_context = GNUNET_CRYPTO_hash_context_start ();
  for (wdd_pos = wdd_head; NULL != wdd_pos; wdd_pos = wdd_pos->next)
  {
    dd.h_contract_terms = wdd_pos->h_contract_terms;
    dd.execution_time = GNUNET_TIME_absolute_hton (exec_time);
    dd.coin_pub = wdd_pos->coin_pub;
    TALER_amount_hton (&dd.deposit_value,
                       &wdd_pos->deposit_value);
    TALER_amount_hton (&dd.deposit_fee,
                       &wdd_pos->deposit_fee);
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &dd,
                                     sizeof (struct TALER_WireDepositDetailP));
    GNUNET_assert (0 ==
                   json_array_append_new (deposits,
                                          json_pack ("{s:o, s:o, s:o, s:o}",
                                                     "h_contract_terms",
                                                     GNUNET_JSON_from_data_auto (
                                                       &wdd_pos->
                                                       h_contract_terms),
                                                     "coin_pub",
                                                     GNUNET_JSON_from_data_auto (
                                                       &wdd_pos->coin_pub),
                                                     "deposit_value",
                                                     TALER_JSON_from_amount (
                                                       &wdd_pos->deposit_value),
                                                     "deposit_fee",
                                                     TALER_JSON_from_amount (
                                                       &wdd_pos->deposit_fee))));
  }
  wdp.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE_DEPOSIT);
  wdp.purpose.size = htonl (sizeof (struct TALER_WireDepositDataPS));
  TALER_amount_hton (&wdp.total,
                     total);
  TALER_amount_hton (&wdp.wire_fee,
                     wire_fee);
  wdp.merchant_pub = *merchant_pub;
  wdp.h_wire = *h_wire;
  GNUNET_CRYPTO_hash_context_finish (hash_context,
                                     &wdp.h_details);
  if (GNUNET_OK !=
      TEH_KS_sign (&wdp.purpose,
                   &pub,
                   &sig))
  {
    json_decref (deposits);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_BAD_CONFIGURATION,
                                       "no keys");
  }

  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_OK,
                                    "{s:o, s:o, s:o, s:o, s:o, s:o, s:o, s:o}",
                                    "total", TALER_JSON_from_amount (total),
                                    "wire_fee", TALER_JSON_from_amount (
                                      wire_fee),
                                    "merchant_pub",
                                    GNUNET_JSON_from_data_auto (
                                      merchant_pub),
                                    "h_wire", GNUNET_JSON_from_data_auto (
                                      h_wire),
                                    "execution_time",
                                    GNUNET_JSON_from_time_abs (exec_time),
                                    "deposits", deposits,
                                    "exchange_sig",
                                    GNUNET_JSON_from_data_auto (&sig),
                                    "exchange_pub",
                                    GNUNET_JSON_from_data_auto (&pub));
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
   * Which method was used to wire the funds?
   */
  char *wire_method;

  /**
   * Hash of the wire details of the merchant (identical for all
   * deposits), only valid if @e is_valid is #GNUNET_YES.
   */
  struct GNUNET_HashCode h_wire;

  /**
   * Wire fee applicable at @e exec_time.
   */
  struct TALER_Amount wire_fee;

  /**
   * Execution time of the wire transfer
   */
  struct GNUNET_TIME_Absolute exec_time;

  /**
   * Head of DLL with details for /wire/deposit response.
   */
  struct TEH_TrackTransferDetail *wdd_head;

  /**
   * Head of DLL with details for /wire/deposit response.
   */
  struct TEH_TrackTransferDetail *wdd_tail;

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
  int is_valid;

};


/**
 * Function called with the results of the lookup of the
 * transaction data for the given wire transfer identifier.
 *
 * @param cls our context for transmission
 * @param rowid which row in the DB is the information from (for diagnostics), ignored
 * @param merchant_pub public key of the merchant (should be same for all callbacks with the same @e cls)
 * @param h_wire hash of wire transfer details of the merchant (should be same for all callbacks with the same @e cls)
 * @param wire where the funds were sent
 * @param exec_time execution time of the wire transfer (should be same for all callbacks with the same @e cls)
 * @param h_contract_terms which proposal was this payment about
 * @param denom_pub denomination public key of the @a coin_pub (ignored)
 * @param coin_pub which public key was this payment about
 * @param deposit_value amount contributed by this coin in total
 * @param deposit_fee deposit fee charged by exchange for this coin
 */
static void
handle_transaction_data (void *cls,
                         uint64_t rowid,
                         const struct TALER_MerchantPublicKeyP *merchant_pub,
                         const struct GNUNET_HashCode *h_wire,
                         const json_t *wire,
                         struct GNUNET_TIME_Absolute exec_time,
                         const struct GNUNET_HashCode *h_contract_terms,
                         const struct TALER_DenominationPublicKey *denom_pub,
                         const struct TALER_CoinSpendPublicKeyP *coin_pub,
                         const struct TALER_Amount *deposit_value,
                         const struct TALER_Amount *deposit_fee)
{
  struct WtidTransactionContext *ctx = cls;
  struct TALER_Amount delta;
  struct TEH_TrackTransferDetail *wdd;
  char *wire_method;

  (void) rowid;
  (void) denom_pub;
  if (GNUNET_SYSERR == ctx->is_valid)
    return;
  if (NULL == (wire_method = TALER_JSON_wire_to_method (wire)))
  {
    GNUNET_break (0);
    ctx->is_valid = GNUNET_SYSERR;
    return;
  }
  if (GNUNET_NO == ctx->is_valid)
  {
    ctx->merchant_pub = *merchant_pub;
    ctx->h_wire = *h_wire;
    ctx->exec_time = exec_time;
    ctx->wire_method = wire_method;
    ctx->is_valid = GNUNET_YES;
    if (GNUNET_OK !=
        TALER_amount_subtract (&ctx->total,
                               deposit_value,
                               deposit_fee))
    {
      GNUNET_break (0);
      ctx->is_valid = GNUNET_SYSERR;
      return;
    }
  }
  else
  {
    if ( (0 != GNUNET_memcmp (&ctx->merchant_pub,
                              merchant_pub)) ||
         (0 != strcmp (wire_method,
                       ctx->wire_method)) ||
         (0 != GNUNET_memcmp (&ctx->h_wire,
                              h_wire)) )
    {
      GNUNET_break (0);
      ctx->is_valid = GNUNET_SYSERR;
      GNUNET_free (wire_method);
      return;
    }
    GNUNET_free (wire_method);
    if (GNUNET_OK !=
        TALER_amount_subtract (&delta,
                               deposit_value,
                               deposit_fee))
    {
      GNUNET_break (0);
      ctx->is_valid = GNUNET_SYSERR;
      return;
    }
    if (GNUNET_OK !=
        TALER_amount_add (&ctx->total,
                          &ctx->total,
                          &delta))
    {
      GNUNET_break (0);
      ctx->is_valid = GNUNET_SYSERR;
      return;
    }
  }
  wdd = GNUNET_new (struct TEH_TrackTransferDetail);
  wdd->deposit_value = *deposit_value;
  wdd->deposit_fee = *deposit_fee;
  wdd->h_contract_terms = *h_contract_terms;
  wdd->coin_pub = *coin_pub;
  GNUNET_CONTAINER_DLL_insert (ctx->wdd_head,
                               ctx->wdd_tail,
                               wdd);
}


/**
 * Execute a "/track/transfer".  Returns the transaction information
 * associated with the given wire transfer identifier.
 *
 * If it returns a non-error code, the transaction logic MUST
 * NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF
 * it returns the soft error code, the function MAY be called again to
 * retry and MUST not queue a MHD response.
 *
 * @param cls closure
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
track_transfer_transaction (void *cls,
                            struct MHD_Connection *connection,
                            struct TALER_EXCHANGEDB_Session *session,
                            int *mhd_ret)
{
  struct WtidTransactionContext *ctx = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_TIME_Absolute wire_fee_start_date;
  struct GNUNET_TIME_Absolute wire_fee_end_date;
  struct TALER_MasterSignatureP wire_fee_master_sig;
  struct TALER_Amount closing_fee;

  ctx->is_valid = GNUNET_NO;
  ctx->wdd_head = NULL;
  ctx->wdd_tail = NULL;
  ctx->wire_method = NULL;
  qs = TEH_plugin->lookup_wire_transfer (TEH_plugin->cls,
                                         session,
                                         &ctx->wtid,
                                         &handle_transaction_data,
                                         ctx);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_TRACK_TRANSFER_DB_FETCH_FAILED,
                                             "failed to fetch transaction data");
    }
    return qs;
  }
  if (GNUNET_SYSERR == ctx->is_valid)
  {
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_TRACK_TRANSFER_DB_INCONSISTENT,
                                           "exchange database internally inconsistent");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_NO == ctx->is_valid)
  {
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_TRACK_TRANSFER_WTID_NOT_FOUND,
                                           "wtid");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  qs = TEH_plugin->get_wire_fee (TEH_plugin->cls,
                                 session,
                                 ctx->wire_method,
                                 ctx->exec_time,
                                 &wire_fee_start_date,
                                 &wire_fee_end_date,
                                 &ctx->wire_fee,
                                 &closing_fee,
                                 &wire_fee_master_sig);
  if (0 >= qs)
  {
    if ( (GNUNET_DB_STATUS_HARD_ERROR == qs) ||
         (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS) )
    {
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_TRACK_TRANSFER_WIRE_FEE_NOT_FOUND,
                                             "did not find wire fee");
    }
    return qs;
  }
  if (GNUNET_OK !=
      TALER_amount_subtract (&ctx->total,
                             &ctx->total,
                             &ctx->wire_fee))
  {
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_TRACK_TRANSFER_WIRE_FEE_INCONSISTENT,
                                           "could not subtract wire fee");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Free data structure reachable from @a ctx, but not @a ctx itself.
 *
 * @param ctx context to free
 */
static void
free_ctx (struct WtidTransactionContext *ctx)
{
  struct TEH_TrackTransferDetail *wdd;

  while (NULL != (wdd = ctx->wdd_head))
  {
    GNUNET_CONTAINER_DLL_remove (ctx->wdd_head,
                                 ctx->wdd_tail,
                                 wdd);
    GNUNET_free (wdd);
  }
  GNUNET_free_non_null (ctx->wire_method);
}


/**
 * Handle a GET "/transfers/$WTID" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param args array of additional options (length: 1, just the wtid)
 * @return MHD result code
 */
int
TEH_TRACKING_handler_track_transfer (const struct TEH_RequestHandler *rh,
                                     struct MHD_Connection *connection,
                                     const char *const args[1])
{
  struct WtidTransactionContext ctx;
  int mhd_ret;

  (void) rh;
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
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_TRANSFERS_INVALID_WTID,
                                       "wire transfer identifier malformed");
  }
  if (GNUNET_OK !=
      TEH_DB_run_transaction (connection,
                              "run track transfer",
                              &mhd_ret,
                              &track_transfer_transaction,
                              &ctx))
  {
    free_ctx (&ctx);
    return mhd_ret;
  }
  mhd_ret = reply_track_transfer_details (connection,
                                          &ctx.total,
                                          &ctx.merchant_pub,
                                          &ctx.h_wire,
                                          &ctx.wire_fee,
                                          ctx.exec_time,
                                          ctx.wdd_head);
  free_ctx (&ctx);
  return mhd_ret;
}


/* end of taler-exchange-httpd_transfers_get.c */
