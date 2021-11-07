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
 * @file lib/exchange_api_kyc_proof.c
 * @brief Implementation of the /kyc-proof request
 * @author Christian Grothoff
 */
#include "platform.h"
#include <microhttpd.h> /* just for HTTP proof codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A ``/kyc-proof`` handle
 */
struct TALER_EXCHANGE_KycProofHandle
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
   * Handle to our CURL request.
   */
  CURL *eh;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_KycProofCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

};


/**
 * Function called when we're done processing the
 * HTTP /kyc-proof request.
 *
 * @param cls the `struct TALER_EXCHANGE_KycProofHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_kyc_proof_finished (void *cls,
                           long response_code,
                           const void *response)
{
  struct TALER_EXCHANGE_KycProofHandle *kph = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_KycProofResponse kpr = {
    .http_status = (unsigned int) response_code
  };

  kph->job = NULL;
  switch (response_code)
  {
  case 0:
    kpr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_FOUND:
    {
      char *redirect_url;

      GNUNET_assert (CURLE_OK ==
                     curl_easy_getinfo (kph->eh,
                                        CURLINFO_REDIRECT_URL,
                                        &redirect_url));
      kpr.details.found.redirect_url = redirect_url;
      break;
    }
  case MHD_HTTP_BAD_REQUEST:
    kpr.ec = TALER_JSON_get_error_code (j);
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_UNAUTHORIZED:
    kpr.ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    kpr.ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_BAD_GATEWAY:
    kpr.ec = TALER_JSON_get_error_code (j);
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  case MHD_HTTP_GATEWAY_TIMEOUT:
    kpr.ec = TALER_JSON_get_error_code (j);
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    kpr.ec = TALER_JSON_get_error_code (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange kyc_proof\n",
                (unsigned int) response_code,
                (int) kpr.ec);
    break;
  }
  kph->cb (kph->cb_cls,
           &kpr);
  TALER_EXCHANGE_kyc_proof_cancel (kph);
}


struct TALER_EXCHANGE_KycProofHandle *
TALER_EXCHANGE_kyc_proof (struct TALER_EXCHANGE_Handle *exchange,
                          uint64_t payment_target,
                          const char *code,
                          const char *state,
                          TALER_EXCHANGE_KycProofCallback cb,
                          void *cb_cls)
{
  struct TALER_EXCHANGE_KycProofHandle *kph;
  struct GNUNET_CURL_Context *ctx;
  char *arg_str;

  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  /* TODO: any escaping of code/state needed??? */
  GNUNET_asprintf (&arg_str,
                   "/kyc-proof/%llu?code=%s&state=%s",
                   (unsigned long long) payment_target,
                   code,
                   state);
  kph = GNUNET_new (struct TALER_EXCHANGE_KycProofHandle);
  kph->exchange = exchange;
  kph->cb = cb;
  kph->cb_cls = cb_cls;
  kph->url = TEAH_path_to_url (exchange,
                               arg_str);
  GNUNET_free (arg_str);
  if (NULL == kph->url)
  {
    GNUNET_free (kph);
    return NULL;
  }
  kph->eh = TALER_EXCHANGE_curl_easy_get_ (kph->url);
  if (NULL == kph->eh)
  {
    GNUNET_break (0);
    GNUNET_free (kph->url);
    GNUNET_free (kph);
    return NULL;
  }
  /* disable location following, we want to learn the
     result of a 302 redirect! */
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (kph->eh,
                                   CURLOPT_FOLLOWLOCATION,
                                   0L));
  ctx = TEAH_handle_to_context (exchange);
  kph->job = GNUNET_CURL_job_add_with_ct_json (ctx,
                                               kph->eh,
                                               &handle_kyc_proof_finished,
                                               kph);
  return kph;
}


void
TALER_EXCHANGE_kyc_proof_cancel (struct TALER_EXCHANGE_KycProofHandle *kph)
{
  if (NULL != kph->job)
  {
    GNUNET_CURL_job_cancel (kph->job);
    kph->job = NULL;
  }
  GNUNET_free (kph->url);
  GNUNET_free (kph);
}


/* end of exchange_api_kyc_proof.c */
