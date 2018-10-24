/*
  This file is part of TALER
  Copyright (C) 2014-2018 GNUnet e.V.

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
 * @file auditor-lib/auditor_api_deposit_confirmation.c
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
#include "curl_defaults.h"


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
   * JSON encoding of the request to POST.
   */
  char *json_enc;

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
 * @param json parsed JSON result, NULL on error
 */
static void
handle_deposit_confirmation_finished (void *cls,
				      long response_code,
				      const json_t *json)
{
  struct TALER_AUDITOR_DepositConfirmationHandle *dh = cls;
  struct TALER_AuditorPublicKeyP auditor_pub;
  struct TALER_AuditorPublicKeyP *ep = NULL;

  dh->job = NULL;
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    break;
  case MHD_HTTP_NOT_FOUND:
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the auditor is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_UNAUTHORIZED:
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
 * @param dki public key information
 * @param amount the amount to be deposit-confirmationed
 * @param h_wire hash of the merchant’s account details
 * @param h_contract_terms hash of the contact of the merchant with the customer (further details are never disclosed to the auditor)
 * @param coin_pub coin’s public key
 * @param timestamp timestamp when the deposit-confirmation was finalized
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the auditor (can be zero if refunds are not allowed)
 * @param coin_sig the signature made with purpose #TALER_SIGNATURE_WALLET_COIN_DEPOSIT_CONFIRMATION made by the customer with the coin’s private key.
 * @return #GNUNET_OK if signatures are OK, #GNUNET_SYSERR if not
 */
static int
verify_signatures (const struct TALER_Amount *amount,
                   const struct GNUNET_HashCode *h_wire,
                   const struct GNUNET_HashCode *h_contract_terms,
                   const struct TALER_CoinSpendPublicKeyP *coin_pub,
                   struct GNUNET_TIME_Absolute timestamp,
                   const struct TALER_MerchantPublicKeyP *merchant_pub,
                   struct GNUNET_TIME_Absolute refund_deadline,
                   const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_DepositConfirmationRequestPS dr;
  struct TALER_CoinPublicInfo coin_info;

  dr.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_DEPOSIT_CONFIRMATION);
  dr.purpose.size = htonl (sizeof (struct TALER_DepositConfirmationRequestPS));
  dr.h_contract_terms = *h_contract_terms;
  dr.h_wire = *h_wire;
  dr.timestamp = GNUNET_TIME_absolute_hton (timestamp);
  dr.refund_deadline = GNUNET_TIME_absolute_hton (refund_deadline);
  TALER_amount_hton (&dr.amount_with_fee,
                     amount);
  TALER_amount_hton (&dr.deposit_confirmation_fee,
                     &dki->fee_deposit_confirmation);
  dr.merchant = *merchant_pub;
  dr.coin_pub = *coin_pub;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_DEPOSIT_CONFIRMATION,
                                  &dr.purpose,
                                  &coin_sig->eddsa_signature,
                                  &coin_pub->eddsa_pub))
  {
    GNUNET_break_op (0);
    TALER_LOG_WARNING ("Invalid coin signature on /deposit-confirmation request!\n");
    {
      TALER_LOG_DEBUG ("... amount_with_fee was %s\n",
                       TALER_amount2s (amount));
      TALER_LOG_DEBUG ("... deposit-confirmation_fee was %s\n",
                       TALER_amount2s (&dki->fee_deposit_confirmation));
    }

    return GNUNET_SYSERR;
  }

  /* check coin signature */
  coin_info.coin_pub = *coin_pub;
  coin_info.denom_pub = *denom_pub;
  coin_info.denom_sig = *denom_sig;
  if (GNUNET_YES !=
      TALER_test_coin_valid (&coin_info))
  {
    GNUNET_break_op (0);
    TALER_LOG_WARNING ("Invalid coin passed for /deposit-confirmation\n");
    return GNUNET_SYSERR;
  }
  if (0 < TALER_amount_cmp (&dki->fee_deposit_confirmation,
                            amount))
  {
    GNUNET_break_op (0);
    TALER_LOG_WARNING ("DepositConfirmation amount smaller than fee\n");
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
 * @param amount the amount to be deposit-confirmationed
 * @param h_contract_terms hash of the contact of the merchant with the customer (further details are never disclosed to the auditor)
 * @param coin_pub coin’s public key
 * @param timestamp timestamp when the contract was finalized, must not be too far in the future
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the auditor (can be zero if refunds are not allowed); must not be after the @a wire_deadline
 * @param coin_sig the signature made with purpose #TALER_SIGNATURE_WALLET_COIN_DEPOSIT-CONFIRMATION made by the customer with the coin’s private key.
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_AUDITOR_DepositConfirmationHandle *
TALER_AUDITOR_deposit_confirmation (struct TALER_AUDITOR_Handle *auditor,
				    const struct GNUNET_HashCode *h_wire,
				    const struct TALER_Amount *amount_without_fees,
				    const struct GNUNET_HashCode *h_contract_terms,
				    const struct TALER_CoinSpendPublicKeyP *coin_pub,
				    struct GNUNET_TIME_Absolute timestamp,
				    const struct TALER_MerchantPublicKeyP *merchant_pub,
				    struct GNUNET_TIME_Absolute refund_deadline,
				    TALER_AUDITOR_DepositConfirmationResultCallback cb,
				    void *cb_cls)
{
  struct TALER_AUDITOR_DepositConfirmationHandle *dh;
  struct GNUNET_CURL_Context *ctx;
  json_t *deposit_confirmation_obj;
  CURL *eh;
  struct TALER_Amount amount_without_fee;

  (void) GNUNET_TIME_round_abs (&wire_deadline);
  (void) GNUNET_TIME_round_abs (&refund_deadline);
  GNUNET_assert (refund_deadline.abs_value_us <= wire_deadline.abs_value_us);
  GNUNET_assert (GNUNET_YES ==
		 MAH_handle_is_ready (auditor));
  if (GNUNET_OK !=
      verify_signatures (amount,
                         &h_wire,
                         h_contract_terms,
                         coin_pub,
                         timestamp,
                         merchant_pub,
                         refund_deadline,
                         coin_sig))
  {
    GNUNET_break_op (0);
    return NULL;
  }

  deposit_confirmation_obj
    = json_pack ("{s:o, s:o," /* f/wire */
		 " s:o, s:o," /* H_wire, h_contract_terms */
		 " s:o, s:o," /* coin_pub, denom_pub */
		 " s:o, s:o," /* ub_sig, timestamp */
		 " s:o," /* merchant_pub */
		 " s:o, s:o," /* refund_deadline, wire_deadline */
		 " s:o}",     /* coin_sig */
		 "contribution", TALER_JSON_from_amount (amount),
		 "H_wire", GNUNET_JSON_from_data_auto (&h_wire),
		 "h_contract_terms", GNUNET_JSON_from_data_auto (h_contract_terms),
		 "coin_pub", GNUNET_JSON_from_data_auto (coin_pub),
		 "timestamp", GNUNET_JSON_from_time_abs (timestamp),
		 "merchant_pub", GNUNET_JSON_from_data_auto (merchant_pub),
		 "refund_deadline", GNUNET_JSON_from_time_abs (refund_deadline),
		 "wire_transfer_deadline", GNUNET_JSON_from_time_abs (wire_deadline),
		 "coin_sig", GNUNET_JSON_from_data_auto (coin_sig)
		 );
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
  dh->depconf.purpose.size = htonl (sizeof (struct TALER_DepositConfirmationConfirmationPS));
  dh->depconf.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_DEPOSIT_CONFIRMATION);
  dh->depconf.h_contract_terms = *h_contract_terms;
  dh->depconf.h_wire = h_wire;
  dh->depconf.timestamp = GNUNET_TIME_absolute_hton (timestamp);
  dh->depconf.refund_deadline = GNUNET_TIME_absolute_hton (refund_deadline);
  TALER_amount_hton (&dh->depconf.amount_without_fee,
                     &amount_without_fee);
  dh->depconf.coin_pub = *coin_pub;
  dh->depconf.merchant = *merchant_pub;
  dh->amount_with_fee = *amount;
  dh->coin_value = dki->value;

  eh = TEL_curl_easy_get (dh->url);
  GNUNET_assert (NULL != (dh->json_enc =
                          json_dumps (deposit_confirmation_obj,
                                      JSON_COMPACT)));
  json_decref (deposit_confirmation_obj);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "URL for deposit-confirmation: `%s'\n",
              dh->url);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDS,
                                   dh->json_enc));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDSIZE,
                                   strlen (dh->json_enc)));
  ctx = MAH_handle_to_context (auditor);
  dh->job = GNUNET_CURL_job_add (ctx,
				 eh,
				 GNUNET_YES,
				 (GC_JCC) &handle_deposit_confirmation_finished,
				 dh);
  return dh;
}


/**
 * Cancel a deposit-confirmation permission request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param deposit-confirmation the deposit-confirmation permission request handle
 */
void
TALER_AUDITOR_deposit_confirmation_cancel (struct TALER_AUDITOR_DepositConfirmationHandle *deposit_confirmation)
{
  if (NULL != deposit_confirmation->job)
  {
    GNUNET_CURL_job_cancel (deposit_confirmation->job);
    deposit_confirmation->job = NULL;
  }
  GNUNET_free (deposit_confirmation->url);
  GNUNET_free (deposit_confirmation->json_enc);
  GNUNET_free (deposit_confirmation);
}


/* end of auditor_api_deposit_confirmation.c */
