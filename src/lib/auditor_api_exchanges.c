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
 * @file lib/auditor_api_exchanges.c
 * @brief Implementation of the /exchanges request of the auditor's HTTP API
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
 * How many exchanges do we allow a single auditor to
 * audit at most?
 */
#define MAX_EXCHANGES 1024


/**
 * @brief A ListExchanges Handle
 */
struct TALER_AUDITOR_ListExchangesHandle
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
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_AUDITOR_ListExchangesResultCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * Function called when we're done processing the
 * HTTP /deposit-confirmation request.
 *
 * @param cls the `struct TALER_AUDITOR_ListExchangesHandle`
 * @param response_code HTTP response code, 0 on error
 * @param djson parsed JSON result, NULL on error
 */
static void
handle_exchanges_finished (void *cls,
                           long response_code,
                           const void *djson)
{
  const json_t *json = djson;
  const json_t *ja;
  unsigned int ja_len;
  struct TALER_AUDITOR_ListExchangesHandle *leh = cls;
  struct TALER_AUDITOR_HttpResponse hr = {
    .reply = json,
    .http_status = (unsigned int) response_code
  };

  leh->job = NULL;
  switch (response_code)
  {
  case 0:
    hr.ec = TALER_EC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    ja = json_object_get (json,
                          "exchanges");
    if ( (NULL == ja) ||
         (! json_is_array (ja)) )
    {
      GNUNET_break (0);
      hr.ec = TALER_EC_AUDITOR_EXCHANGES_REPLY_MALFORMED;
      hr.http_status = 0;
      break;
    }

    ja_len = json_array_size (ja);
    if (ja_len > MAX_EXCHANGES)
    {
      GNUNET_break (0);
      hr.ec = TALER_EC_AUDITOR_EXCHANGES_REPLY_MALFORMED;
      hr.http_status = 0;
      break;
    }
    {
      struct TALER_AUDITOR_ExchangeInfo ei[ja_len];
      int ok;

      ok = GNUNET_YES;
      for (unsigned int i = 0; i<ja_len; i++)
      {
        struct GNUNET_JSON_Specification spec[] = {
          GNUNET_JSON_spec_fixed_auto ("master_pub", &ei[i].master_pub),
          GNUNET_JSON_spec_string ("exchange_url", &ei[i].exchange_url),
          GNUNET_JSON_spec_end ()
        };

        if (GNUNET_OK !=
            GNUNET_JSON_parse (json_array_get (ja,
                                               i),
                               spec,
                               NULL, NULL))
        {
          GNUNET_break_op (0);
          ok = GNUNET_NO;
          hr.ec = TALER_EC_AUDITOR_EXCHANGES_REPLY_MALFORMED;
          hr.http_status = 0;
          break;
        }
      }
      if (GNUNET_YES != ok)
        break;
      leh->cb (leh->cb_cls,
               &hr,
               ja_len,
               ei);
      TALER_AUDITOR_list_exchanges_cancel (leh);
      return;
    }
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the auditor is buggy
       (or API version conflict); just pass JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    break;
  default:
    /* unexpected response code */
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d\n",
                (unsigned int) response_code,
                (int) hr.ec);
    GNUNET_break_op (0);
    break;
  }
  if (NULL != leh->cb)
    leh->cb (leh->cb_cls,
             &hr,
             0,
             NULL);
  TALER_AUDITOR_list_exchanges_cancel (leh);
}


/**
 * Submit an /exchanges request to the auditor and get the
 * auditor's response.  If the auditor's reply is not
 * well-formed, we return an HTTP status code of zero to @a cb.
 *
 * @param auditor the auditor handle; the auditor must be ready to operate
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_AUDITOR_ListExchangesHandle *
TALER_AUDITOR_list_exchanges (struct TALER_AUDITOR_Handle *auditor,
                              TALER_AUDITOR_ListExchangesResultCallback cb,
                              void *cb_cls)
{
  struct TALER_AUDITOR_ListExchangesHandle *leh;
  struct GNUNET_CURL_Context *ctx;
  CURL *eh;

  GNUNET_assert (GNUNET_YES ==
                 TALER_AUDITOR_handle_is_ready_ (auditor));

  leh = GNUNET_new (struct TALER_AUDITOR_ListExchangesHandle);
  leh->auditor = auditor;
  leh->cb = cb;
  leh->cb_cls = cb_cls;
  leh->url = TALER_AUDITOR_path_to_url_ (auditor, "/exchanges");

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "URL for list-exchanges: `%s'\n",
              leh->url);
  eh = TALER_AUDITOR_curl_easy_get_ (leh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (leh->url);
    GNUNET_free (leh);
    return NULL;
  }
  ctx = TALER_AUDITOR_handle_to_context_ (auditor);
  leh->job = GNUNET_CURL_job_add (ctx,
                                  eh,
                                  GNUNET_NO,
                                  &handle_exchanges_finished,
                                  leh);
  return leh;
}


/**
 * Cancel a list exchanges request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param leh the list exchanges request handle
 */
void
TALER_AUDITOR_list_exchanges_cancel (struct
                                     TALER_AUDITOR_ListExchangesHandle *leh)
{
  if (NULL != leh->job)
  {
    GNUNET_CURL_job_cancel (leh->job);
    leh->job = NULL;
  }
  GNUNET_free (leh->url);
  GNUNET_free (leh);
}


/* end of auditor_api_exchanges.c */
