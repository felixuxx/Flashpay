/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file lib/exchange_api_reserves_get_attestable.c
 * @brief Implementation of the GET_ATTESTABLE /reserves/$RESERVE_PUB requests
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
 * @brief A /reserves/ GET_ATTESTABLE Handle
 */
struct TALER_EXCHANGE_ReservesGetAttestHandle
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
  TALER_EXCHANGE_ReservesGetAttestCallback cb;

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
 * @param rgah handle of the request
 * @param j JSON response
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_reserves_get_attestable_ok (
  struct TALER_EXCHANGE_ReservesGetAttestHandle *rgah,
  const json_t *j)
{
  struct TALER_EXCHANGE_ReserveGetAttestResult rs = {
    .hr.reply = j,
    .hr.http_status = MHD_HTTP_OK
  };
  json_t *details;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("details",
                           &details),
    GNUNET_JSON_spec_end ()
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
  {
    unsigned int dlen = json_array_size (details);
    const char *attributes[GNUNET_NZL (dlen)];

    for (unsigned int i = 0; i<dlen; i++)
    {
      json_t *detail = json_array_get (details,
                                       i);
      attributes[i] = json_string_value (detail);
      if (NULL == attributes[i])
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }
    }
    rs.details.ok.attributes_length = dlen;
    rs.details.ok.attributes = attributes;
    rgah->cb (rgah->cb_cls,
              &rs);
    rgah->cb = NULL;
  }
  GNUNET_JSON_parse_free (spec);
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP GET /reserves/$RID/attest request.
 *
 * @param cls the `struct TALER_EXCHANGE_ReservesGetAttestableHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_reserves_get_attestable_finished (void *cls,
                                         long response_code,
                                         const void *response)
{
  struct TALER_EXCHANGE_ReservesGetAttestHandle *rgah = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_ReserveGetAttestResult rs = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  rgah->job = NULL;
  switch (response_code)
  {
  case 0:
    rs.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        handle_reserves_get_attestable_ok (rgah,
                                           j))
    {
      rs.hr.http_status = 0;
      rs.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_CONFLICT:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for reserves get_attestable\n",
                (unsigned int) response_code,
                (int) rs.hr.ec);
    break;
  }
  if (NULL != rgah->cb)
  {
    rgah->cb (rgah->cb_cls,
              &rs);
    rgah->cb = NULL;
  }
  TALER_EXCHANGE_reserves_get_attestable_cancel (rgah);
}


struct TALER_EXCHANGE_ReservesGetAttestHandle *
TALER_EXCHANGE_reserves_get_attestable (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  TALER_EXCHANGE_ReservesGetAttestCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ReservesGetAttestHandle *rgah;
  struct GNUNET_CURL_Context *ctx;
  CURL *eh;
  char arg_str[sizeof (struct TALER_ReservePublicKeyP) * 2 + 32];

  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  {
    char pub_str[sizeof (struct TALER_ReservePublicKeyP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      reserve_pub,
      sizeof (*reserve_pub),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/reserves/%s/attest",
                     pub_str);
  }
  rgah = GNUNET_new (struct TALER_EXCHANGE_ReservesGetAttestHandle);
  rgah->exchange = exchange;
  rgah->cb = cb;
  rgah->cb_cls = cb_cls;
  rgah->reserve_pub = *reserve_pub;
  rgah->url = TEAH_path_to_url (exchange,
                                arg_str);
  if (NULL == rgah->url)
  {
    GNUNET_free (rgah);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (rgah->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (rgah->url);
    GNUNET_free (rgah);
    return NULL;
  }
  ctx = TEAH_handle_to_context (exchange);
  rgah->job = GNUNET_CURL_job_add (ctx,
                                   eh,
                                   &handle_reserves_get_attestable_finished,
                                   rgah);
  return rgah;
}


void
TALER_EXCHANGE_reserves_get_attestable_cancel (
  struct TALER_EXCHANGE_ReservesGetAttestHandle *rgah)
{
  if (NULL != rgah->job)
  {
    GNUNET_CURL_job_cancel (rgah->job);
    rgah->job = NULL;
  }
  GNUNET_free (rgah->url);
  GNUNET_free (rgah);
}


/* end of exchange_api_reserves_get_attestable.c */
