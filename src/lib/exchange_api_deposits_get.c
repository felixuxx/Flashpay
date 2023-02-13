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
   * Hash over the wiring information of the merchant.
   */
  struct TALER_MerchantWireHashP h_wire;

  /**
   * Hash over the contract for which this deposit is made.
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * The coin's public key.  This is the value that must have been
   * signed (blindly) by the Exchange.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

};


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
        GNUNET_JSON_spec_timestamp ("execution_time",
                                    &dr.details.success.execution_time),
        TALER_JSON_spec_amount_any ("coin_contribution",
                                    &dr.details.success.coin_contribution),
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &dr.details.success.exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &dr.details.success.exchange_pub),
        GNUNET_JSON_spec_end ()
      };
      const struct TALER_EXCHANGE_Keys *key_state;

      key_state = TALER_EXCHANGE_get_keys (dwh->exchange);
      GNUNET_assert (NULL != key_state);
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
      if (GNUNET_OK !=
          TALER_EXCHANGE_test_signing_key (key_state,
                                           &dr.details.success.exchange_pub))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_EXCHANGE_DEPOSITS_GET_INVALID_SIGNATURE_BY_EXCHANGE;
        break;
      }
      if (GNUNET_OK !=
          TALER_exchange_online_confirm_wire_verify (
            &dwh->h_wire,
            &dwh->h_contract_terms,
            &dr.details.success.wtid,
            &dwh->coin_pub,
            dr.details.success.execution_time,
            &dr.details.success.coin_contribution,
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
      bool no_legi = false;
      uint32_t state32;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_timestamp ("execution_time",
                                    &dr.details.accepted.execution_time),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_uint64 ("requirement_row",
                                   &dr.details.accepted.requirement_row),
          &no_legi),
        GNUNET_JSON_spec_uint32 ("aml_decision",
                                 &state32),
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
      dr.details.accepted.aml_decision
        = (enum TALER_AmlDecisionState) state32;
      if (no_legi)
        dr.details.accepted.requirement_row = 0;
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


struct TALER_EXCHANGE_DepositGetHandle *
TALER_EXCHANGE_deposits_get (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_MerchantPrivateKeyP *merchant_priv,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  TALER_EXCHANGE_DepositGetCallback cb,
  void *cb_cls)
{
  struct TALER_MerchantPublicKeyP merchant;
  struct TALER_MerchantSignatureP merchant_sig;
  struct TALER_EXCHANGE_DepositGetHandle *dwh;
  struct GNUNET_CURL_Context *ctx;
  CURL *eh;
  char arg_str[(sizeof (struct TALER_CoinSpendPublicKeyP)
                + sizeof (struct TALER_MerchantWireHashP)
                + sizeof (struct TALER_MerchantPublicKeyP)
                + sizeof (struct TALER_PrivateContractHashP)
                + sizeof (struct TALER_MerchantSignatureP)) * 2 + 48];

  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  GNUNET_CRYPTO_eddsa_key_get_public (&merchant_priv->eddsa_priv,
                                      &merchant.eddsa_pub);
  TALER_merchant_deposit_sign (h_contract_terms,
                               h_wire,
                               coin_pub,
                               merchant_priv,
                               &merchant_sig);
  {
    char cpub_str[sizeof (struct TALER_CoinSpendPublicKeyP) * 2];
    char mpub_str[sizeof (struct TALER_MerchantPublicKeyP) * 2];
    char msig_str[sizeof (struct TALER_MerchantSignatureP) * 2];
    char chash_str[sizeof (struct TALER_PrivateContractHashP) * 2];
    char whash_str[sizeof (struct TALER_MerchantWireHashP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (h_wire,
                                         sizeof (*h_wire),
                                         whash_str,
                                         sizeof (whash_str));
    *end = '\0';
    end = GNUNET_STRINGS_data_to_string (&merchant,
                                         sizeof (merchant),
                                         mpub_str,
                                         sizeof (mpub_str));
    *end = '\0';
    end = GNUNET_STRINGS_data_to_string (h_contract_terms,
                                         sizeof (*h_contract_terms),
                                         chash_str,
                                         sizeof (chash_str));
    *end = '\0';
    end = GNUNET_STRINGS_data_to_string (coin_pub,
                                         sizeof (*coin_pub),
                                         cpub_str,
                                         sizeof (cpub_str));
    *end = '\0';
    end = GNUNET_STRINGS_data_to_string (&merchant_sig,
                                         sizeof (merchant_sig),
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
  dwh->h_wire = *h_wire;
  dwh->h_contract_terms = *h_contract_terms;
  dwh->coin_pub = *coin_pub;

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
