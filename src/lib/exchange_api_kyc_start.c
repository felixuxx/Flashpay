/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

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
 * @file lib/exchange_api_kyc_start.c
 * @brief functions to start a KYC process
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "exchange_api_curl_defaults.h"
#include "taler_signatures.h"
#include "taler_curl_lib.h"
#include "taler_json_lib.h"


struct TALER_EXCHANGE_KycStartHandle
{

  /**
   * The url for this request.
   */
  char *url;

  /**
   * Minor context that holds body and headers.
   */
  struct TALER_CURL_PostContext post_ctx;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_KycStartCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Reference to the execution context.
   */
  struct GNUNET_CURL_Context *ctx;
};


/**
 * Function called when we're done processing the
 * HTTP POST /kyc-start/$ID request.
 *
 * @param cls the `struct TALER_EXCHANGE_KycStartHandle *`
 * @param response_code HTTP response code, 0 on error
 * @param response response body, NULL if not in JSON
 */
static void
handle_kyc_start_finished (void *cls,
                           long response_code,
                           const void *response)
{
  struct TALER_EXCHANGE_KycStartHandle *wh = cls;
  const json_t *json = response;
  struct TALER_EXCHANGE_KycStartResponse adr = {
    .hr.http_status = (unsigned int) response_code,
    .hr.reply = json
  };

  wh->job = NULL;
  switch (response_code)
  {
  case 0:
    /* no reply */
    adr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    adr.hr.hint = "server offline?";
    break;
  case MHD_HTTP_OK:
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_string (
          "redirect_url",
          &adr.details.ok.redirect_url),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (json,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        adr.hr.http_status = 0;
        adr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
    }
    break;
  case MHD_HTTP_NOT_FOUND:
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    adr.hr.ec = TALER_JSON_get_error_code (json);
    adr.hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange AML decision\n",
                (unsigned int) response_code,
                (int) adr.hr.ec);
    break;
  }
  if (NULL != wh->cb)
  {
    wh->cb (wh->cb_cls,
            &adr);
    wh->cb = NULL;
  }
  TALER_EXCHANGE_kyc_start_cancel (wh);
}


struct TALER_EXCHANGE_KycStartHandle *
TALER_EXCHANGE_kyc_start (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const char *id,
  TALER_EXCHANGE_KycStartCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_KycStartHandle *wh;
  CURL *eh;
  json_t *body;

  wh = GNUNET_new (struct TALER_EXCHANGE_KycStartHandle);
  wh->cb = cb;
  wh->cb_cls = cb_cls;
  wh->ctx = ctx;
  {
    char *path;

    GNUNET_asprintf (&path,
                     "kyc-start/%s",
                     id);
    wh->url = TALER_url_join (url,
                              path,
                              NULL);
    GNUNET_free (path);
  }
  if (NULL == wh->url)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not construct request URL.\n");
    GNUNET_free (wh);
    return NULL;
  }
  body = json_object (); /* as per spec: empty! */
  GNUNET_assert (NULL != body);
  eh = TALER_EXCHANGE_curl_easy_get_ (wh->url);
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&wh->post_ctx,
                              eh,
                              body)) )
  {
    GNUNET_break (0);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (body);
    GNUNET_free (wh->url);
    return NULL;
  }
  json_decref (body);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting URL '%s'\n",
              wh->url);
  wh->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  wh->post_ctx.headers,
                                  &handle_kyc_start_finished,
                                  wh);
  if (NULL == wh->job)
  {
    TALER_EXCHANGE_kyc_start_cancel (wh);
    return NULL;
  }
  return wh;
}


void
TALER_EXCHANGE_kyc_start_cancel (
  struct TALER_EXCHANGE_KycStartHandle *wh)
{
  if (NULL != wh->job)
  {
    GNUNET_CURL_job_cancel (wh->job);
    wh->job = NULL;
  }
  TALER_curl_easy_post_finished (&wh->post_ctx);
  GNUNET_free (wh->url);
  GNUNET_free (wh);
}
