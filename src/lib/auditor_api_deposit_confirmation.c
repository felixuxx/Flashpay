/*
  This file is part of TALER
  Copyright (C) 2014-2018 Taler Systems SA

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
#include "taler_json_lib.h"
#include "taler_auditor_service.h"
#include "auditor_api_handle.h"
#include "taler_signatures.h"
#include "auditor_api_curl_defaults.h"


/**
 * @brief A DepositConfirmation Handle
 */
struct TALER_AUDITOR_DepositConfirmationHandle
{

  /**
   * The connection to auditor this request handle will use
   */
  struct TALER_AUDITOR_Handle *auditor;

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

  dh->job = NULL;
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the auditor is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Nothing really to verify, auditor says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
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
  dh->cb (dh->cb_cls,
          response_code,
          TALER_JSON_get_error_code (json),
          json);
  TALER_AUDITOR_deposit_confirmation_cancel (dh);
}


/**
 * Verify signature information about the deposit-confirmation.
 *
 * @param h_wire hash of merchant wire details
 * @param h_contract_terms hash of the contact of the merchant with the customer (further details are never disclosed to the auditor)
 * @param timestamp timestamp when the contract was finalized, must not be too far in the future
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the auditor (can be zero if refunds are not allowed); must not be after the @a wire_deadline
 * @param amount_without_fee the amount confirmed to be wired by the exchange to the merchant
 * @param coin_pub coin’s public key
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
static int
verify_signatures (const struct GNUNET_HashCode *h_wire,
                   const struct GNUNET_HashCode *h_contract_terms,
                   struct GNUNET_TIME_Absolute timestamp,
                   struct GNUNET_TIME_Absolute refund_deadline,
                   const struct TALER_Amount *amount_without_fee,
                   const struct TALER_CoinSpendPublicKeyP *coin_pub,
                   const struct TALER_MerchantPublicKeyP *merchant_pub,
                   const struct TALER_ExchangePublicKeyP *exchange_pub,
                   const struct TALER_ExchangeSignatureP *exchange_sig,
                   const struct TALER_MasterPublicKeyP *master_pub,
                   struct GNUNET_TIME_Absolute ep_start,
                   struct GNUNET_TIME_Absolute ep_expire,
                   struct GNUNET_TIME_Absolute ep_end,
                   const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_DepositConfirmationPS dc;
  struct TALER_ExchangeSigningKeyValidityPS sv;

  dc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT);
  dc.purpose.size = htonl (sizeof (struct TALER_DepositConfirmationPS));
  dc.h_contract_terms = *h_contract_terms;
  dc.h_wire = *h_wire;
  dc.timestamp = GNUNET_TIME_absolute_hton (timestamp);
  dc.refund_deadline = GNUNET_TIME_absolute_hton (refund_deadline);
  TALER_amount_hton (&dc.amount_without_fee,
                     amount_without_fee);
  dc.coin_pub = *coin_pub;
  dc.merchant = *merchant_pub;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT,
                                  &dc.purpose,
                                  &exchange_sig->eddsa_signature,
                                  &exchange_pub->eddsa_pub))
  {
    GNUNET_break_op (0);
    TALER_LOG_WARNING ("Invalid signature on /deposit-confirmation request!\n");
    {
      TALER_LOG_DEBUG ("... amount_without_fee was %s\n",
                       TALER_amount2s (amount_without_fee));
    }
    return GNUNET_SYSERR;
  }
  sv.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY);
  sv.purpose.size = htonl (sizeof (struct TALER_ExchangeSigningKeyValidityPS));
  sv.master_public_key = *master_pub;
  sv.start = GNUNET_TIME_absolute_hton (ep_start);
  sv.expire = GNUNET_TIME_absolute_hton (ep_expire);
  sv.end = GNUNET_TIME_absolute_hton (ep_end);
  sv.signkey_pub = *exchange_pub;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY,
                                  &sv.purpose,
                                  &master_sig->eddsa_signature,
                                  &master_pub->eddsa_pub))
  {
    GNUNET_break (0);
    TALER_LOG_WARNING ("Invalid signature on exchange signing key!\n");
    return GNUNET_SYSERR;
  }
  if (0 == GNUNET_TIME_absolute_get_remaining (ep_end).rel_value_us)
  {
    GNUNET_break (0);
    TALER_LOG_WARNING ("Exchange signing key is no longer valid!\n");
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Submit a deposit-confirmation permission to the auditor and get the
 * auditor's response.  Note that while we return the response
 * verbatim to the caller for further processing, we do already verify
 * that the response is well-formed.  If the auditor's reply is not
 * well-formed, we return an HTTP status code of zero to @a cb.
 *
 * We also verify that the @a exchange_sig is valid for this deposit-confirmation
 * request, and that the @a master_sig is a valid signature for @a
 * exchange_pub.  Also, the @a auditor must be ready to operate (i.e.  have
 * finished processing the /version reply).  If either check fails, we do
 * NOT initiate the transaction with the auditor and instead return NULL.
 *
 * @param auditor the auditor handle; the auditor must be ready to operate
 * @param h_wire hash of merchant wire details
 * @param h_contract_terms hash of the contact of the merchant with the customer (further details are never disclosed to the auditor)
 * @param timestamp timestamp when the contract was finalized, must not be too far in the future
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the auditor (can be zero if refunds are not allowed); must not be after the @a wire_deadline
 * @param amount_without_fee the amount confirmed to be wired by the exchange to the merchant
 * @param coin_pub coin’s public key
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param exchange_sig the signature made with purpose #TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT
 * @param exchange_pub the public key of the exchange that matches @a exchange_sig
 * @param master_pub master public key of the exchange
 * @param ep_start when does @a exchange_pub validity start
 * @param ep_expire when does @a exchange_pub usage end
 * @param ep_end when does @a exchange_pub legal validity end
 * @param master_sig master signature affirming validity of @a exchange_pub
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_AUDITOR_DepositConfirmationHandle *
TALER_AUDITOR_deposit_confirmation (struct TALER_AUDITOR_Handle *auditor,
                                    const struct GNUNET_HashCode *h_wire,
                                    const struct
                                    GNUNET_HashCode *h_contract_terms,
                                    struct GNUNET_TIME_Absolute timestamp,
                                    struct GNUNET_TIME_Absolute refund_deadline,
                                    const struct
                                    TALER_Amount *amount_without_fee,
                                    const struct
                                    TALER_CoinSpendPublicKeyP *coin_pub,
                                    const struct
                                    TALER_MerchantPublicKeyP *merchant_pub,
                                    const struct
                                    TALER_ExchangePublicKeyP *exchange_pub,
                                    const struct
                                    TALER_ExchangeSignatureP *exchange_sig,
                                    const struct
                                    TALER_MasterPublicKeyP *master_pub,
                                    struct GNUNET_TIME_Absolute ep_start,
                                    struct GNUNET_TIME_Absolute ep_expire,
                                    struct GNUNET_TIME_Absolute ep_end,
                                    const struct
                                    TALER_MasterSignatureP *master_sig,
                                    TALER_AUDITOR_DepositConfirmationResultCallback
                                    cb,
                                    void *cb_cls)
{
  struct TALER_AUDITOR_DepositConfirmationHandle *dh;
  struct GNUNET_CURL_Context *ctx;
  json_t *deposit_confirmation_obj;
  CURL *eh;

  (void) GNUNET_TIME_round_abs (&timestamp);
  (void) GNUNET_TIME_round_abs (&refund_deadline);
  (void) GNUNET_TIME_round_abs (&ep_start);
  (void) GNUNET_TIME_round_abs (&ep_expire);
  (void) GNUNET_TIME_round_abs (&ep_end);
  GNUNET_assert (GNUNET_YES ==
                 MAH_handle_is_ready (auditor));
  if (GNUNET_OK !=
      verify_signatures (h_wire,
                         h_contract_terms,
                         timestamp,
                         refund_deadline,
                         amount_without_fee,
                         coin_pub,
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

  deposit_confirmation_obj
    = json_pack ("{s:o, s:o," /* h_wire, h_contract_terms */
                 " s:o, s:o," /* timestamp, refund_deadline */
                 " s:o, s:o," /* amount_without_fees, coin_pub */
                 " s:o, s:o," /* merchant_pub, exchange_sig */
                 " s:o, s:o," /* master_pub, ep_start */
                 " s:o, s:o," /* ep_expire, ep_end */
                 " s:o, s:o}", /* master_sig, exchange_pub */
                 "h_wire", GNUNET_JSON_from_data_auto (h_wire),
                 "h_contract_terms", GNUNET_JSON_from_data_auto (
                   h_contract_terms),
                 "timestamp", GNUNET_JSON_from_time_abs (timestamp),
                 "refund_deadline", GNUNET_JSON_from_time_abs (refund_deadline),
                 "amount_without_fee", TALER_JSON_from_amount (
                   amount_without_fee),
                 "coin_pub", GNUNET_JSON_from_data_auto (coin_pub),
                 "merchant_pub", GNUNET_JSON_from_data_auto (merchant_pub),
                 "exchange_sig", GNUNET_JSON_from_data_auto (exchange_sig),
                 "master_pub", GNUNET_JSON_from_data_auto (master_pub),
                 "ep_start", GNUNET_JSON_from_time_abs (ep_start),
                 "ep_expire", GNUNET_JSON_from_time_abs (ep_expire),
                 "ep_end", GNUNET_JSON_from_time_abs (ep_end),
                 "master_sig", GNUNET_JSON_from_data_auto (master_sig),
                 "exchange_pub", GNUNET_JSON_from_data_auto (exchange_pub));

  if (NULL == deposit_confirmation_obj)
  {
    GNUNET_break (0);
    return NULL;
  }

  dh = GNUNET_new (struct TALER_AUDITOR_DepositConfirmationHandle);
  dh->auditor = auditor;
  dh->cb = cb;
  dh->cb_cls = cb_cls;
  dh->url = MAH_path_to_url (auditor, "/deposit-confirmation");

  eh = TAL_curl_easy_get (dh->url);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_CUSTOMREQUEST,
                                   "PUT"));
  if (GNUNET_OK !=
      TALER_curl_easy_post (&dh->ctx,
                            eh,
                            deposit_confirmation_obj))
  {
    GNUNET_break (0);
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
  ctx = MAH_handle_to_context (auditor);
  dh->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  dh->ctx.headers,
                                  &handle_deposit_confirmation_finished,
                                  dh);
  return dh;
}


/**
 * Cancel a deposit-confirmation permission request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param deposit_confirmation the deposit-confirmation permission request handle
 */
void
TALER_AUDITOR_deposit_confirmation_cancel (struct
                                           TALER_AUDITOR_DepositConfirmationHandle
                                           *deposit_confirmation)
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
