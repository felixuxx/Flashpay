/*
  This file is part of TALER
  Copyright (C) 2021 Taler Systems SA

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
 * @file lib/exchange_api_kyc_wallet.c
 * @brief Implementation of the /kyc-wallet request
 * @author Christian Grothoff
 */
#include "platform.h"
#include <microhttpd.h> /* just for HTTP wallet codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A ``/kyc-wallet`` handle
 */
struct TALER_EXCHANGE_KycWalletHandle
{

  /**
   * Context for #TEH_curl_easy_post(). Keeps the data that must
   * persist for Curl to make the upload.
   */
  struct TALER_CURL_PostContext ctx;

  /**
   * The connection to exchange this request handle will use
   */
  struct TALER_EXCHANGE_Handle *exchange;

  /**
   * The url for this request.
   */
  char *url;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_KycWalletCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

};


/**
 * Function called when we're done processing the
 * HTTP /kyc-wallet request.
 *
 * @param cls the `struct TALER_EXCHANGE_KycWalletHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_kyc_wallet_finished (void *cls,
                            long response_code,
                            const void *response)
{
  struct TALER_EXCHANGE_KycWalletHandle *kwh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_WalletKycResponse ks = {
    .http_status = (unsigned int) response_code
  };

  kwh->job = NULL;
  switch (response_code)
  {
  case 0:
    ks.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_uint64 ("payment_target_uuid",
                                 &ks.payment_target_uuid),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        ks.http_status = 0;
        ks.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
        break;
      }
      break;
    }
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_BAD_REQUEST:
    ks.ec = TALER_JSON_get_error_code (j);
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    ks.ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    ks.ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    ks.ec = TALER_JSON_get_error_code (j);
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    ks.ec = TALER_JSON_get_error_code (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange /kyc-wallet\n",
                (unsigned int) response_code,
                (int) ks.ec);
    break;
  }
  kwh->cb (kwh->cb_cls,
           &ks);
  TALER_EXCHANGE_kyc_wallet_cancel (kwh);
}


struct TALER_EXCHANGE_KycWalletHandle *
TALER_EXCHANGE_kyc_wallet (struct TALER_EXCHANGE_Handle *exchange,
                           const struct TALER_ReservePrivateKeyP *reserve_priv,
                           TALER_EXCHANGE_KycWalletCallback cb,
                           void *cb_cls)
{
  struct TALER_EXCHANGE_KycWalletHandle *kwh;
  CURL *eh;
  json_t *req;
  struct GNUNET_CURL_Context *ctx;
  struct TALER_ReservePublicKeyP reserve_pub;
  struct TALER_ReserveSignatureP reserve_sig;

  GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                      &reserve_pub.eddsa_pub);
  TALER_wallet_account_setup_sign (reserve_priv,
                                   &reserve_sig);
  req = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_data_auto ("reserve_pub",
                                &reserve_pub),
    GNUNET_JSON_pack_data_auto ("reserve_sig",
                                &reserve_sig));
  GNUNET_assert (NULL != req);
  kwh = GNUNET_new (struct TALER_EXCHANGE_KycWalletHandle);
  kwh->exchange = exchange;
  kwh->cb = cb;
  kwh->cb_cls = cb_cls;
  kwh->url = TEAH_path_to_url (exchange,
                               "/kyc-wallet");
  if (NULL == kwh->url)
  {
    json_decref (req);
    GNUNET_free (kwh);
    return NULL;
  }
  ctx = TEAH_handle_to_context (exchange);
  eh = TALER_EXCHANGE_curl_easy_get_ (kwh->url);
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&kwh->ctx,
                              eh,
                              req)) )
  {
    GNUNET_break (0);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (req);
    GNUNET_free (kwh->url);
    GNUNET_free (kwh);
    return NULL;
  }
  json_decref (req);
  kwh->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   kwh->ctx.headers,
                                   &handle_kyc_wallet_finished,
                                   kwh);
  return kwh;
}


void
TALER_EXCHANGE_kyc_wallet_cancel (struct TALER_EXCHANGE_KycWalletHandle *kwh)
{
  if (NULL != kwh->job)
  {
    GNUNET_CURL_job_cancel (kwh->job);
    kwh->job = NULL;
  }
  GNUNET_free (kwh->url);
  TALER_curl_easy_post_finished (&kwh->ctx);
  GNUNET_free (kwh);
}


/* end of exchange_api_kyc_wallet.c */
