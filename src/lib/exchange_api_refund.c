/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 GNUnet e.V.

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
 * @file exchange-lib/exchange_api_refund.c
 * @brief Implementation of the /refund request of the exchange's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_json_lib.h"
#include "taler_exchange_service.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A Refund Handle
 */
struct TALER_EXCHANGE_RefundHandle
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
  struct TEAH_PostContext ctx;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_RefundResultCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Information the exchange should sign in response.
   */
  struct TALER_RefundConfirmationPS depconf;

};


/**
 * Verify that the signature on the "200 OK" response
 * from the exchange is valid.
 *
 * @param rh refund handle
 * @param json json reply with the signature
 * @param[out] exchange_pub set to the exchange's public key
 * @return #GNUNET_OK if the signature is valid, #GNUNET_SYSERR if not
 */
static int
verify_refund_signature_ok (const struct TALER_EXCHANGE_RefundHandle *rh,
                            const json_t *json,
                            struct TALER_ExchangePublicKeyP *exchange_pub)
{
  struct TALER_ExchangeSignatureP exchange_sig;
  const struct TALER_EXCHANGE_Keys *key_state;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("sig", &exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("pub", exchange_pub),
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
  key_state = TALER_EXCHANGE_get_keys (rh->exchange);
  if (GNUNET_OK !=
      TALER_EXCHANGE_test_signing_key (key_state,
                                       exchange_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_REFUND,
                                  &rh->depconf.purpose,
                                  &exchange_sig.eddsa_signature,
                                  &exchange_pub->eddsa_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /refund request.
 *
 * @param cls the `struct TALER_EXCHANGE_RefundHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_refund_finished (void *cls,
                        long response_code,
                        const void *response)
{
  struct TALER_EXCHANGE_RefundHandle *rh = cls;
  struct TALER_ExchangePublicKeyP exchange_pub;
  struct TALER_ExchangePublicKeyP *ep = NULL;
  const json_t *j = response;

  rh->job = NULL;
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        verify_refund_signature_ok (rh,
                                    j,
                                    &exchange_pub))
    {
      GNUNET_break_op (0);
      response_code = 0;
    }
    else
    {
      ep = &exchange_pub;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    break;
  case MHD_HTTP_GONE:
    /* Kind of normal: the money was already sent to the merchant
       (it was too late for the refund). */
    break;
  case MHD_HTTP_PRECONDITION_FAILED:
    /* Client request was inconsistent; might be a currency missmatch
       problem.  */
    break;
  case MHD_HTTP_CONFLICT:
    /* Two refund requests were made about the same deposit, but
       carrying different refund transaction ids.  */
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
  rh->cb (rh->cb_cls,
          response_code,
          TALER_JSON_get_error_code (j),
          ep,
          j);
  TALER_EXCHANGE_refund_cancel (rh);
}


/**
 * Submit a refund request to the exchange and get the exchange's
 * response.  This API is used by a merchant.  Note that
 * while we return the response verbatim to the caller for further
 * processing, we do already verify that the response is well-formed
 * (i.e. that signatures included in the response are all valid).  If
 * the exchange's reply is not well-formed, we return an HTTP status code
 * of zero to @a cb.
 *
 * The @a exchange must be ready to operate (i.e.  have
 * finished processing the /keys reply).  If this check fails, we do
 * NOT initiate the transaction with the exchange and instead return NULL.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param amount the amount to be refunded; must be larger than the refund fee
 *        (as that fee is still being subtracted), and smaller than the amount
 *        (with deposit fee) of the original deposit contribution of this coin
 * @param refund_fee fee applicable to this coin for the refund
 * @param h_contract_terms hash of the contact of the merchant with the customer that is being refunded
 * @param coin_pub coin’s public key of the coin from the original deposit operation
 * @param rtransaction_id transaction id for the transaction between merchant and customer (of refunding operation);
 *                        this is needed as we may first do a partial refund and later a full refund.  If both
 *                        refunds are also over the same amount, we need the @a rtransaction_id to make the disjoint
 *                        refund requests different (as requests are idempotent and otherwise the 2nd refund might not work).
 * @param merchant_priv the private key of the merchant, used to generate signature for refund request
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_EXCHANGE_RefundHandle *
TALER_EXCHANGE_refund (struct TALER_EXCHANGE_Handle *exchange,
                       const struct TALER_Amount *amount,
                       const struct TALER_Amount *refund_fee,
                       const struct GNUNET_HashCode *h_contract_terms,
                       const struct TALER_CoinSpendPublicKeyP *coin_pub,
                       uint64_t rtransaction_id,
                       const struct TALER_MerchantPrivateKeyP *merchant_priv,
                       TALER_EXCHANGE_RefundResultCallback cb,
                       void *cb_cls)
{
  struct TALER_RefundRequestPS rr;
  struct TALER_MerchantSignatureP merchant_sig;

  GNUNET_assert (GNUNET_YES ==
                 TEAH_handle_is_ready (exchange));
  rr.purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_REFUND);
  rr.purpose.size = htonl (sizeof (struct TALER_RefundRequestPS));
  rr.h_contract_terms = *h_contract_terms;
  rr.coin_pub = *coin_pub;
  GNUNET_CRYPTO_eddsa_key_get_public (&merchant_priv->eddsa_priv,
                                      &rr.merchant.eddsa_pub);
  rr.rtransaction_id = GNUNET_htonll (rtransaction_id);
  TALER_amount_hton (&rr.refund_amount,
                     amount);
  TALER_amount_hton (&rr.refund_fee,
                     refund_fee);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (&merchant_priv->eddsa_priv,
                                           &rr.purpose,
                                           &merchant_sig.eddsa_sig));
  return TALER_EXCHANGE_refund2 (exchange,
                                 amount,
                                 refund_fee,
                                 h_contract_terms,
                                 coin_pub,
                                 rtransaction_id,
                                 &rr.merchant,
                                 &merchant_sig,
                                 cb,
                                 cb_cls);
}


/**
 * Submit a refund request to the exchange and get the exchange's
 * response.  This API is used by a merchant.  Note that
 * while we return the response verbatim to the caller for further
 * processing, we do already verify that the response is well-formed
 * (i.e. that signatures included in the response are all valid).  If
 * the exchange's reply is not well-formed, we return an HTTP status code
 * of zero to @a cb.
 *
 * The @a exchange must be ready to operate (i.e.  have
 * finished processing the /keys reply).  If this check fails, we do
 * NOT initiate the transaction with the exchange and instead return NULL.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param amount the amount to be refunded; must be larger than the refund fee
 *        (as that fee is still being subtracted), and smaller than the amount
 *        (with deposit fee) of the original deposit contribution of this coin
 * @param refund_fee fee applicable to this coin for the refund
 * @param h_contract_terms hash of the contact of the merchant with the customer that is being refunded
 * @param coin_pub coin’s public key of the coin from the original deposit operation
 * @param rtransaction_id transaction id for the transaction between merchant and customer (of refunding operation);
 *                        this is needed as we may first do a partial refund and later a full refund.  If both
 *                        refunds are also over the same amount, we need the @a rtransaction_id to make the disjoint
 *                        refund requests different (as requests are idempotent and otherwise the 2nd refund might not work).
 * @param merchant_pub public key of the merchant
 * @param merchant_sig signature affirming the refund from the merchant
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_EXCHANGE_RefundHandle *
TALER_EXCHANGE_refund2 (struct TALER_EXCHANGE_Handle *exchange,
                        const struct TALER_Amount *amount,
                        const struct TALER_Amount *refund_fee,
                        const struct GNUNET_HashCode *h_contract_terms,
                        const struct TALER_CoinSpendPublicKeyP *coin_pub,
                        uint64_t rtransaction_id,
                        const struct TALER_MerchantPublicKeyP *merchant_pub,
                        const struct TALER_MerchantSignatureP *merchant_sig,
                        TALER_EXCHANGE_RefundResultCallback cb,
                        void *cb_cls)
{
  struct TALER_EXCHANGE_RefundHandle *rh;
  struct GNUNET_CURL_Context *ctx;
  json_t *refund_obj;
  CURL *eh;

  refund_obj = json_pack ("{s:o, s:o," /* amount/fee */
                          " s:o, s:o," /* h_contract_terms, coin_pub */
                          " s:I," /* rtransaction id */
                          " s:o, s:o}", /* merchant_pub, merchant_sig */
                          "refund_amount", TALER_JSON_from_amount (amount),
                          "refund_fee", TALER_JSON_from_amount (refund_fee),
                          "h_contract_terms", GNUNET_JSON_from_data_auto (
                            h_contract_terms),
                          "coin_pub", GNUNET_JSON_from_data_auto (coin_pub),
                          "rtransaction_id", (json_int_t) rtransaction_id,
                          "merchant_pub", GNUNET_JSON_from_data_auto (
                            merchant_pub),
                          "merchant_sig", GNUNET_JSON_from_data_auto (
                            merchant_sig)
                          );
  if (NULL == refund_obj)
  {
    GNUNET_break (0);
    return NULL;
  }

  rh = GNUNET_new (struct TALER_EXCHANGE_RefundHandle);
  rh->exchange = exchange;
  rh->cb = cb;
  rh->cb_cls = cb_cls;
  rh->url = TEAH_path_to_url (exchange, "/refund");
  rh->depconf.purpose.size = htonl (sizeof (struct TALER_RefundConfirmationPS));
  rh->depconf.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_REFUND);
  rh->depconf.h_contract_terms = *h_contract_terms;
  rh->depconf.coin_pub = *coin_pub;
  rh->depconf.merchant = *merchant_pub;
  rh->depconf.rtransaction_id = GNUNET_htonll (rtransaction_id);
  TALER_amount_hton (&rh->depconf.refund_amount,
                     amount);
  TALER_amount_hton (&rh->depconf.refund_fee,
                     refund_fee);

  eh = TEL_curl_easy_get (rh->url);
  if (GNUNET_OK !=
      TALER_curl_easy_post (&rh->ctx,
                            eh,
                            refund_obj))
  {
    GNUNET_break (0);
    curl_easy_cleanup (eh);
    json_decref (refund_obj);
    GNUNET_free (rh->url);
    GNUNET_free (rh);
    return NULL;
  }
  json_decref (refund_obj);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "URL for refund: `%s'\n",
              rh->url);
  ctx = TEAH_handle_to_context (exchange);
  rh->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  rh->ctx.headers,
                                  &handle_refund_finished,
                                  rh);
  return rh;
}


/**
 * Cancel a refund permission request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param refund the refund permission request handle
 */
void
TALER_EXCHANGE_refund_cancel (struct TALER_EXCHANGE_RefundHandle *refund)
{
  if (NULL != refund->job)
  {
    GNUNET_CURL_job_cancel (refund->job);
    refund->job = NULL;
  }
  GNUNET_free (refund->url);
  TALER_curl_easy_post_finished (&refund->ctx);
  GNUNET_free (refund);
}


/* end of exchange_api_refund.c */
