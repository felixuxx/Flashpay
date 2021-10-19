/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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
 * @file lib/exchange_api_deposits_get.c
 * @brief Implementation of the /deposits/ GET request
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
 * @brief A Deposit Get Handle
 */
struct TALER_EXCHANGE_DepositGetHandle
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
  TALER_EXCHANGE_DepositGetCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Information the exchange should sign in response.
   * (with pre-filled fields from the request).
   */
  struct TALER_ConfirmWirePS depconf;

};


/**
 * Verify that the signature on the "200 OK" response
 * from the exchange is valid.
 *
 * @param dwh deposit wtid handle
 * @param json json reply with the signature
 * @param exchange_pub the exchange's public key
 * @param exchange_sig the exchange's signature
 * @return #GNUNET_OK if the signature is valid, #GNUNET_SYSERR if not
 */
static enum GNUNET_GenericReturnValue
verify_deposit_wtid_signature_ok (
  const struct TALER_EXCHANGE_DepositGetHandle *dwh,
  const json_t *json,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_ExchangeSignatureP *exchange_sig)
{
  const struct TALER_EXCHANGE_Keys *key_state;

  key_state = TALER_EXCHANGE_get_keys (dwh->exchange);
  if (GNUNET_OK !=
      TALER_EXCHANGE_test_signing_key (key_state,
                                       exchange_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE,
                                  &dwh->depconf,
                                  &exchange_sig->eddsa_signature,
                                  &exchange_pub->eddsa_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /track/transaction request.
 *
 * @param cls the `struct TALER_EXCHANGE_DepositGetHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_deposit_wtid_finished (void *cls,
                              long response_code,
                              const void *response)
{
  struct TALER_EXCHANGE_DepositGetHandle *dwh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_GetDepositResponse dr = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  dwh->job = NULL;
  switch (response_code)
  {
  case 0:
    dr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("wtid",
                                     &dr.details.success.wtid),
        TALER_JSON_spec_absolute_time ("execution_time",
                                       &dr.details.success.execution_time),
        TALER_JSON_spec_amount_any ("coin_contribution",
                                    &dr.details.success.coin_contribution),
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &dr.details.success.exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &dr.details.success.exchange_pub),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      dwh->depconf.execution_time = GNUNET_TIME_absolute_hton (
        dr.details.success.execution_time);
      dwh->depconf.wtid = dr.details.success.wtid;
      TALER_amount_hton (&dwh->depconf.coin_contribution,
                         &dr.details.success.coin_contribution);
      if (GNUNET_OK !=
          verify_deposit_wtid_signature_ok (dwh,
                                            j,
                                            &dr.details.success.exchange_pub,
                                            &dr.details.success.exchange_sig))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_EXCHANGE_DEPOSITS_GET_INVALID_SIGNATURE_BY_EXCHANGE;
        break;
      }
      dwh->cb (dwh->cb_cls,
               &dr);
      TALER_EXCHANGE_deposits_get_cancel (dwh);
      return;
    }
  case MHD_HTTP_ACCEPTED:
    {
      /* Transaction known, but not executed yet */
      struct GNUNET_JSON_Specification spec[] = {
        TALER_JSON_spec_absolute_time ("execution_time",
                                       &dr.details.accepted.execution_time),
        GNUNET_JSON_spec_uint64 ("payment_target_uuid",
                                 &dr.details.accepted.payment_target_uuid),
        GNUNET_JSON_spec_bool ("kyc_ok",
                               &dr.details.accepted.kyc_ok),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      dwh->cb (dwh->cb_cls,
               &dr);
      TALER_EXCHANGE_deposits_get_cancel (dwh);
      return;
    }
  case MHD_HTTP_BAD_REQUEST:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Exchange does not know about transaction;
       we should pass the reply to the application */
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange GET deposits\n",
                (unsigned int) response_code,
                (int) dr.hr.ec);
    GNUNET_break_op (0);
    break;
  }
  dwh->cb (dwh->cb_cls,
           &dr);
  TALER_EXCHANGE_deposits_get_cancel (dwh);
}


/**
 * Obtain wire transfer details about an existing deposit operation.
 *
 * @param exchange the exchange to query
 * @param merchant_priv the merchant's private key
 * @param h_wire hash of merchant's wire transfer details
 * @param h_contract_terms hash of the proposal data from the contract
 *                        between merchant and customer
 * @param coin_pub public key of the coin
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to abort request
 */
struct TALER_EXCHANGE_DepositGetHandle *
TALER_EXCHANGE_deposits_get (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_MerchantPrivateKeyP *merchant_priv,
  const struct GNUNET_HashCode *h_wire,
  const struct GNUNET_HashCode *h_contract_terms,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  TALER_EXCHANGE_DepositGetCallback cb,
  void *cb_cls)
{
  struct TALER_DepositTrackPS dtp;
  struct TALER_MerchantSignatureP merchant_sig;
  struct TALER_EXCHANGE_DepositGetHandle *dwh;
  struct GNUNET_CURL_Context *ctx;
  CURL *eh;
  char arg_str[(sizeof (struct TALER_CoinSpendPublicKeyP)
                + sizeof (struct GNUNET_HashCode)
                + sizeof (struct TALER_MerchantPublicKeyP)
                + sizeof (struct GNUNET_HashCode)
                + sizeof (struct TALER_MerchantSignatureP)) * 2 + 48];

  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  dtp.purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_TRACK_TRANSACTION);
  dtp.purpose.size = htonl (sizeof (dtp));
  dtp.h_contract_terms = *h_contract_terms;
  dtp.h_wire = *h_wire;
  GNUNET_CRYPTO_eddsa_key_get_public (&merchant_priv->eddsa_priv,
                                      &dtp.merchant.eddsa_pub);

  dtp.coin_pub = *coin_pub;
  GNUNET_CRYPTO_eddsa_sign (&merchant_priv->eddsa_priv,
                            &dtp,
                            &merchant_sig.eddsa_sig);
  {
    char cpub_str[sizeof (struct TALER_CoinSpendPublicKeyP) * 2];
    char mpub_str[sizeof (struct TALER_MerchantPublicKeyP) * 2];
    char msig_str[sizeof (struct TALER_MerchantSignatureP) * 2];
    char chash_str[sizeof (struct GNUNET_HashCode) * 2];
    char whash_str[sizeof (struct GNUNET_HashCode) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (h_wire,
                                         sizeof (struct
                                                 GNUNET_HashCode),
                                         whash_str,
                                         sizeof (whash_str));
    *end = '\0';
    end = GNUNET_STRINGS_data_to_string (&dtp.merchant,
                                         sizeof (struct
                                                 TALER_MerchantPublicKeyP),
                                         mpub_str,
                                         sizeof (mpub_str));
    *end = '\0';
    end = GNUNET_STRINGS_data_to_string (h_contract_terms,
                                         sizeof (struct
                                                 GNUNET_HashCode),
                                         chash_str,
                                         sizeof (chash_str));
    *end = '\0';
    end = GNUNET_STRINGS_data_to_string (coin_pub,
                                         sizeof (struct
                                                 TALER_CoinSpendPublicKeyP),
                                         cpub_str,
                                         sizeof (cpub_str));
    *end = '\0';
    end = GNUNET_STRINGS_data_to_string (&merchant_sig,
                                         sizeof (struct
                                                 TALER_MerchantSignatureP),
                                         msig_str,
                                         sizeof (msig_str));
    *end = '\0';

    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/deposits/%s/%s/%s/%s?merchant_sig=%s",
                     whash_str,
                     mpub_str,
                     chash_str,
                     cpub_str,
                     msig_str);
  }

  dwh = GNUNET_new (struct TALER_EXCHANGE_DepositGetHandle);
  dwh->exchange = exchange;
  dwh->cb = cb;
  dwh->cb_cls = cb_cls;
  dwh->url = TEAH_path_to_url (exchange,
                               arg_str);
  if (NULL == dwh->url)
  {
    GNUNET_free (dwh);
    return NULL;
  }
  dwh->depconf.purpose.size = htonl (sizeof (struct TALER_ConfirmWirePS));
  dwh->depconf.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE);
  dwh->depconf.h_wire = *h_wire;
  dwh->depconf.h_contract_terms = *h_contract_terms;
  dwh->depconf.coin_pub = *coin_pub;

  eh = TALER_EXCHANGE_curl_easy_get_ (dwh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (dwh->url);
    GNUNET_free (dwh);
    return NULL;
  }
  ctx = TEAH_handle_to_context (exchange);
  dwh->job = GNUNET_CURL_job_add (ctx,
                                  eh,
                                  &handle_deposit_wtid_finished,
                                  dwh);
  return dwh;
}


/**
 * Cancel /deposits/$WTID request.  This function cannot be used on a request
 * handle if a response is already served for it.
 *
 * @param dwh the wire deposits request handle
 */
void
TALER_EXCHANGE_deposits_get_cancel (struct TALER_EXCHANGE_DepositGetHandle *dwh)
{
  if (NULL != dwh->job)
  {
    GNUNET_CURL_job_cancel (dwh->job);
    dwh->job = NULL;
  }
  GNUNET_free (dwh->url);
  TALER_curl_easy_post_finished (&dwh->ctx);
  GNUNET_free (dwh);
}


/* end of exchange_api_deposits_get.c */
