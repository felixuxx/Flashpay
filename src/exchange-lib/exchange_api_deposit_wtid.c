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
  TALER; see the file COPYING.  If not, If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file exchange-lib/exchange_api_deposit_wtid.c
 * @brief Implementation of the /deposit/wtid request of the exchange's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include "taler_exchange_service.h"
#include "exchange_api_common.h"
#include "exchange_api_json.h"
#include "exchange_api_context.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"


/**
 * @brief A Deposit Wtid Handle
 */
struct TALER_EXCHANGE_DepositWtidHandle
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
   * JSON encoding of the request to POST.
   */
  char *json_enc;

  /**
   * Handle for the request.
   */
  struct MAC_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_DepositWtidCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Download buffer
   */
  struct MAC_DownloadBuffer db;

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
 * @return #GNUNET_OK if the signature is valid, #GNUNET_SYSERR if not
 */
static int
verify_deposit_wtid_signature_ok (const struct TALER_EXCHANGE_DepositWtidHandle *dwh,
                                  json_t *json)
{
  struct TALER_ExchangeSignatureP exchange_sig;
  struct TALER_ExchangePublicKeyP exchange_pub;
  const struct TALER_EXCHANGE_Keys *key_state;
  struct MAJ_Specification spec[] = {
    MAJ_spec_fixed_auto ("exchange_sig", &exchange_sig),
    MAJ_spec_fixed_auto ("exchange_pub", &exchange_pub),
    MAJ_spec_end
  };

  if (GNUNET_OK !=
      MAJ_parse_json (json,
                      spec))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  key_state = TALER_EXCHANGE_get_keys (dwh->exchange);
  if (GNUNET_OK !=
      TALER_EXCHANGE_test_signing_key (key_state,
                                   &exchange_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE,
                                  &dwh->depconf.purpose,
                                  &exchange_sig.eddsa_signature,
                                  &exchange_pub.eddsa_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /deposit/wtid request.
 *
 * @param cls the `struct TALER_EXCHANGE_DepositWtidHandle`
 * @param eh the curl request handle
 */
static void
handle_deposit_wtid_finished (void *cls,
                              CURL *eh)
{
  struct TALER_EXCHANGE_DepositWtidHandle *dwh = cls;
  long response_code;
  json_t *json;
  const struct TALER_WireTransferIdentifierRawP *wtid = NULL;
  struct GNUNET_TIME_Absolute execution_time = GNUNET_TIME_UNIT_FOREVER_ABS;
  const struct TALER_Amount *coin_contribution = NULL;
  struct TALER_Amount coin_contribution_s;

  dwh->job = NULL;
  json = MAC_download_get_result (&dwh->db,
                                  eh,
                                  &response_code);
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    {
      struct MAJ_Specification spec[] = {
        MAJ_spec_fixed_auto ("wtid", &dwh->depconf.wtid),
        MAJ_spec_absolute_time ("execution_time", &execution_time),
        MAJ_spec_amount ("coin_contribution", &coin_contribution_s),
        MAJ_spec_end
      };

      if (GNUNET_OK !=
          MAJ_parse_json (json,
                          spec))
      {
        GNUNET_break_op (0);
        response_code = 0;
        break;
      }
      wtid = &dwh->depconf.wtid;
      dwh->depconf.execution_time = GNUNET_TIME_absolute_hton (execution_time);
      TALER_amount_hton (&dwh->depconf.coin_contribution,
                         &coin_contribution_s);
      coin_contribution = &coin_contribution_s;
      if (GNUNET_OK !=
          verify_deposit_wtid_signature_ok (dwh,
                                            json))
      {
        GNUNET_break_op (0);
        response_code = 0;
      }
    }
    break;
  case MHD_HTTP_ACCEPTED:
    {
      /* Transaction known, but not executed yet */
      struct MAJ_Specification spec[] = {
        MAJ_spec_absolute_time ("execution_time", &execution_time),
        MAJ_spec_end
      };

      if (GNUNET_OK !=
          MAJ_parse_json (json,
                          spec))
      {
        GNUNET_break_op (0);
        response_code = 0;
        break;
      }
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Exchange does not know about transaction;
       we should pass the reply to the application */
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                response_code);
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  dwh->cb (dwh->cb_cls,
           response_code,
           json,
           wtid,
           execution_time,
           coin_contribution);
  json_decref (json);
  TALER_EXCHANGE_deposit_wtid_cancel (dwh);
}


/**
 * Obtain wire transfer details about an existing deposit operation.
 *
 * @param exchange the exchange to query
 * @param merchant_priv the merchant's private key
 * @param h_wire hash of merchant's wire transfer details
 * @param h_contract hash of the contract
 * @param coin_pub public key of the coin
 * @param transaction_id transaction identifier
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to abort request
 */
struct TALER_EXCHANGE_DepositWtidHandle *
TALER_EXCHANGE_deposit_wtid (struct TALER_EXCHANGE_Handle *exchange,
                         const struct TALER_MerchantPrivateKeyP *merchant_priv,
                         const struct GNUNET_HashCode *h_wire,
                         const struct GNUNET_HashCode *h_contract,
                         const struct TALER_CoinSpendPublicKeyP *coin_pub,
                         uint64_t transaction_id,
                         TALER_EXCHANGE_DepositWtidCallback cb,
                         void *cb_cls)
{
  struct TALER_DepositTrackPS dtp;
  struct TALER_MerchantSignatureP merchant_sig;
  struct TALER_EXCHANGE_DepositWtidHandle *dwh;
  struct TALER_EXCHANGE_Context *ctx;
  json_t *deposit_wtid_obj;
  CURL *eh;

  if (GNUNET_YES !=
      MAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  dtp.purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_DEPOSIT_WTID);
  dtp.purpose.size = htonl (sizeof (dtp));
  dtp.h_contract = *h_contract;
  dtp.h_wire = *h_wire;
  dtp.transaction_id = GNUNET_htonll (transaction_id);
  GNUNET_CRYPTO_eddsa_key_get_public (&merchant_priv->eddsa_priv,
                                      &dtp.merchant.eddsa_pub);

  dtp.coin_pub = *coin_pub;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (&merchant_priv->eddsa_priv,
                                           &dtp.purpose,
                                           &merchant_sig.eddsa_sig));
  deposit_wtid_obj = json_pack ("{s:o, s:o," /* H_wire, H_contract */
                                " s:o, s:I," /* coin_pub, transaction_id */
                                " s:o, s:o}", /* merchant_pub, merchant_sig */
                                "H_wire", TALER_json_from_data (h_wire,
                                                                sizeof (struct GNUNET_HashCode)),
                                "H_contract", TALER_json_from_data (h_contract,
                                                                    sizeof (struct GNUNET_HashCode)),
                                "coin_pub", TALER_json_from_data (coin_pub,
                                                                  sizeof (*coin_pub)),
                                "transaction_id", (json_int_t) transaction_id,
                                "merchant_pub", TALER_json_from_data (&dtp.merchant,
                                                                      sizeof (struct TALER_MerchantPublicKeyP)),
                                "merchant_sig", TALER_json_from_data (&merchant_sig,
                                                                      sizeof (merchant_sig)));

  dwh = GNUNET_new (struct TALER_EXCHANGE_DepositWtidHandle);
  dwh->exchange = exchange;
  dwh->cb = cb;
  dwh->cb_cls = cb_cls;
  dwh->url = MAH_path_to_url (exchange, "/deposit/wtid");
  dwh->depconf.purpose.size = htonl (sizeof (struct TALER_DepositConfirmationPS));
  dwh->depconf.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE);
  dwh->depconf.h_wire = *h_wire;
  dwh->depconf.h_contract = *h_contract;
  dwh->depconf.coin_pub = *coin_pub;
  dwh->depconf.transaction_id = GNUNET_htonll (transaction_id);

  eh = curl_easy_init ();
  GNUNET_assert (NULL != (dwh->json_enc =
                          json_dumps (deposit_wtid_obj,
                                      JSON_COMPACT)));
  json_decref (deposit_wtid_obj);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   dwh->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDS,
                                   dwh->json_enc));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDSIZE,
                                   strlen (dwh->json_enc)));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEFUNCTION,
                                   &MAC_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEDATA,
                                   &dwh->db));
  ctx = MAH_handle_to_context (exchange);
  dwh->job = MAC_job_add (ctx,
                          eh,
                          GNUNET_YES,
                          &handle_deposit_wtid_finished,
                          dwh);
  return dwh;
}


/**
 * Cancel deposit wtid request.  This function cannot be used on a request
 * handle if a response is already served for it.
 *
 * @param dwh the wire deposits request handle
 */
void
TALER_EXCHANGE_deposit_wtid_cancel (struct TALER_EXCHANGE_DepositWtidHandle *dwh)
{
  if (NULL != dwh->job)
  {
    MAC_job_cancel (dwh->job);
    dwh->job = NULL;
  }
  GNUNET_free_non_null (dwh->db.buf);
  GNUNET_free (dwh->url);
  GNUNET_free (dwh->json_enc);
  GNUNET_free (dwh);
}


/* end of exchange_api_deposit_wtid.c */
