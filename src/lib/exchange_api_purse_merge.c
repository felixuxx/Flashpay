/*
   This file is part of TALER
   Copyright (C) 2022-2023 Taler Systems SA

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
 * @file lib/exchange_api_purse_merge.c
 * @brief Implementation of the client to merge a purse
 *        into an account
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
#include "exchange_api_common.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A purse merge with deposit handle
 */
struct TALER_EXCHANGE_AccountMergeHandle
{

  /**
   * The keys of the exchange this request handle will use
   */
  struct TALER_EXCHANGE_Keys *keys;

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
  TALER_EXCHANGE_AccountMergeCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Base URL of the provider hosting the @e reserve_pub.
   */
  char *provider_url;

  /**
   * Signature for our operation.
   */
  struct TALER_PurseMergeSignatureP merge_sig;

  /**
   * Expected value in the purse after fees.
   */
  struct TALER_Amount purse_value_after_fees;

  /**
   * Public key of the reserve public key.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Public key of the purse.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * Hash over the purse's contrac terms.
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * When does the purse expire.
   */
  struct GNUNET_TIME_Timestamp purse_expiration;

  /**
   * Our merge key.
   */
  struct TALER_PurseMergePrivateKeyP merge_priv;

  /**
   * Reserve signature affirming the merge.
   */
  struct TALER_ReserveSignatureP reserve_sig;

};


/**
 * Function called when we're done processing the
 * HTTP /purse/$PID/merge request.
 *
 * @param cls the `struct TALER_EXCHANGE_AccountMergeHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_purse_merge_finished (void *cls,
                             long response_code,
                             const void *response)
{
  struct TALER_EXCHANGE_AccountMergeHandle *pch = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_AccountMergeResponse dr = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code,
    .reserve_sig = &pch->reserve_sig
  };

  pch->job = NULL;
  switch (response_code)
  {
  case 0:
    dr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      struct TALER_Amount total_deposited;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &dr.details.ok.exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &dr.details.ok.exchange_pub),
        GNUNET_JSON_spec_timestamp ("exchange_timestamp",
                                    &dr.details.ok.etime),
        TALER_JSON_spec_amount ("merge_amount",
                                pch->purse_value_after_fees.currency,
                                &total_deposited),
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
      if (GNUNET_OK !=
          TALER_EXCHANGE_test_signing_key (pch->keys,
                                           &dr.details.ok.exchange_pub))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_EXCHANGE_PURSE_MERGE_EXCHANGE_SIGNATURE_INVALID;
        break;
      }
      if (GNUNET_OK !=
          TALER_exchange_online_purse_merged_verify (
            dr.details.ok.etime,
            pch->purse_expiration,
            &pch->purse_value_after_fees,
            &pch->purse_pub,
            &pch->h_contract_terms,
            &pch->reserve_pub,
            pch->provider_url,
            &dr.details.ok.exchange_pub,
            &dr.details.ok.exchange_sig))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_EXCHANGE_PURSE_MERGE_EXCHANGE_SIGNATURE_INVALID;
        break;
      }
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_PAYMENT_REQUIRED:
    /* purse was not (yet) full */
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
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
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    break;
  case MHD_HTTP_CONFLICT:
    {
      struct TALER_PurseMergePublicKeyP merge_pub;

      GNUNET_CRYPTO_eddsa_key_get_public (&pch->merge_priv.eddsa_priv,
                                          &merge_pub.eddsa_pub);
      if (GNUNET_OK !=
          TALER_EXCHANGE_check_purse_merge_conflict_ (
            &pch->merge_sig,
            &merge_pub,
            &pch->purse_pub,
            pch->provider_url,
            j))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      break;
    }
    break;
  case MHD_HTTP_GONE:
    /* could happen if denomination was revoked */
    /* Note: one might want to check /keys for revocation
       signature here, alas tricky in case our /keys
       is outdated => left to clients */
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS:
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_uint64 (
          "requirement_row",
          &dr.details.unavailable_for_legal_reasons.requirement_row),
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
    }
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
                "Unexpected response code %u/%d for exchange deposit\n",
                (unsigned int) response_code,
                dr.hr.ec);
    GNUNET_break_op (0);
    break;
  }
  pch->cb (pch->cb_cls,
           &dr);
  TALER_EXCHANGE_account_merge_cancel (pch);
}


