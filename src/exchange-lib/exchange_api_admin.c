/*
  This file is part of TALER
  Copyright (C) 2014, 2015 GNUnet e.V.

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
 * @file exchange-lib/exchange_api_admin.c
 * @brief Implementation of the /admin/ requests of the exchange's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_json_lib.h"
#include "taler_exchange_service.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"


/**
 * @brief An admin/add/incoming Handle
 */
struct TALER_EXCHANGE_AdminAddIncomingHandle
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
  struct GNUNET_CURL_Job *job;

  /**
   * HTTP headers for the request.
   */
  struct curl_slist *headers;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_AdminAddIncomingResultCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * Function called when we're done processing the
 * HTTP /admin/add/incoming request.
 *
 * @param cls the `struct TALER_EXCHANGE_AdminAddIncomingHandle`
 * @param response_code HTTP response code, 0 on error
 * @param json parsed JSON result, NULL on error
 */
static void
handle_admin_add_incoming_finished (void *cls,
                                    long response_code,
                                    const json_t *json)
{
  struct TALER_EXCHANGE_AdminAddIncomingHandle *aai = cls;

  aai->job = NULL;
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Access denied */
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, exchange says one of the signatures is
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
                response_code);
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  aai->cb (aai->cb_cls,
           response_code,
           json);
  TALER_EXCHANGE_admin_add_incoming_cancel (aai);
}


/**
 * Notify the exchange that we have received an incoming transaction
 * which fills a reserve.  Note that this API is an administrative
 * API and thus not accessible to typical exchange clients, but only
 * to the operators of the exchange.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param reserve_pub public key of the reserve
 * @param amount amount that was deposited
 * @param execution_date when did we receive the amount
 * @param wire wire details
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return NULL
 *         if the inputs are invalid (i.e. invalid amount).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_AdminAddIncomingHandle *
TALER_EXCHANGE_admin_add_incoming (struct TALER_EXCHANGE_Handle *exchange,
                               const struct TALER_ReservePublicKeyP *reserve_pub,
                               const struct TALER_Amount *amount,
                               struct GNUNET_TIME_Absolute execution_date,
                               const json_t *wire,
                               TALER_EXCHANGE_AdminAddIncomingResultCallback res_cb,
                               void *res_cb_cls)
{
  struct TALER_EXCHANGE_AdminAddIncomingHandle *aai;
  struct GNUNET_CURL_Context *ctx;
  json_t *admin_obj;
  CURL *eh;

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_TIME_round_abs (&execution_date));
  if (GNUNET_YES !=
      MAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  admin_obj = json_pack ("{s:o, s:o," /* reserve_pub/amount */
                         " s:o, s:O}", /* execution_Date/wire */
                         "reserve_pub", GNUNET_JSON_from_data (reserve_pub,
                                                               sizeof (*reserve_pub)),
                         "amount", TALER_JSON_from_amount (amount),
                         "execution_date", GNUNET_JSON_from_time_abs (execution_date),
                         "wire", wire);
  aai = GNUNET_new (struct TALER_EXCHANGE_AdminAddIncomingHandle);
  aai->exchange = exchange;
  aai->cb = res_cb;
  aai->cb_cls = res_cb_cls;
  aai->url = MAH_path_to_url (exchange, "/admin/add/incoming");

  eh = curl_easy_init ();
  GNUNET_assert (NULL != (aai->json_enc =
                          json_dumps (admin_obj,
                                      JSON_COMPACT)));
  json_decref (admin_obj);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   aai->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDS,
                                   aai->json_enc));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDSIZE,
                                   strlen (aai->json_enc)));
  ctx = MAH_handle_to_context (exchange);
  aai->job = GNUNET_CURL_job_add (ctx,
                                  eh,
                                  GNUNET_YES,
                                  &handle_admin_add_incoming_finished,
                                  aai);
  return aai;
}


/**
 * Cancel an add incoming.  This function cannot be used on a request
 * handle if a response is already served for it.
 *
 * @param aai the admin add incoming request handle
 */
void
TALER_EXCHANGE_admin_add_incoming_cancel (struct TALER_EXCHANGE_AdminAddIncomingHandle *aai)
{
  if (NULL != aai->job)
  {
    GNUNET_CURL_job_cancel (aai->job);
    aai->job = NULL;
  }
  curl_slist_free_all (aai->headers);
  GNUNET_free (aai->url);
  GNUNET_free (aai->json_enc);
  GNUNET_free (aai);
}


/* end of exchange_api_admin.c */
