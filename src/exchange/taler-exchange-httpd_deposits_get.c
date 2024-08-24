/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
#include "taler_dbevents.h"
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
   * Kept in a DLL.
   */
  struct DepositWtidContext *next;

  /**
   * Kept in a DLL.
   */
  struct DepositWtidContext *prev;

  /**
   * Context for the request we are processing.
   */
  struct TEH_RequestContext *rc;

  /**
   * Subscription for the database event we are waiting for.
   */
  struct GNUNET_DB_EventHandler *eh;

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
   * Public key for KYC operations on the target bank
   * account for the wire transfer. All zero if no
   * public key is accepted yet. In that case, the
   * client should use the @e merchant public key for
   * the KYC auth wire transfer.
   */
  union TALER_AccountPublicKeyP account_pub;

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
   * Signature by the merchant.
   */
  struct TALER_MerchantSignatureP merchant_sig;

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
   * Timeout of the request, for long-polling.
   */
  struct GNUNET_TIME_Absolute timeout;

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

  /**
   * #GNUNET_YES if we were suspended, #GNUNET_SYSERR
   * if we were woken up due to shutdown.
   */
  enum GNUNET_GenericReturnValue suspended;
};


/**
 * Head of DLL of suspended requests.
 */
static struct DepositWtidContext *dwc_head;

/**
 * Tail of DLL of suspended requests.
 */
static struct DepositWtidContext *dwc_tail;


void
TEH_deposits_get_cleanup ()
{
  struct DepositWtidContext *n;

  for (struct DepositWtidContext *ctx = dwc_head;
       NULL != ctx;
       ctx = n)
  {
    n = ctx->next;
    GNUNET_assert (GNUNET_YES == ctx->suspended);
    ctx->suspended = GNUNET_SYSERR;
    MHD_resume_connection (ctx->rc->connection);
    GNUNET_CONTAINER_DLL_remove (dwc_head,
                                 dwc_tail,
                                 ctx);
  }
}


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
    GNUNET_break (0);
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

  qs = TEH_plugin->lookup_transfer_by_deposit (
    TEH_plugin->cls,
    &ctx->h_contract_terms,
    &ctx->h_wire,
    &ctx->coin_pub,
    &ctx->merchant,
    &pending,
    &ctx->wtid,
    &ctx->execution_time,
    &ctx->coin_contribution,
    &fee,
    &ctx->kyc,
    &ctx->account_pub);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_DB_FETCH_FAILED,
        NULL);
    }
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    *mhd_ret = TALER_MHD_reply_with_error (
      connection,
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
 * Function called on events received from Postgres.
 * Wakes up long pollers.
 *
 * @param cls the `struct DepositWtidContext *`
 * @param extra additional event data provided
 * @param extra_size number of bytes in @a extra
 */
static void
db_event_cb (void *cls,
             const void *extra,
             size_t extra_size)
{
  struct DepositWtidContext *ctx = cls;
  struct GNUNET_AsyncScopeSave old_scope;

  (void) extra;
  (void) extra_size;
  if (GNUNET_YES != ctx->suspended)
    return; /* might get multiple wake-up events */
  GNUNET_CONTAINER_DLL_remove (dwc_head,
                               dwc_tail,
                               ctx);
  GNUNET_async_scope_enter (&ctx->rc->async_scope_id,
                            &old_scope);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Resuming request handling\n");
  TEH_check_invariants ();
  ctx->suspended = GNUNET_NO;
  MHD_resume_connection (ctx->rc->connection);
  TALER_MHD_daemon_trigger ();
  TEH_check_invariants ();
  GNUNET_async_scope_restore (&old_scope);
}


/**
 * Lookup and return the wire transfer identifier.
 *
 * @param ctx context of the signed request to execute
 * @return MHD result code
 */
static MHD_RESULT
handle_track_transaction_request (
  struct DepositWtidContext *ctx)
{
  struct MHD_Connection *connection = ctx->rc->connection;

  if ( (GNUNET_TIME_absolute_is_future (ctx->timeout)) &&
       (NULL == ctx->eh) )
  {
    struct TALER_CoinDepositEventP rep = {
      .header.size = htons (sizeof (rep)),
      .header.type = htons (TALER_DBEVENT_EXCHANGE_DEPOSIT_STATUS_CHANGED),
      .merchant_pub = ctx->merchant
    };

    ctx->eh = TEH_plugin->event_listen (
      TEH_plugin->cls,
      GNUNET_TIME_absolute_get_remaining (ctx->timeout),
      &rep.header,
      &db_event_cb,
      ctx);
    GNUNET_break (NULL != ctx->eh);
  }
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
  }
  if (GNUNET_SYSERR == ctx->pending)
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_INTERNAL_SERVER_ERROR,
      TALER_EC_GENERIC_DB_INVARIANT_FAILURE,
      "wire fees exceed aggregate in database");
  if (GNUNET_YES == ctx->pending)
  {
    if ( (GNUNET_TIME_absolute_is_future (ctx->timeout)) &&
         (GNUNET_NO == ctx->suspended) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Suspending request handling\n");
      GNUNET_CONTAINER_DLL_insert (dwc_head,
                                   dwc_tail,
                                   ctx);
      ctx->suspended = GNUNET_YES;
      MHD_suspend_connection (connection);
      return MHD_YES;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC required with row %llu\n",
                (unsigned long long) ctx->kyc.requirement_row);
    return TALER_MHD_REPLY_JSON_PACK (
      connection,
      MHD_HTTP_ACCEPTED,
      GNUNET_JSON_pack_allow_null (
        (0 == ctx->kyc.requirement_row)
        ? GNUNET_JSON_pack_string ("requirement_row",
                                   NULL)
        : GNUNET_JSON_pack_uint64 ("requirement_row",
                                   ctx->kyc.requirement_row)),
      GNUNET_JSON_pack_allow_null (
        (GNUNET_is_zero (&ctx->account_pub))
        ? GNUNET_JSON_pack_string ("account_pub",
                                   NULL)
        : GNUNET_JSON_pack_data_auto ("account_pub",
                                      &ctx->account_pub)),
      GNUNET_JSON_pack_bool ("kyc_ok",
                             ctx->kyc.ok),
      GNUNET_JSON_pack_timestamp ("execution_time",
                                  ctx->execution_time));
  }
  return reply_deposit_details (connection,
                                ctx);
}