struct TALER_EXCHANGE_AccountMergeHandle *
TALER_EXCHANGE_account_merge (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const char *reserve_exchange_url,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergePrivateKeyP *merge_priv,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  uint8_t min_age,
  const struct TALER_Amount *purse_value_after_fees,
  struct GNUNET_TIME_Timestamp purse_expiration,
  struct GNUNET_TIME_Timestamp merge_timestamp,
  TALER_EXCHANGE_AccountMergeCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_AccountMergeHandle *pch;
  json_t *merge_obj;
  CURL *eh;
  char arg_str[sizeof (pch->purse_pub) * 2 + 32];
  struct TALER_NormalizedPayto reserve_url;

  pch = GNUNET_new (struct TALER_EXCHANGE_AccountMergeHandle);
  pch->merge_priv = *merge_priv;
  pch->cb = cb;
  pch->cb_cls = cb_cls;
  pch->purse_pub = *purse_pub;
  pch->h_contract_terms = *h_contract_terms;
  pch->purse_expiration = purse_expiration;
  pch->purse_value_after_fees = *purse_value_after_fees;
  if (NULL == reserve_exchange_url)
    pch->provider_url = GNUNET_strdup (url);
  else
    pch->provider_url = GNUNET_strdup (reserve_exchange_url);
  GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                      &pch->reserve_pub.eddsa_pub);

  {
    char pub_str[sizeof (*purse_pub) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      purse_pub,
      sizeof (*purse_pub),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "purses/%s/merge",
                     pub_str);
  }
  reserve_url = TALER_reserve_make_payto (pch->provider_url,
                                          &pch->reserve_pub);
  if (NULL == reserve_url.normalized_payto)
  {
    GNUNET_break (0);
    GNUNET_free (pch->provider_url);
    GNUNET_free (pch);
    return NULL;
  }
  pch->url = TALER_url_join (url,
                             arg_str,
                             NULL);
  if (NULL == pch->url)
  {
    GNUNET_break (0);
    GNUNET_free (reserve_url.normalized_payto);
    GNUNET_free (pch->provider_url);
    GNUNET_free (pch);
    return NULL;
  }
  TALER_wallet_purse_merge_sign (reserve_url,
                                 merge_timestamp,
                                 purse_pub,
                                 merge_priv,
                                 &pch->merge_sig);
  {
    struct TALER_Amount zero_purse_fee;

    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (purse_value_after_fees->currency,
                                          &zero_purse_fee));
    TALER_wallet_account_merge_sign (merge_timestamp,
                                     purse_pub,
                                     purse_expiration,
                                     h_contract_terms,
                                     purse_value_after_fees,
                                     &zero_purse_fee,
                                     min_age,
                                     TALER_WAMF_MODE_MERGE_FULLY_PAID_PURSE,
                                     reserve_priv,
                                     &pch->reserve_sig);
  }
  merge_obj = GNUNET_JSON_PACK (
    TALER_JSON_pack_normalized_payto ("payto_uri",
                                      reserve_url),
    GNUNET_JSON_pack_data_auto ("merge_sig",
                                &pch->merge_sig),
    GNUNET_JSON_pack_data_auto ("reserve_sig",
                                &pch->reserve_sig),
    GNUNET_JSON_pack_timestamp ("merge_timestamp",
                                merge_timestamp));
  GNUNET_assert (NULL != merge_obj);
  GNUNET_free (reserve_url.normalized_payto);
  eh = TALER_EXCHANGE_curl_easy_get_ (pch->url);
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&pch->ctx,
                              eh,
                              merge_obj)) )
  {
    GNUNET_break (0);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (merge_obj);
    GNUNET_free (pch->provider_url);
    GNUNET_free (pch->url);
    GNUNET_free (pch);
    return NULL;
  }
  json_decref (merge_obj);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "URL for purse merge: `%s'\n",
              pch->url);
  pch->keys = TALER_EXCHANGE_keys_incref (keys);
  pch->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   pch->ctx.headers,
                                   &handle_purse_merge_finished,
                                   pch);
  return pch;
}


void
TALER_EXCHANGE_account_merge_cancel (
  struct TALER_EXCHANGE_AccountMergeHandle *pch)
{
  if (NULL != pch->job)
  {
    GNUNET_CURL_job_cancel (pch->job);
    pch->job = NULL;
  }
  GNUNET_free (pch->url);
  GNUNET_free (pch->provider_url);
  TALER_curl_easy_post_finished (&pch->ctx);
  TALER_EXCHANGE_keys_decref (pch->keys);
  GNUNET_free (pch);
}


/* end of exchange_api_purse_merge.c */
