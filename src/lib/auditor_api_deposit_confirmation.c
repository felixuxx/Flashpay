/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * @file lib/auditor_api_deposit_confirmation.c
 * @brief Implementation of the /deposit request of the auditor's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_util.h"
#include "taler_curl_lib.h"
#include "taler_json_lib.h"
#include "taler_auditor_service.h"
#include "taler_signatures.h"
#include "auditor_api_curl_defaults.h"


/**
 * @brief A DepositConfirmation Handle
 */
struct TALER_AUDITOR_DepositConfirmationHandle
{

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
  TALER_AUDITOR_DepositConfirmationResultCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * Function called when we're done processing the
 * HTTP /deposit-confirmation request.
 *
 * @param cls the `struct TALER_AUDITOR_DepositConfirmationHandle`
 * @param response_code HTTP response code, 0 on error
 * @param djson parsed JSON result, NULL on error
 */
static void
handle_deposit_confirmation_finished (void *cls,
                                      long response_code,
                                      const void *djson)
{
  const json_t *json = djson;
  struct TALER_AUDITOR_DepositConfirmationHandle *dh = cls;
  struct TALER_AUDITOR_DepositConfirmationResponse dcr = {
    .hr.reply = json,
    .hr.http_status = (unsigned int) response_code
  };

  dh->job = NULL;
  switch (response_code)
  {
  case 0:
    dcr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    dcr.hr.ec = TALER_EC_NONE;
    break;
  case MHD_HTTP_BAD_REQUEST:
    dcr.hr.ec = TALER_JSON_get_error_code (json);
    dcr.hr.hint = TALER_JSON_get_error_hint (json);
    /* This should never happen, either us or the auditor is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    dcr.hr.ec = TALER_JSON_get_error_code (json);
    dcr.hr.hint = TALER_JSON_get_error_hint (json);
    /* Nothing really to verify, auditor says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    dcr.hr.ec = TALER_JSON_get_error_code (json);
    dcr.hr.hint = TALER_JSON_get_error_hint (json);
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    break;
  case MHD_HTTP_GONE:
    dcr.hr.ec = TALER_JSON_get_error_code (json);
    dcr.hr.hint = TALER_JSON_get_error_hint (json);
    /* Nothing really to verify, auditor says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    dcr.hr.ec = TALER_JSON_get_error_code (json);
    dcr.hr.hint = TALER_JSON_get_error_hint (json);
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    dcr.hr.ec = TALER_JSON_get_error_code (json);
    dcr.hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for auditor deposit confirmation\n",
                (unsigned int) response_code,
                dcr.hr.ec);
    break;
  }
  dh->cb (dh->cb_cls,
          &dcr);
  TALER_AUDITOR_deposit_confirmation_cancel (dh);
}


/**
 * Verify signature information about the deposit-confirmation.
 *
 * @param h_wire hash of merchant wire details
 * @param h_policy hash over the policy extension, if any
 * @param h_contract_terms hash of the contact of the merchant with the customer (further details are never disclosed to the auditor)
 * @param exchange_timestamp timestamp when the deposit was received by the wallet
 * @param wire_deadline by what time must the amount be wired to the merchant
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the auditor (can be zero if refunds are not allowed); must not be after the @a wire_deadline
 * @param amount_without_fee the amount confirmed to be wired by the exchange to the merchant
 * @param num_coins number of coins involved
 * @param coin_sigs array of @a num_coins coin signatures
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param exchange_sig the signature made with purpose #TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT
 * @param exchange_pub the public key of the exchange that matches @a exchange_sig
 * @param master_pub master public key of the exchange
 * @param ep_start when does @a exchange_pub validity start
 * @param ep_expire when does @a exchange_pub usage end
 * @param ep_end when does @a exchange_pub legal validity end
 * @param master_sig master signature affirming validity of @a exchange_pub
 * @return #GNUNET_OK if signatures are OK, #GNUNET_SYSERR if not
 */
static enum GNUNET_GenericReturnValue
verify_signatures (
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_ExtensionPolicyHashP *h_policy,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  struct GNUNET_TIME_Timestamp exchange_timestamp,
  struct GNUNET_TIME_Timestamp wire_deadline,
  struct GNUNET_TIME_Timestamp refund_deadline,
  const struct TALER_Amount *amount_without_fee,
  unsigned int num_coins,
  const struct TALER_CoinSpendSignatureP *coin_sigs[
    static num_coins],
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_ExchangeSignatureP *exchange_sig,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct GNUNET_TIME_Timestamp ep_start,
  struct GNUNET_TIME_Timestamp ep_expire,
  struct GNUNET_TIME_Timestamp ep_end,
  const struct TALER_MasterSignatureP *master_sig)
{
  if (GNUNET_OK !=
      TALER_exchange_online_deposit_confirmation_verify (
        h_contract_terms,
        h_wire,
        h_policy,
        exchange_timestamp,
        wire_deadline,
        refund_deadline,
        amount_without_fee,
        num_coins,
        coin_sigs,
        merchant_pub,
        exchange_pub,
        exchange_sig))
  {
    GNUNET_break_op (0);
    TALER_LOG_WARNING (
      "Invalid signature on /deposit-confirmation request!\n");
    {
      TALER_LOG_DEBUG ("... amount_without_fee was %s\n",
                       TALER_amount2s (amount_without_fee));
    }
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      TALER_exchange_offline_signkey_validity_verify (
        exchange_pub,
        ep_start,
        ep_expire,
        ep_end,
        master_pub,
        master_sig))
  {
    GNUNET_break (0);
    TALER_LOG_WARNING ("Invalid signature on exchange signing key!\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_TIME_absolute_is_past (ep_end.abs_time))
  {
    GNUNET_break (0);
    TALER_LOG_WARNING ("Exchange signing key is no longer valid!\n");
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


struct TALER_AUDITOR_DepositConfirmationHandle *
TALER_AUDITOR_deposit_confirmation (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_ExtensionPolicyHashP *h_policy,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  struct GNUNET_TIME_Timestamp exchange_timestamp,
  struct GNUNET_TIME_Timestamp wire_deadline,
  struct GNUNET_TIME_Timestamp refund_deadline,
  const struct TALER_Amount *total_without_fee,
  unsigned int num_coins,
  const struct TALER_CoinSpendPublicKeyP *coin_pubs[
    static num_coins],
  const struct TALER_CoinSpendSignatureP *coin_sigs[
    static num_coins],
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_ExchangeSignatureP *exchange_sig,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct GNUNET_TIME_Timestamp ep_start,
  struct GNUNET_TIME_Timestamp ep_expire,
  struct GNUNET_TIME_Timestamp ep_end,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_AUDITOR_DepositConfirmationResultCallback cb,
  void *cb_cls)
{
  struct TALER_AUDITOR_DepositConfirmationHandle *dh;
  json_t *deposit_confirmation_obj;
  CURL *eh;
  json_t *jcoin_sigs;
  json_t *jcoin_pubs;

  if (0 == num_coins)
  {
    GNUNET_break (0);
    return NULL;
  }
  if (GNUNET_OK !=
      verify_signatures (h_wire,
                         h_policy,
                         h_contract_terms,
                         exchange_timestamp,
                         wire_deadline,
                         refund_deadline,
                         total_without_fee,
                         num_coins,
                         coin_sigs,
                         merchant_pub,
                         exchange_pub,
                         exchange_sig,
                         master_pub,
                         ep_start,
                         ep_expire,
                         ep_end,
                         master_sig))
  {
    GNUNET_break_op (0);
    return NULL;
  }
  jcoin_sigs = json_array ();
  GNUNET_assert (NULL != jcoin_sigs);
  jcoin_pubs = json_array ();
  GNUNET_assert (NULL != jcoin_pubs);
  for (unsigned int i = 0; i<num_coins; i++)
  {
    GNUNET_assert (0 ==
                   json_array_append_new (jcoin_sigs,
                                          GNUNET_JSON_from_data_auto (
                                            coin_sigs[i])));
    GNUNET_assert (0 ==
                   json_array_append_new (jcoin_pubs,
                                          GNUNET_JSON_from_data_auto (
                                            coin_pubs[i])));
  }
  deposit_confirmation_obj
    = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_auto ("h_wire",
                                    h_wire),
        GNUNET_JSON_pack_data_auto ("h_policy",
                                    h_policy),
        GNUNET_JSON_pack_data_auto ("h_contract_terms",
                                    h_contract_terms),
        GNUNET_JSON_pack_timestamp ("exchange_timestamp",
                                    exchange_timestamp),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_timestamp ("refund_deadline",
                                      refund_deadline)),
        GNUNET_JSON_pack_timestamp ("wire_deadline",
                                    wire_deadline),
        TALER_JSON_pack_amount ("total_without_fee",
                                total_without_fee),
        GNUNET_JSON_pack_array_steal ("coin_pubs",
                                      jcoin_pubs),
        GNUNET_JSON_pack_array_steal ("coin_sigs",
                                      jcoin_sigs),
        GNUNET_JSON_pack_data_auto ("merchant_pub",
                                    merchant_pub),
        GNUNET_JSON_pack_data_auto ("exchange_sig",
                                    exchange_sig),
        GNUNET_JSON_pack_data_auto ("master_pub",
                                    master_pub),
        GNUNET_JSON_pack_timestamp ("ep_start",
                                    ep_start),
        GNUNET_JSON_pack_timestamp ("ep_expire",
                                    ep_expire),
        GNUNET_JSON_pack_timestamp ("ep_end",
                                    ep_end),
        GNUNET_JSON_pack_data_auto ("master_sig",
                                    master_sig),
        GNUNET_JSON_pack_data_auto ("exchange_pub",
                                    exchange_pub));
  dh = GNUNET_new (struct TALER_AUDITOR_DepositConfirmationHandle);
  dh->cb = cb;
  dh->cb_cls = cb_cls;
  dh->url = TALER_url_join (url,
                            "deposit-confirmation",
                            NULL);
  if (NULL == dh->url)
  {
    GNUNET_free (dh);
    return NULL;
  }
  eh = TALER_AUDITOR_curl_easy_get_ (dh->url);
  if ( (NULL == eh) ||
       (CURLE_OK !=
        curl_easy_setopt (eh,
                          CURLOPT_CUSTOMREQUEST,
                          "PUT")) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&dh->ctx,
                              eh,
                              deposit_confirmation_obj)) )
  {
    GNUNET_break (0);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (deposit_confirmation_obj);
    GNUNET_free (dh->url);
    GNUNET_free (dh);
    return NULL;
  }
  json_decref (deposit_confirmation_obj);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "URL for deposit-confirmation: `%s'\n",
              dh->url);
  dh->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  dh->ctx.headers,
                                  &handle_deposit_confirmation_finished,
                                  dh);
  {
    /* Disable 100 continue processing */
    struct curl_slist *x_headers;

    x_headers = curl_slist_append (NULL,
                                   "Expect:");
    GNUNET_CURL_extend_headers (dh->job,
                                x_headers);
    curl_slist_free_all (x_headers);
  }
  return dh;
}


void
TALER_AUDITOR_deposit_confirmation_cancel (
  struct TALER_AUDITOR_DepositConfirmationHandle *deposit_confirmation)
{
  if (NULL != deposit_confirmation->job)
  {
    GNUNET_CURL_job_cancel (deposit_confirmation->job);
    deposit_confirmation->job = NULL;
  }
  GNUNET_free (deposit_confirmation->url);
  TALER_curl_easy_post_finished (&deposit_confirmation->ctx);
  GNUNET_free (deposit_confirmation);
}


/* end of auditor_api_deposit_confirmation.c */