/**
 * Function called to clean up a context.
 *
 * @param rc request context with data to clean up
 */
static void
dwc_cleaner (struct TEH_RequestContext *rc)
{
  struct DepositWtidContext *ctx = rc->rh_ctx;

  GNUNET_assert (GNUNET_NO == ctx->suspended);
  if (NULL != ctx->eh)
  {
    TEH_plugin->event_listen_cancel (TEH_plugin->cls,
                                     ctx->eh);
    ctx->eh = NULL;
  }
  GNUNET_free (ctx);
}


MHD_RESULT
TEH_handler_deposits_get (struct TEH_RequestContext *rc,
                          const char *const args[4])
{
  struct DepositWtidContext *ctx = rc->rh_ctx;

  if (NULL == ctx)
  {
    ctx = GNUNET_new (struct DepositWtidContext);
    ctx->rc = rc;
    rc->rh_ctx = ctx;
    rc->rh_cleaner = &dwc_cleaner;

    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[0],
                                       strlen (args[0]),
                                       &ctx->h_wire,
                                       sizeof (ctx->h_wire)))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_EXCHANGE_DEPOSITS_GET_INVALID_H_WIRE,
        args[0]);
    }
    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[1],
                                       strlen (args[1]),
                                       &ctx->merchant,
                                       sizeof (ctx->merchant)))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_EXCHANGE_DEPOSITS_GET_INVALID_MERCHANT_PUB,
        args[1]);
    }
    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[2],
                                       strlen (args[2]),
                                       &ctx->h_contract_terms,
                                       sizeof (ctx->h_contract_terms)))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_EXCHANGE_DEPOSITS_GET_INVALID_H_CONTRACT_TERMS,
        args[2]);
    }
    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[3],
                                       strlen (args[3]),
                                       &ctx->coin_pub,
                                       sizeof (ctx->coin_pub)))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_EXCHANGE_DEPOSITS_GET_INVALID_COIN_PUB,
        args[3]);
    }
    TALER_MHD_parse_request_arg_auto_t (rc->connection,
                                        "merchant_sig",
                                        &ctx->merchant_sig);
    TALER_MHD_parse_request_timeout (rc->connection,
                                     &ctx->timeout);
    TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
    {
      if (GNUNET_OK !=
          TALER_merchant_deposit_verify (&ctx->merchant,
                                         &ctx->coin_pub,
                                         &ctx->h_contract_terms,
                                         &ctx->h_wire,
                                         &ctx->merchant_sig))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_FORBIDDEN,
          TALER_EC_EXCHANGE_DEPOSITS_GET_MERCHANT_SIGNATURE_INVALID,
          NULL);
      }
    }
  }

  return handle_track_transaction_request (ctx);
}


/* end of taler-exchange-httpd_deposits_get.c */
