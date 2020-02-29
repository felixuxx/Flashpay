/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file lib/exchange_api_withdraw.c
 * @brief Implementation of the /reserves/$RESERVE_PUB/withdraw requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A Withdraw Handle
 */
struct TALER_EXCHANGE_WithdrawHandle
{

  /**
   * The connection to exchange this request handle will use
   */
  struct TALER_EXCHANGE_Handle *exchange;

  /**
   * The url for this request.
   */
  char *url;

  /**
   * Context for #TEH_curl_easy_post(). Keeps the data that must
   * persist for Curl to make the upload.
   */
  struct TALER_CURL_PostContext ctx;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_WithdrawCallback cb;

  /**
   * Secrets of the planchet.
   */
  struct TALER_PlanchetSecretsP ps;

  /**
   * Denomination key we are withdrawing.
   */
  struct TALER_EXCHANGE_DenomPublicKey pk;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Hash of the public key of the coin we are signing.
   */
  struct GNUNET_HashCode c_hash;

  /**
   * Public key of the reserve we are withdrawing from.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

};


/**
 * We got a 200 OK response for the /reserves/$RESERVE_PUB/withdraw operation.
 * Extract the coin's signature and return it to the caller.  The signature we
 * get from the exchange is for the blinded value.  Thus, we first must
 * unblind it and then should verify its validity against our coin's hash.
 *
 * If everything checks out, we return the unblinded signature
 * to the application via the callback.
 *
 * @param wh operation handle
 * @param json reply from the exchange
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static int
reserve_withdraw_ok (struct TALER_EXCHANGE_WithdrawHandle *wh,
                     const json_t *json)
{
  struct GNUNET_CRYPTO_RsaSignature *blind_sig;
  struct TALER_FreshCoin fc;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_rsa_signature ("ev_sig",
                                    &blind_sig),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_planchet_to_coin (&wh->pk.key,
                              blind_sig,
                              &wh->ps,
                              &wh->c_hash,
                              &fc))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return GNUNET_SYSERR;
  }
  GNUNET_JSON_parse_free (spec);

  /* signature is valid, return it to the application */
  wh->cb (wh->cb_cls,
          MHD_HTTP_OK,
          TALER_EC_NONE,
          &fc.sig,
          json);
  /* make sure callback isn't called again after return */
  wh->cb = NULL;
  GNUNET_CRYPTO_rsa_signature_free (fc.sig.rsa_signature);
  return GNUNET_OK;
}


