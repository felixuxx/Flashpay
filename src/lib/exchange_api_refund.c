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
 * @file lib/exchange_api_refund.c
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
  struct TALER_CURL_PostContext ctx;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_RefundCallback cb;

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
 * @param[in,out] rh refund handle (refund fee added)
 * @param json json reply with the signature
 * @param[out] exchange_pub set to the exchange's public key
 * @param[out] exchange_sig set to the exchange's signature
 * @return #GNUNET_OK if the signature is valid, #GNUNET_SYSERR if not
 */
static int
verify_refund_signature_ok (struct TALER_EXCHANGE_RefundHandle *rh,
                            const json_t *json,
                            struct TALER_ExchangePublicKeyP *exchange_pub,
                            struct TALER_ExchangeSignatureP *exchange_sig)
{
  const struct TALER_EXCHANGE_Keys *key_state;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("exchange_sig", exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub", exchange_pub),
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
                                  &rh->depconf,
                                  &exchange_sig->eddsa_signature,
                                  &exchange_pub->eddsa_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Verify that the information in the "409 Conflict" response
 * from the exchange is valid and indeed shows that the refund
 * amount requested is too high.
 *
 * @param[in,out] rh refund handle (refund fee added)
 * @param json json reply with the coin transaction history
 * @return #GNUNET_OK if the signature is valid, #GNUNET_SYSERR if not
 */
static int
verify_conflict_history_ok (struct TALER_EXCHANGE_RefundHandle *rh,
                            const json_t *json)
{
  json_t *history;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("history",
                           &history),
    GNUNET_JSON_spec_end ()
  };
  size_t len;
  struct TALER_Amount dtotal;
  bool have_deposit;
  struct TALER_Amount rtotal;
  bool have_refund;

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
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
  have_deposit = false;
  have_refund = false;
  for (size_t off = 0; off<len; off++)
  {
    json_t *transaction;
    struct TALER_Amount amount;
    const char *type;
    struct GNUNET_JSON_Specification spec_glob[] = {
      TALER_JSON_spec_amount ("amount",
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
    if (0 == strcasecmp (type,
                         "DEPOSIT"))
    {
      struct TALER_DepositRequestPS dr = {
        .purpose.size = htonl (sizeof (dr)),
        .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_DEPOSIT),
        .coin_pub = rh->depconf.coin_pub
      };
      struct TALER_CoinSpendSignatureP sig;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                     &sig),
        GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                     &dr.h_contract_terms),
        GNUNET_JSON_spec_fixed_auto ("h_wire",
                                     &dr.h_wire),
        GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                     &dr.h_denom_pub),
        TALER_JSON_spec_absolute_time_nbo ("timestamp",
                                           &dr.wallet_timestamp),
        TALER_JSON_spec_absolute_time_nbo ("refund_deadline",
                                           &dr.refund_deadline),
        TALER_JSON_spec_amount_nbo ("deposit_fee",
                                    &dr.deposit_fee),
        GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                     &dr.merchant),
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
      TALER_amount_hton (&dr.amount_with_fee,
                         &amount);
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_DEPOSIT,
                                      &dr,
                                      &sig.eddsa_signature,
                                      &rh->depconf.coin_pub.eddsa_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if ( (0 != GNUNET_memcmp (&rh->depconf.h_contract_terms,
                                &dr.h_contract_terms)) ||
           (0 != GNUNET_memcmp (&rh->depconf.merchant,
                                &dr.merchant)) )
      {
        /* deposit information is about a different merchant/contract */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (have_deposit)
      {
        /* this cannot really happen, but we conservatively support it anyway */
        if (GNUNET_YES !=
            TALER_amount_cmp_currency (&amount,
                                       &dtotal))
        {
          GNUNET_break_op (0);
          return GNUNET_SYSERR;
        }
        GNUNET_break (0 <=
                      TALER_amount_add (&dtotal,
                                        &dtotal,
                                        &amount));
      }
      else
      {
        dtotal = amount;
        have_deposit = true;
      }
    }
    else if (0 == strcasecmp (type,
                              "REFUND"))
    {
      struct TALER_MerchantSignatureP sig;
      struct TALER_Amount refund_fee;
      struct TALER_Amount sig_amount;
      struct TALER_RefundRequestPS rr = {
        .purpose.size = htonl (sizeof (rr)),
        .purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_REFUND),
        .coin_pub = rh->depconf.coin_pub
      };
      struct GNUNET_JSON_Specification spec[] = {
        TALER_JSON_spec_amount ("refund_fee",
                                &refund_fee),
        GNUNET_JSON_spec_fixed_auto ("merchant_sig",
                                     &sig),
        GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                     &rr.h_contract_terms),
        GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                     &rr.merchant),
        GNUNET_JSON_spec_uint64 ("rtransaction_id",
                                 &rr.rtransaction_id), // FIXME: shouldn't this be NBO!?
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
                            &amount))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      TALER_amount_hton (&rr.refund_amount,
                         &sig_amount);
      rr.rtransaction_id = GNUNET_htonll (rr.rtransaction_id);
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MERCHANT_REFUND,
                                      &rr,
                                      &sig.eddsa_sig,
                                      &rr.merchant.eddsa_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if ( (0 != GNUNET_memcmp (&rh->depconf.h_contract_terms,
                                &rr.h_contract_terms)) ||
           (0 != GNUNET_memcmp (&rh->depconf.merchant,
                                &rr.merchant)) )
      {
        /* refund is about a different merchant/contract */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (rr.rtransaction_id == rh->depconf.rtransaction_id)
      {
        /* Eh, this shows either a dependency failure or idempotency,
           but must not happen in a conflict reply. Fail! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }

      if (have_refund)
      {
        if (GNUNET_YES !=
            TALER_amount_cmp_currency (&amount,
                                       &rtotal))
        {
          GNUNET_break_op (0);
          return GNUNET_SYSERR;
        }
        GNUNET_break (0 <=
                      TALER_amount_add (&rtotal,
                                        &rtotal,
                                        &amount));
      }
      else
      {
        rtotal = amount;
        have_refund = true;
      }
    }
    else
    {
      /* unexpected type, new version on server? */
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Unexpected type `%s' in response\n",
                  type);
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }

  {
    struct TALER_Amount amount;

    TALER_amount_ntoh (&amount,
                       &rh->depconf.refund_amount);
    if (have_refund)
    {
      if (0 >
          TALER_amount_add (&rtotal,
                            &rtotal,
                            &amount))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
    }
    else
    {
      rtotal = amount;
    }
  }
  if (-1 == TALER_amount_cmp (&dtotal,
                              &rtotal))
  {
    /* dtotal < rtotal: good! */
    return GNUNET_OK;
  }
  /* this fails to prove a conflict */
  GNUNET_break_op (0);
  return GNUNET_SYSERR;
}


/**
 * Verify that the information on the "412 Dependency Failed" response
 * from the exchange is valid and indeed shows that there is a refund
 * transaction ID reuse going on.
 *
 * @param[in,out] rh refund handle (refund fee added)
 * @param json json reply with the signature
 * @return #GNUNET_OK if the signature is valid, #GNUNET_SYSERR if not
 */
static int
verify_failed_dependency_ok (struct TALER_EXCHANGE_RefundHandle *rh,
                             const json_t *json)
{
  json_t *h;
  json_t *e;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("history", &h),
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
  if ( (! json_is_array (h)) ||
       (1 != json_array_size (h) ) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  e = json_array_get (h, 0);
  {
    struct TALER_Amount amount;
    const char *type;
    struct TALER_MerchantSignatureP sig;
    struct TALER_Amount refund_fee;
    struct TALER_RefundRequestPS rr = {
      .purpose.size = htonl (sizeof (rr)),
      .purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_REFUND),
      .coin_pub = rh->depconf.coin_pub
    };
    uint64_t rtransaction_id;
    struct GNUNET_JSON_Specification spec[] = {
      TALER_JSON_spec_amount ("amount",
                              &amount),
      GNUNET_JSON_spec_string ("type",
                               &type),
      TALER_JSON_spec_amount ("refund_fee",
                              &refund_fee),
      GNUNET_JSON_spec_fixed_auto ("merchant_sig",
                                   &sig),
      GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                   &rr.h_contract_terms),
      GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                   &rr.merchant),
      GNUNET_JSON_spec_uint64 ("rtransaction_id",
                               &rtransaction_id),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (e,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    rr.rtransaction_id = GNUNET_htonll (rtransaction_id);
    TALER_amount_hton (&rr.refund_amount,
                       &amount);
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MERCHANT_REFUND,
                                    &rr,
                                    &sig.eddsa_sig,
                                    &rh->depconf.merchant.eddsa_pub))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    if ( (rr.rtransaction_id != rh->depconf.rtransaction_id) ||
         (0 != GNUNET_memcmp (&rh->depconf.h_contract_terms,
                              &rr.h_contract_terms)) ||
         (0 != GNUNET_memcmp (&rh->depconf.merchant,
                              &rr.merchant)) ||
         (0 == TALER_amount_cmp_nbo (&rh->depconf.refund_amount,
                                     &rr.refund_amount)) )
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
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
  struct TALER_ExchangeSignatureP exchange_sig;
  struct TALER_ExchangePublicKeyP *ep = NULL;
  struct TALER_ExchangeSignatureP *es = NULL;
  const json_t *j = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .reply = j,
    .http_status = (unsigned int) response_code
  };

  rh->job = NULL;
  switch (response_code)
  {
  case 0:
    hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        verify_refund_signature_ok (rh,
                                    j,
                                    &exchange_pub,
                                    &exchange_sig))
    {
      GNUNET_break_op (0);
      hr.http_status = 0;
      hr.ec = TALER_EC_EXCHANGE_REFUND_INVALID_SIGNATURE_BY_EXCHANGE;
    }
    else
    {
      ep = &exchange_pub;
      es = &exchange_sig;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); also can happen if the currency
       differs (which we should obviously never support).
       Just pass JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_CONFLICT:
    /* Requested total refunds exceed deposited amount */
    if (GNUNET_OK !=
        verify_conflict_history_ok (rh,
                                    j))
    {
      GNUNET_break (0);
      hr.http_status = 0;
      hr.ec = TALER_EC_EXCHANGE_REFUND_INVALID_FAILURE_PROOF_BY_EXCHANGE;
      hr.hint = "conflict information provided by exchange is invalid";
      break;
    }
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_GONE:
    /* Kind of normal: the money was already sent to the merchant
       (it was too late for the refund). */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_PRECONDITION_FAILED:
    if (GNUNET_OK !=
        verify_failed_dependency_ok (rh,
                                     j))
    {
      GNUNET_break (0);
      hr.http_status = 0;
      hr.ec = TALER_EC_EXCHANGE_REFUND_INVALID_FAILURE_PROOF_BY_EXCHANGE;
      hr.hint = "failed precondition proof returned by exchange is invalid";
      break;
    }
    /* Two different refund requests were made about the same deposit, but
       carrying identical refund transaction ids.  */
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
                "Unexpected response code %u/%d\n",
                (unsigned int) response_code,
                hr.ec);
    break;
  }
  rh->cb (rh->cb_cls,
          &hr,
          ep,
          es);
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
                       const struct GNUNET_HashCode *h_contract_terms,
                       const struct TALER_CoinSpendPublicKeyP *coin_pub,
                       uint64_t rtransaction_id,
                       const struct TALER_MerchantPrivateKeyP *merchant_priv,
                       TALER_EXCHANGE_RefundCallback cb,
                       void *cb_cls)
{
  struct TALER_RefundRequestPS rr = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_REFUND),
    .purpose.size = htonl (sizeof (rr)),
    .h_contract_terms = *h_contract_terms,
    .rtransaction_id = GNUNET_htonll (rtransaction_id),
    .coin_pub = *coin_pub
  };
  struct TALER_MerchantSignatureP merchant_sig;
  struct TALER_EXCHANGE_RefundHandle *rh;
  struct GNUNET_CURL_Context *ctx;
  json_t *refund_obj;
  CURL *eh;
  char arg_str[sizeof (struct TALER_CoinSpendPublicKeyP) * 2 + 32];

  GNUNET_assert (GNUNET_YES ==
                 TEAH_handle_is_ready (exchange));
  GNUNET_CRYPTO_eddsa_key_get_public (&merchant_priv->eddsa_priv,
                                      &rr.merchant.eddsa_pub);
  TALER_amount_hton (&rr.refund_amount,
                     amount);
  GNUNET_CRYPTO_eddsa_sign (&merchant_priv->eddsa_priv,
                            &rr,
                            &merchant_sig.eddsa_sig);


  {
    char pub_str[sizeof (struct TALER_CoinSpendPublicKeyP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (coin_pub,
                                         sizeof (struct
                                                 TALER_CoinSpendPublicKeyP),
                                         pub_str,
                                         sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/coins/%s/refund",
                     pub_str);
  }
  refund_obj = json_pack ("{s:o," /* amount */
                          " s:o," /* h_contract_terms */
                          " s:I," /* rtransaction id */
                          " s:o, s:o}", /* merchant_pub, merchant_sig */
                          "refund_amount", TALER_JSON_from_amount (amount),
                          "h_contract_terms", GNUNET_JSON_from_data_auto (
                            h_contract_terms),
                          "rtransaction_id", (json_int_t) rtransaction_id,
                          "merchant_pub", GNUNET_JSON_from_data_auto (
                            &rr.merchant),
                          "merchant_sig", GNUNET_JSON_from_data_auto (
                            &merchant_sig)
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
  rh->url = TEAH_path_to_url (exchange,
                              arg_str);
  rh->depconf.purpose.size = htonl (sizeof (struct TALER_RefundConfirmationPS));
  rh->depconf.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_REFUND);
  rh->depconf.h_contract_terms = *h_contract_terms;
  rh->depconf.coin_pub = *coin_pub;
  rh->depconf.merchant = rr.merchant;
  rh->depconf.rtransaction_id = GNUNET_htonll (rtransaction_id);
  TALER_amount_hton (&rh->depconf.refund_amount,
                     amount);

  eh = TALER_EXCHANGE_curl_easy_get_ (rh->url);
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&rh->ctx,
                              eh,
                              refund_obj)) )
  {
    GNUNET_break (0);
    if (NULL != eh)
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
