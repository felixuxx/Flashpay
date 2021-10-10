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
 * @file lib/exchange_api_kyc_check.c
 * @brief Implementation of the /kyc-check request
 * @author Christian Grothoff
 */
#include "platform.h"
#include <microhttpd.h> /* just for HTTP check codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A ``/kyc-check`` handle
 */
struct TALER_EXCHANGE_KycCheckHandle
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
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_KycStatusCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

};


/**
 * Function called when we're done processing the
 * HTTP /kyc-check request.
 *
 * @param cls the `struct TALER_EXCHANGE_KycCheckHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_kyc_check_finished (void *cls,
                           long response_code,
                           const void *response)
{
  struct TALER_EXCHANGE_KycCheckHandle *kch = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_KycStatus ks = {
    .http_status = (unsigned int) response_code
  };

  kch->job = NULL;
  switch (response_code)
  {
  case 0:
    ks.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    GNUNET_break (0); // FIXME
    TALER_EXCHANGE_kyc_check_cancel (kch);
    return;
  case MHD_HTTP_ACCEPTED:
    GNUNET_break (0); // FIXME
    TALER_EXCHANGE_kyc_check_cancel (kch);
    return;
  case MHD_HTTP_NO_CONTENT:
    GNUNET_break (0); // FIXME
    TALER_EXCHANGE_kyc_check_cancel (kch);
    return;
  case MHD_HTTP_BAD_REQUEST:
    ks.ec = TALER_JSON_get_error_code (j);
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_UNAUTHORIZED:
    GNUNET_break (0); // FIXME
    TALER_EXCHANGE_kyc_check_cancel (kch);
    return;
  case MHD_HTTP_NOT_FOUND:
    ks.ec = TALER_JSON_get_error_code (j);
    TALER_EXCHANGE_kyc_check_cancel (kch);
    return;
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
                "Unexpected response code %u/%d for exchange kyc_check\n",
                (unsigned int) response_code,
                (int) ks.ec);
    break;
  }
  TALER_EXCHANGE_kyc_check_cancel (kch);
}


/**
 * Submit a kyc_check request to the exchange and get the exchange's response.
 *
 * This API is typically not used by anyone, it is more a threat against those
 * trying to receive a funds transfer by abusing the refresh protocol.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param coin_priv private key to request kyc_check data for
 * @param kyc_check_cb the callback to call with the useful result of the
 *        refresh operation the @a coin_priv was involved in (if any)
 * @param kyc_check_cb_cls closure for @a kyc_check_cb
 * @return a handle for this request
 */
struct TALER_EXCHANGE_KycCheckHandle *
TALER_EXCHANGE_kyc_check (struct TALER_EXCHANGE_Handle *exchange,
                          uint64_t payment_target,
                          const struct GNUNET_HashCode *h_wire,
                          struct GNUNET_TIME_Relative timeout,
                          TALER_EXCHANGE_KycStatusCallback cb,
                          void *cb_cls)
{
  struct TALER_EXCHANGE_KycCheckHandle *kch;
  CURL *eh;
  struct GNUNET_CURL_Context *ctx;

  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }

  kch = GNUNET_new (struct TALER_EXCHANGE_KycCheckHandle);
  kch->exchange = exchange;
  kch->cb = cb;
  kch->cb_cls = cb_cls;
  kch->url = TEAH_path_to_url (exchange,
                               "FIXME");
  if (NULL == kch->url)
  {
    GNUNET_free (kch);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (kch->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (kch->url);
    GNUNET_free (kch);
    return NULL;
  }
  ctx = TEAH_handle_to_context (exchange);
  kch->job = GNUNET_CURL_job_add_with_ct_json (ctx,
                                               eh,
                                               &handle_kyc_check_finished,
                                               kch);
  return kch;
}


/**
 * Cancel a kyc_check request.  This function cannot be used
 * on a request handle if the callback was already invoked.
 *
 * @param kch the kyc_check handle
 */
void
TALER_EXCHANGE_kyc_check_cancel (struct TALER_EXCHANGE_KycCheckHandle *kch)
{
  if (NULL != kch->job)
  {
    GNUNET_CURL_job_cancel (kch->job);
    kch->job = NULL;
  }
  GNUNET_free (kch->url);
  GNUNET_free (kch);
}


/* end of exchange_api_kyc_check.c */
