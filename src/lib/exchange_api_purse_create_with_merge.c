/*
   This file is part of TALER
   Copyright (C) 2022 Taler Systems SA

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
 * @file lib/exchange_api_purse_create_with_merge.c
 * @brief Implementation of the client to create a
 *        purse for an account
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
 * @brief A purse create with merge handle
 */
struct TALER_EXCHANGE_PurseCreateMergeHandle
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
  TALER_EXCHANGE_PurseCreateMergeCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

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
   * When does the purse get merged/created.
   */
  struct GNUNET_TIME_Timestamp merge_timestamp;
};


/**
 * Function called when we're done processing the
 * HTTP /reserves/$RID/purse request.
 *
 * @param cls the `struct TALER_EXCHANGE_PurseCreateMergeHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_purse_create_with_merge_finished (void *cls,
                                         long response_code,
                                         const void *response)
{
  struct TALER_EXCHANGE_PurseCreateMergeHandle *pcm = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_PurseCreateMergeResponse dr = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  pcm->job = NULL;
  switch (response_code)
  {
  case 0:
    dr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
#if FIXME
      const struct TALER_EXCHANGE_Keys *key_state;
      struct GNUNET_TIME_Timestamp etime;
      struct TALER_Amount total_deposited;
      struct TALER_ExchangeSignatureP exchange_sig;
      struct TALER_ExchangePublicKeyP exchange_pub;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &exchange_pub),
        GNUNET_JSON_spec_timestamp ("exchange_timestamp",
                                    &etime),
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
      key_state = TALER_EXCHANGE_get_keys (pcm->exchange);
      if (GNUNET_OK !=
          TALER_EXCHANGE_test_signing_key (key_state,
                                           &exchange_pub))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec =
          TALER_EC_EXCHANGE_PURSE_CREATE_WITH_MERGE_EXCHANGE_SIGNATURE_INVALID;
        break;
      }
      if (GNUNET_OK !=
          TALER_exchange_online_purse_create_with_merged_verify (
            etime,
            pcm->purse_expiration,
            &pcm->purse_value_after_fees,
            &pcm->purse_pub,
            &pcm->h_contract_terms,
            &pcm->reserve_pub,
            pcm->provider_url,
            &exchange_pub,
            &exchange_sig))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec =
          TALER_EC_EXCHANGE_PURSE_CREATE_WITH_MERGE_EXCHANGE_SIGNATURE_INVALID;
        break;
      }
#endif
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
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
    // FIXME: check reply!
    break;
  case MHD_HTTP_GONE:
    /* could happen if denomination was revoked */
    /* Note: one might want to check /keys for revocation
       signature here, alas tricky in case our /keys
       is outdated => left to clients */
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
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
  pcm->cb (pcm->cb_cls,
           &dr);
  TALER_EXCHANGE_purse_create_with_merge_cancel (pcm);
}


