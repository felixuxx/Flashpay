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
 * @file lib/exchange_api_withdraw2.c
 * @brief Implementation of /reserves/$RESERVE_PUB/withdraw requests without blinding/unblinding
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
struct TALER_EXCHANGE_Withdraw2Handle
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
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_Withdraw2Callback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Context for #TEH_curl_easy_post(). Keeps the data that must
   * persist for Curl to make the upload.
   */
  struct TALER_CURL_PostContext post_ctx;

  /**
   * Total amount requested (value plus withdraw fee).
   */
  struct TALER_Amount requested_amount;

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
reserve_withdraw_ok (struct TALER_EXCHANGE_Withdraw2Handle *wh,
                     const json_t *json)
{
  struct GNUNET_CRYPTO_RsaSignature *blind_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_rsa_signature ("ev_sig",
                                    &blind_sig),
    GNUNET_JSON_spec_end ()
  };
  struct TALER_EXCHANGE_HttpResponse hr = {
    .reply = json,
    .http_status = MHD_HTTP_OK
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* signature is valid, return it to the application */
  wh->cb (wh->cb_cls,
          &hr,
          blind_sig);
  /* make sure callback isn't called again after return */
  wh->cb = NULL;
  GNUNET_JSON_parse_free (spec);
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
reserve_withdraw_payment_required (
  struct TALER_EXCHANGE_Withdraw2Handle *wh,
  const json_t *json)
{
  struct TALER_Amount balance;
  struct TALER_Amount balance_from_history;
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
  /* Check that funds were really insufficient */
  if (0 >= TALER_amount_cmp (&wh->requested_amount,
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
  struct TALER_EXCHANGE_Withdraw2Handle *wh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .reply = j,
    .http_status = (unsigned int) response_code
  };

  wh->job = NULL;
  switch (response_code)
  {
  case 0:
    hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        reserve_withdraw_ok (wh,
                             j))
    {
      GNUNET_break_op (0);
      hr.http_status = 0;
      hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
      break;
    }
    GNUNET_assert (NULL == wh->cb);
    TALER_EXCHANGE_withdraw2_cancel (wh);
    return;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_FORBIDDEN:
    GNUNET_break_op (0);
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, the exchange basically just says
       that it doesn't know this reserve.  Can happen if we
       query before the wire transfer went through.
       We should simply pass the JSON reply to the application. */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_CONFLICT:
    /* The exchange says that the reserve has insufficient funds;
       check the signatures in the history... */
    if (GNUNET_OK !=
        reserve_withdraw_payment_required (wh,
                                           j))
    {
      GNUNET_break_op (0);
      hr.http_status = 0;
      hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
    }
    else
    {
      hr.ec = TALER_JSON_get_error_code (j);
      hr.hint = TALER_JSON_get_error_hint (j);
    }
    break;
  case MHD_HTTP_GONE:
    /* could happen if denomination was revoked */
    /* Note: one might want to check /keys for revocation
       signature here, alas tricky in case our /keys
       is outdated => left to clients */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange withdraw\n",
                (unsigned int) response_code,
                (int) hr.ec);
    break;
  }
  if (NULL != wh->cb)
  {
    wh->cb (wh->cb_cls,
            &hr,
            NULL);
    wh->cb = NULL;
  }
  TALER_EXCHANGE_withdraw2_cancel (wh);
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
 * @param pd planchet details of the planchet to withdraw
 * @param reserve_priv private key of the reserve to withdraw from
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for @a res_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_Withdraw2Handle *
TALER_EXCHANGE_withdraw2 (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_PlanchetDetail *pd,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  TALER_EXCHANGE_Withdraw2Callback res_cb,
  void *res_cb_cls)
{
  struct TALER_EXCHANGE_Withdraw2Handle *wh;
  const struct TALER_EXCHANGE_Keys *keys;
  const struct TALER_EXCHANGE_DenomPublicKey *dk;
  struct TALER_ReserveSignatureP reserve_sig;
  char arg_str[sizeof (struct TALER_ReservePublicKeyP) * 2 + 32];

  keys = TALER_EXCHANGE_get_keys (exchange);
  if (NULL == keys)
  {
    GNUNET_break (0);
    return NULL;
  }
  dk = TALER_EXCHANGE_get_denomination_key_by_hash (keys,
                                                    &pd->denom_pub_hash);
  if (NULL == dk)
  {
    GNUNET_break (0);
    return NULL;
  }
  wh = GNUNET_new (struct TALER_EXCHANGE_Withdraw2Handle);
  wh->exchange = exchange;
  wh->cb = res_cb;
  wh->cb_cls = res_cb_cls;
  /* Compute how much we expected to charge to the reserve */
  if (0 >
      TALER_amount_add (&wh->requested_amount,
                        &dk->value,
                        &dk->fee_withdraw))
  {
    /* Overflow here? Very strange, our CPU must be fried... */
    GNUNET_break (0);
    GNUNET_free (wh);
    return NULL;
  }

  GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                      &wh->reserve_pub.eddsa_pub);

  {
    char pub_str[sizeof (struct TALER_ReservePublicKeyP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &wh->reserve_pub,
      sizeof (struct TALER_ReservePublicKeyP),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/reserves/%s/withdraw",
                     pub_str);
  }
  {
    struct TALER_WithdrawRequestPS req = {
      .purpose.size = htonl (sizeof (struct TALER_WithdrawRequestPS)),
      .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW),
      .reserve_pub = wh->reserve_pub,
      .h_denomination_pub = pd->denom_pub_hash
    };

    TALER_amount_hton (&req.amount_with_fee,
                       &wh->requested_amount);
    GNUNET_CRYPTO_hash (pd->coin_ev,
                        pd->coin_ev_size,
                        &req.h_coin_envelope);
    GNUNET_CRYPTO_eddsa_sign (&reserve_priv->eddsa_priv,
                              &req,
                              &reserve_sig.eddsa_signature);
  }

  {
    json_t *withdraw_obj;

    withdraw_obj = json_pack ("{s:o, s:o, s:o}",
                              "denom_pub_hash",
                              GNUNET_JSON_from_data_auto (&pd->denom_pub_hash),
                              "coin_ev",
                              GNUNET_JSON_from_data (pd->coin_ev,
                                                     pd->coin_ev_size),
                              "reserve_sig",
                              GNUNET_JSON_from_data_auto (&reserve_sig));
    if (NULL == withdraw_obj)
    {
      GNUNET_break (0);
      GNUNET_free (wh);
      return NULL;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Attempting to withdraw from reserve %s\n",
                TALER_B2S (&wh->reserve_pub));
    wh->url = TEAH_path_to_url (exchange,
                                arg_str);
    {
      CURL *eh;
      struct GNUNET_CURL_Context *ctx;

      ctx = TEAH_handle_to_context (exchange);
      eh = TALER_EXCHANGE_curl_easy_get_ (wh->url);
      if ( (NULL == eh) ||
           (GNUNET_OK !=
            TALER_curl_easy_post (&wh->post_ctx,
                                  eh,
                                  withdraw_obj)) )
      {
        GNUNET_break (0);
        if (NULL != eh)
          curl_easy_cleanup (eh);
        json_decref (withdraw_obj);
        GNUNET_free (wh->url);
        GNUNET_free (wh);
        return NULL;
      }
      json_decref (withdraw_obj);
      wh->job = GNUNET_CURL_job_add2 (ctx,
                                      eh,
                                      wh->post_ctx.headers,
                                      &handle_reserve_withdraw_finished,
                                      wh);
    }
  }
  return wh;
}


/**
 * Cancel a withdraw status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param wh the withdraw sign request handle
 */
void
TALER_EXCHANGE_withdraw2_cancel (struct TALER_EXCHANGE_Withdraw2Handle *wh)
{
  if (NULL != wh->job)
  {
    GNUNET_CURL_job_cancel (wh->job);
    wh->job = NULL;
  }
  GNUNET_free (wh->url);
  TALER_curl_easy_post_finished (&wh->post_ctx);
  GNUNET_free (wh);
}
