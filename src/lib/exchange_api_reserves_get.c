/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file lib/exchange_api_reserves_get.c
 * @brief Implementation of the GET /reserves/$RESERVE_PUB requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A /reserves/ GET Handle
 */
struct TALER_EXCHANGE_ReservesGetHandle
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
  TALER_EXCHANGE_ReservesGetCallback cb;

  /**
   * Public key of the reserve we are querying.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * We received an #MHD_HTTP_OK status code. Handle the JSON
 * response.
 *
 * @param rgh handle of the request
 * @param j JSON response
 * @return #GNUNET_OK on success
 */
static int
handle_reserves_get_ok (struct TALER_EXCHANGE_ReservesGetHandle *rgh,
                        const json_t *j)
{
  json_t *history;
  unsigned int len;
  struct TALER_Amount balance;
  struct TALER_Amount balance_from_history;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("balance", &balance),
    GNUNET_JSON_spec_end ()
  };
  struct TALER_EXCHANGE_HttpResponse hr = {
    .reply = j,
    .http_status = MHD_HTTP_OK
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (j,
                         spec,
                         NULL,
                         NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  history = json_object_get (j,
                             "history");
  if (NULL == history)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  len = json_array_size (history);
  {
    struct TALER_EXCHANGE_ReserveHistory *rhistory;

    rhistory = GNUNET_new_array (len,
                                 struct TALER_EXCHANGE_ReserveHistory);
    if (GNUNET_OK !=
        TALER_EXCHANGE_parse_reserve_history (rgh->exchange,
                                              history,
                                              &rgh->reserve_pub,
                                              balance.currency,
                                              &balance_from_history,
                                              len,
                                              rhistory))
    {
      GNUNET_break_op (0);
      TALER_EXCHANGE_free_reserve_history (rhistory,
                                           len);
      return GNUNET_SYSERR;
    }
    if (0 !=
        TALER_amount_cmp (&balance_from_history,
                          &balance))
    {
      /* exchange cannot add up balances!? */
      GNUNET_break_op (0);
      TALER_EXCHANGE_free_reserve_history (rhistory,
                                           len);
      return GNUNET_SYSERR;
    }
    if (NULL != rgh->cb)
    {
      rgh->cb (rgh->cb_cls,
               &hr,
               &balance,
               len,
               rhistory);
      rgh->cb = NULL;
    }
    TALER_EXCHANGE_free_reserve_history (rhistory,
                                         len);
  }
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /reserves/ GET request.
 *
 * @param cls the `struct TALER_EXCHANGE_ReservesGetHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_reserves_get_finished (void *cls,
                              long response_code,
                              const void *response)
{
  struct TALER_EXCHANGE_ReservesGetHandle *rgh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .reply = j,
    .http_status = (unsigned int) response_code
  };

  rgh->job = NULL;
  switch (response_code)
  {
  case 0:
    hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        handle_reserves_get_ok (rgh,
                                j))
    {
      hr.http_status = 0;
      hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for reserves get\n",
                (unsigned int) response_code,
                (int) hr.ec);
    break;
  }
  if (NULL != rgh->cb)
  {
    rgh->cb (rgh->cb_cls,
             &hr,
             NULL,
             0, NULL);
    rgh->cb = NULL;
  }
  TALER_EXCHANGE_reserves_get_cancel (rgh);
}


/**
 * Submit a request to obtain the transaction history of a reserve
 * from the exchange.  Note that while we return the full response to the
 * caller for further processing, we do already verify that the
 * response is well-formed (i.e. that signatures included in the
 * response are all valid and add up to the balance).  If the exchange's
 * reply is not well-formed, we return an HTTP status code of zero to
 * @a cb.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param reserve_pub public key of the reserve to inspect
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_EXCHANGE_ReservesGetHandle *
TALER_EXCHANGE_reserves_get (struct TALER_EXCHANGE_Handle *exchange,
                             const struct
                             TALER_ReservePublicKeyP *reserve_pub,
                             TALER_EXCHANGE_ReservesGetCallback cb,
                             void *cb_cls)
{
  struct TALER_EXCHANGE_ReservesGetHandle *rgh;
  struct GNUNET_CURL_Context *ctx;
  CURL *eh;
  char arg_str[sizeof (struct TALER_ReservePublicKeyP) * 2 + 16];

  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  {
    char pub_str[sizeof (struct TALER_ReservePublicKeyP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (reserve_pub,
                                         sizeof (struct
                                                 TALER_ReservePublicKeyP),
                                         pub_str,
                                         sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/reserves/%s",
                     pub_str);
  }
  rgh = GNUNET_new (struct TALER_EXCHANGE_ReservesGetHandle);
  rgh->exchange = exchange;
  rgh->cb = cb;
  rgh->cb_cls = cb_cls;
  rgh->reserve_pub = *reserve_pub;
  rgh->url = TEAH_path_to_url (exchange,
                               arg_str);
  if (NULL == rgh->url)
  {
    GNUNET_free (rgh);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (rgh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (rgh->url);
    GNUNET_free (rgh);
    return NULL;
  }
  ctx = TEAH_handle_to_context (exchange);
  rgh->job = GNUNET_CURL_job_add (ctx,
                                  eh,
                                  &handle_reserves_get_finished,
                                  rgh);
  return rgh;
}


/**
 * Cancel a reserve status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param rgh the reserve status request handle
 */
void
TALER_EXCHANGE_reserves_get_cancel (struct
                                    TALER_EXCHANGE_ReservesGetHandle *rgh)
{
  if (NULL != rgh->job)
  {
    GNUNET_CURL_job_cancel (rgh->job);
    rgh->job = NULL;
  }
  GNUNET_free (rgh->url);
  GNUNET_free (rgh);
}


/* end of exchange_api_reserve.c */