struct TALER_EXCHANGE_PurseCreateMergeHandle *
TALER_EXCHANGE_purse_create_with_merge (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  const struct TALER_PurseContractPrivateKeyP *purse_priv,
  const struct TALER_PurseMergePrivateKeyP *merge_priv,
  const struct TALER_ContractDiffiePrivateP *contract_priv,
  const json_t *contract_terms,
  bool upload_contract,
  struct GNUNET_TIME_Timestamp merge_timestamp,
  TALER_EXCHANGE_PurseCreateMergeCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_PurseCreateMergeHandle *pcm;
  struct GNUNET_CURL_Context *ctx;
  json_t *create_with_merge_obj;
  CURL *eh;
  struct TALER_ReserveSignatureP reserve_sig;
  char arg_str[sizeof (pcm->reserve_pub) * 2 + 32];
  uint32_t min_age = 0;
  struct TALER_PurseMergePublicKeyP merge_pub;
  struct TALER_PurseMergeSignatureP merge_sig;
  struct TALER_ContractDiffiePublicP contract_pub;
  struct TALER_PurseContractSignatureP contract_sig;
  struct TALER_PurseContractSignatureP purse_sig;
  void *econtract = NULL;
  size_t econtract_size = 0;
  struct TALER_Amount purse_value_after_fees;

  pcm = GNUNET_new (struct TALER_EXCHANGE_PurseCreateMergeHandle);
  pcm->exchange = exchange;
  pcm->cb = cb;
  pcm->cb_cls = cb_cls;
  if (GNUNET_OK !=
      TALER_JSON_contract_hash (contract_terms,
                                &pcm->h_contract_terms))
  {
    GNUNET_break (0);
    GNUNET_free (pcm);
    return NULL;
  }
  pcm->h_contract_terms = pcm->h_contract_terms;
  pcm->merge_timestamp = merge_timestamp;
  GNUNET_CRYPTO_eddsa_key_get_public (&purse_priv->eddsa_priv,
                                      &pcm->purse_pub.eddsa_pub);
  GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                      &pcm->reserve_pub.eddsa_pub);
  GNUNET_CRYPTO_eddsa_key_get_public (&merge_priv->eddsa_priv,
                                      &merge_pub.eddsa_pub);
  GNUNET_CRYPTO_ecdhe_key_get_public (&contract_priv->ecdhe_priv,
                                      &contract_pub.ecdhe_pub);

  {
    // FIXME: get purse expiration time from contract?
    struct GNUNET_JSON_Specification spec[] = {
      TALER_JSON_spec_amount_any ("amount",
                                  &pcm->purse_value_after_fees),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_uint32 ("minimum_age",
                                 &min_age),
        NULL),
      // FIXME: correct field name?
      GNUNET_JSON_spec_timestamp ("payment_deadline",
                                  &pcm->purse_expiration),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (contract_terms,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break (0);
      GNUNET_free (pcm);
      return NULL;
    }
  }


  GNUNET_assert (GNUNET_YES ==
                 TEAH_handle_is_ready (exchange));
  {
    char pub_str[sizeof (pcm->reserve_pub) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &pcm->reserve_pub,
      sizeof (pcm->reserve_pub),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/reserves/%s/purse",
                     pub_str);
  }
  pcm->url = TEAH_path_to_url (exchange,
                               arg_str);
  if (NULL == pcm->url)
  {
    GNUNET_break (0);
    GNUNET_free (pcm);
    return NULL;
  }
  TALER_wallet_purse_create_sign (pcm->purse_expiration,
                                  &pcm->h_contract_terms,
                                  &merge_pub,
                                  min_age,
                                  &pcm->purse_value_after_fees,
                                  purse_priv,
                                  &purse_sig);
  TALER_wallet_purse_merge_sign (exchange->url,
                                 merge_timestamp,
                                 &pcm->purse_pub,
                                 merge_priv,
                                 &merge_sig);
  TALER_wallet_account_merge_sign (merge_timestamp,
                                   &pcm->purse_pub,
                                   pcm->purse_expiration,
                                   &pcm->h_contract_terms,
                                   &pcm->purse_value_after_fees,
                                   min_age,
                                   reserve_priv,
                                   &reserve_sig);
  if (upload_contract)
  {
    TALER_CRYPTO_contract_encrypt_for_deposit (
      &pcm->purse_pub,
      contract_priv,
      contract_terms,
      &econtract,
      &econtract_size);
    TALER_wallet_econtract_upload_sign (
      econtract,
      econtract_size,
      &contract_pub,
      purse_priv,
      &contract_sig);
  }
  create_with_merge_obj = GNUNET_JSON_PACK (
    TALER_JSON_pack_amount ("purse_value",
                            &purse_value_after_fees),
    GNUNET_JSON_pack_uint64 ("min_age",
                             min_age),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_data_varsize ("econtract",
                                     econtract,
                                     econtract_size)),
    GNUNET_JSON_pack_allow_null (
      upload_contract
      ? GNUNET_JSON_pack_data_auto ("econtract_sig",
                                    &contract_sig)
      : GNUNET_JSON_pack_string ("dummy",
                                 NULL)),
    GNUNET_JSON_pack_allow_null (
      upload_contract
      ? GNUNET_JSON_pack_data_auto ("contract_pub",
                                    &contract_pub)
      : GNUNET_JSON_pack_string ("dummy",
                                 NULL)),
    GNUNET_JSON_pack_data_auto ("merge_pub",
                                &merge_pub),
    GNUNET_JSON_pack_data_auto ("merge_sig",
                                &merge_sig),
    GNUNET_JSON_pack_data_auto ("reserve_sig",
                                &reserve_sig),
    GNUNET_JSON_pack_data_auto ("purse_pub",
                                &pcm->purse_pub),
    GNUNET_JSON_pack_data_auto ("purse_sig",
                                &purse_sig),
    GNUNET_JSON_pack_data_auto ("h_contract_terms",
                                &pcm->h_contract_terms),
    GNUNET_JSON_pack_timestamp ("merge_timestamp",
                                merge_timestamp),
    GNUNET_JSON_pack_timestamp ("purse_expiration",
                                pcm->purse_expiration));
  GNUNET_assert (NULL != create_with_merge_obj);
  GNUNET_free (econtract);
  eh = TALER_EXCHANGE_curl_easy_get_ (pcm->url);
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&pcm->ctx,
                              eh,
                              create_with_merge_obj)) )
  {
    GNUNET_break (0);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (create_with_merge_obj);
    GNUNET_free (pcm->url);
    GNUNET_free (pcm);
    return NULL;
  }
  json_decref (create_with_merge_obj);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "URL for purse create_with_merge: `%s'\n",
              pcm->url);
  ctx = TEAH_handle_to_context (exchange);
  pcm->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   pcm->ctx.headers,
                                   &handle_purse_create_with_merge_finished,
                                   pcm);
  return pcm;
}


void
TALER_EXCHANGE_purse_create_with_merge_cancel (
  struct TALER_EXCHANGE_PurseCreateMergeHandle *pcm)
{
  if (NULL != pcm->job)
  {
    GNUNET_CURL_job_cancel (pcm->job);
    pcm->job = NULL;
  }
  GNUNET_free (pcm->url);
  TALER_curl_easy_post_finished (&pcm->ctx);
  GNUNET_free (pcm);
}


/* end of exchange_api_purse_create_with_merge.c */