/**
 * We got a 409 CONFLICT response for the /reserves/$RESERVE_PUB/withdraw operation.
 * Check the signatures on the withdraw transactions in the provided
 * history and that the balances add up.  We don't do anything directly
 * with the information, as the JSON will be returned to the application.
 * However, our job is ensuring that the exchange followed the protocol, and
 * this in particular means checking all of the signatures in the history.
 *
 * @param wh operation handle
 * @param json reply from the exchange
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static int
reserve_withdraw_payment_required (struct
                                   TALER_EXCHANGE_WithdrawHandle *wh,
                                   const json_t *json)
{
  struct TALER_Amount balance;
  struct TALER_Amount balance_from_history;
  struct TALER_Amount requested_amount;
  json_t *history;
  size_t len;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("balance", &balance),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  history = json_object_get (json,
                             "history");
  if (NULL == history)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* go over transaction history and compute
     total incoming and outgoing amounts */
  len = json_array_size (history);
  {
    struct TALER_EXCHANGE_ReserveHistory *rhistory;

    /* Use heap allocation as "len" may be very big and thus this may
       not fit on the stack. Use "GNUNET_malloc_large" as a malicious
       exchange may theoretically try to crash us by giving a history
       that does not fit into our memory. */
    rhistory = GNUNET_malloc_large (sizeof (struct
                                            TALER_EXCHANGE_ReserveHistory)
                                    * len);
    if (NULL == rhistory)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }

    if (GNUNET_OK !=
        TALER_EXCHANGE_parse_reserve_history (wh->exchange,
                                              history,
                                              &wh->reserve_pub,
                                              balance.currency,
                                              &balance_from_history,
                                              len,
                                              rhistory))
    {
      GNUNET_break_op (0);
      TALER_EXCHANGE_free_reserve_history (rhistory,
                                           len);
      return GNUNET_SYSERR;
    }
    TALER_EXCHANGE_free_reserve_history (rhistory,
                                         len);
  }

  if (0 !=
      TALER_amount_cmp (&balance_from_history,
                        &balance))
  {
    /* exchange cannot add up balances!? */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  /* Compute how much we expected to charge to the reserve */
  if (GNUNET_OK !=
      TALER_amount_add (&requested_amount,
                        &wh->pk.value,
                        &wh->pk.fee_withdraw))
  {
    /* Overflow here? Very strange, our CPU must be fried... */
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  /* Check that funds were really insufficient */
  if (0 >= TALER_amount_cmp (&requested_amount,
                             &balance))
  {
    /* Requested amount is smaller or equal to reported balance,
       so this should not have failed. */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /reserves/$RESERVE_PUB/withdraw request.
 *
 * @param cls the `struct TALER_EXCHANGE_WithdrawHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_reserve_withdraw_finished (void *cls,
                                  long response_code,
                                  const void *response)
{
  struct TALER_EXCHANGE_WithdrawHandle *wh = cls;
  const json_t *j = response;

  wh->job = NULL;
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        reserve_withdraw_ok (wh,
                             j))
    {
      GNUNET_break_op (0);
      response_code = 0;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_CONFLICT:
    /* The exchange says that the reserve has insufficient funds;
       check the signatures in the history... */
    if (GNUNET_OK !=
        reserve_withdraw_payment_required (wh,
                                           j))
    {
      GNUNET_break_op (0);
      response_code = 0;
    }
    break;
  case MHD_HTTP_FORBIDDEN:
    GNUNET_break (0);
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, the exchange basically just says
       that it doesn't know this reserve.  Can happen if we
       query before the wire transfer went through.
       We should simply pass the JSON reply to the application. */
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                (unsigned int) response_code);
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  if (NULL != wh->cb)
  {
    wh->cb (wh->cb_cls,
            response_code,
            TALER_JSON_get_error_code (j),
            NULL,
            j);
    wh->cb = NULL;
  }
  TALER_EXCHANGE_withdraw_cancel (wh);
}


/**
 * Helper function for #TALER_EXCHANGE_withdraw2() and
 * #TALER_EXCHANGE_withdraw().
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param pk kind of coin to create
 * @param reserve_sig signature from the reserve authorizing the withdrawal
 * @param reserve_pub public key of the reserve to withdraw from
 * @param ps secrets of the planchet
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param pd planchet details matching @a ps
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for @a res_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_WithdrawHandle *
reserve_withdraw_internal (struct TALER_EXCHANGE_Handle *exchange,
                           const struct TALER_EXCHANGE_DenomPublicKey *pk,
                           const struct TALER_ReserveSignatureP *reserve_sig,
                           const struct TALER_ReservePublicKeyP *reserve_pub,
                           const struct TALER_PlanchetSecretsP *ps,
                           const struct TALER_PlanchetDetail *pd,
                           TALER_EXCHANGE_WithdrawCallback res_cb,
                           void *res_cb_cls)
{
  struct TALER_EXCHANGE_WithdrawHandle *wh;
  struct GNUNET_CURL_Context *ctx;
  json_t *withdraw_obj;
  CURL *eh;
  struct GNUNET_HashCode h_denom_pub;
  char arg_str[sizeof (struct TALER_ReservePublicKeyP) * 2 + 32];

  {
    char pub_str[sizeof (struct TALER_ReservePublicKeyP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (reserve_pub,
                                         sizeof (struct
                                                 TALER_ReservePublicKeyP),
                                         pub_str,
                                         sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/reserves/%s/withdraw",
                     pub_str);
  }
  wh = GNUNET_new (struct TALER_EXCHANGE_WithdrawHandle);
  wh->exchange = exchange;
  wh->cb = res_cb;
  wh->cb_cls = res_cb_cls;
  wh->pk = *pk;
  wh->pk.key.rsa_public_key
    = GNUNET_CRYPTO_rsa_public_key_dup (pk->key.rsa_public_key);
  wh->reserve_pub = *reserve_pub;
  wh->c_hash = pd->c_hash;
  GNUNET_CRYPTO_rsa_public_key_hash (pk->key.rsa_public_key,
                                     &h_denom_pub);
  withdraw_obj = json_pack ("{s:o, s:o," /* denom_pub_hash and coin_ev */
                            " s:o}",/* reserve_pub and reserve_sig */
                            "denom_pub_hash", GNUNET_JSON_from_data_auto (
                              &h_denom_pub),
                            "coin_ev", GNUNET_JSON_from_data (pd->coin_ev,
                                                              pd->coin_ev_size),
                            "reserve_sig", GNUNET_JSON_from_data_auto (
                              reserve_sig));
  if (NULL == withdraw_obj)
  {
    GNUNET_break (0);
    GNUNET_CRYPTO_rsa_public_key_free (wh->pk.key.rsa_public_key);
    GNUNET_free (wh);
    return NULL;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Attempting to withdraw from reserve %s\n",
              TALER_B2S (reserve_pub));
  wh->ps = *ps;
  wh->url = TEAH_path_to_url (exchange,
                              arg_str);
  eh = TEL_curl_easy_get (wh->url);
  if (GNUNET_OK !=
      TALER_curl_easy_post (&wh->ctx,
                            eh,
                            withdraw_obj))
  {
    GNUNET_break (0);
    curl_easy_cleanup (eh);
    json_decref (withdraw_obj);
    GNUNET_free (wh->url);
    GNUNET_CRYPTO_rsa_public_key_free (wh->pk.key.rsa_public_key);
    GNUNET_free (wh);
    return NULL;
  }
  json_decref (withdraw_obj);
  ctx = TEAH_handle_to_context (exchange);
  wh->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  wh->ctx.headers,
                                  &handle_reserve_withdraw_finished,
                                  wh);
  return wh;
}


/**
 * Withdraw a coin from the exchange using a /reserve/withdraw request.  Note
 * that to ensure that no money is lost in case of hardware failures,
 * the caller must have committed (most of) the arguments to disk
 * before calling, and be ready to repeat the request with the same
 * arguments in case of failures.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param pk kind of coin to create
 * @param reserve_priv private key of the reserve to withdraw from
 * @param ps secrets of the planchet
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return handle for the operation on success, NULL on error, i.e.
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_WithdrawHandle *
TALER_EXCHANGE_withdraw (struct TALER_EXCHANGE_Handle *exchange,
                         const struct TALER_EXCHANGE_DenomPublicKey *pk,
                         const struct
                         TALER_ReservePrivateKeyP *reserve_priv,
                         const struct TALER_PlanchetSecretsP *ps,
                         TALER_EXCHANGE_WithdrawCallback
                         res_cb,
                         void *res_cb_cls)
{
  struct TALER_Amount amount_with_fee;
  struct TALER_ReserveSignatureP reserve_sig;
  struct TALER_WithdrawRequestPS req;
  struct TALER_PlanchetDetail pd;
  struct TALER_EXCHANGE_WithdrawHandle *wh;

  GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                      &req.reserve_pub.eddsa_pub);
  req.purpose.size = htonl (sizeof (struct TALER_WithdrawRequestPS));
  req.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW);
  if (GNUNET_OK !=
      TALER_amount_add (&amount_with_fee,
                        &pk->fee_withdraw,
                        &pk->value))
  {
    /* exchange gave us denomination keys that overflow like this!? */
    GNUNET_break_op (0);
    return NULL;
  }
  TALER_amount_hton (&req.amount_with_fee,
                     &amount_with_fee);
  TALER_amount_hton (&req.withdraw_fee,
                     &pk->fee_withdraw);
  if (GNUNET_OK !=
      TALER_planchet_prepare (&pk->key,
                              ps,
                              &pd))
  {
    GNUNET_break_op (0);
    return NULL;
  }
  req.h_denomination_pub = pd.denom_pub_hash;
  GNUNET_CRYPTO_hash (pd.coin_ev,
                      pd.coin_ev_size,
                      &req.h_coin_envelope);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (&reserve_priv->eddsa_priv,
                                           &req.purpose,
                                           &reserve_sig.eddsa_signature));
  wh = reserve_withdraw_internal (exchange,
                                  pk,
                                  &reserve_sig,
                                  &req.reserve_pub,
                                  ps,
                                  &pd,
                                  res_cb,
                                  res_cb_cls);
  GNUNET_free (pd.coin_ev);
  return wh;
}


/**
 * Withdraw a coin from the exchange using a /reserve/withdraw
 * request.  This API is typically used by a wallet to withdraw a tip
 * where the reserve's signature was created by the merchant already.
 *
 * Note that to ensure that no money is lost in case of hardware
 * failures, the caller must have committed (most of) the arguments to
 * disk before calling, and be ready to repeat the request with the
 * same arguments in case of failures.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param pk kind of coin to create
 * @param reserve_sig signature from the reserve authorizing the withdrawal
 * @param reserve_pub public key of the reserve to withdraw from
 * @param ps secrets of the planchet
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for @a res_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_WithdrawHandle *
TALER_EXCHANGE_withdraw2 (struct TALER_EXCHANGE_Handle *exchange,
                          const struct
                          TALER_EXCHANGE_DenomPublicKey *pk,
                          const struct
                          TALER_ReserveSignatureP *reserve_sig,
                          const struct
                          TALER_ReservePublicKeyP *reserve_pub,
                          const struct TALER_PlanchetSecretsP *ps,
                          TALER_EXCHANGE_WithdrawCallback
                          res_cb,
                          void *res_cb_cls)
{
  struct TALER_EXCHANGE_WithdrawHandle *wh;
  struct TALER_PlanchetDetail pd;

  if (GNUNET_OK !=
      TALER_planchet_prepare (&pk->key,
                              ps,
                              &pd))
  {
    GNUNET_break_op (0);
    return NULL;
  }
  wh = reserve_withdraw_internal (exchange,
                                  pk,
                                  reserve_sig,
                                  reserve_pub,
                                  ps,
                                  &pd,
                                  res_cb,
                                  res_cb_cls);
  GNUNET_free (pd.coin_ev);
  return wh;
}


/**
 * Cancel a withdraw status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param sign the withdraw sign request handle
 */
void
TALER_EXCHANGE_withdraw_cancel (struct TALER_EXCHANGE_WithdrawHandle *wh)
{
  if (NULL != wh->job)
  {
    GNUNET_CURL_job_cancel (wh->job);
    wh->job = NULL;
  }
  GNUNET_free (wh->url);
  TALER_curl_easy_post_finished (&wh->ctx);
  GNUNET_CRYPTO_rsa_public_key_free (wh->pk.key.rsa_public_key);
  GNUNET_free (wh);
}
