/*
  This file is part of TALER
  Copyright (C) 2015-2020 Taler Systems SA

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
 * @file lib/exchange_api_management_wire_disable.c
 * @brief functions to disable an exchange wire method / bank account
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_signatures.h"
#include "taler_curl_lib.h"
#include "taler_json_lib.h"


struct TALER_EXCHANGE_ManagementWireDisableHandle
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
  TALER_EXCHANGE_ManagementWireDisableCallback cb;

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
 * HTTP /management/wire/disable request.
 *
 * @param cls the `struct TALER_EXCHANGE_ManagementAuditorDisableHandle *`
 * @param response_code HTTP response code, 0 on error
 * @param response response body, NULL if not in JSON
 */
static void
handle_auditor_disable_finished (void *cls,
                                 long response_code,
                                 const void *response)
{
  struct TALER_EXCHANGE_ManagementWireDisableHandle *wh = cls;
  const json_t *json = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .http_status = (unsigned int) response_code,
    .reply = json
  };

  wh->job = NULL;
  switch (response_code)
  {
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_FORBIDDEN:
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    break;
  case MHD_HTTP_NOT_FOUND:
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    break;
  case MHD_HTTP_CONFLICT:
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d\n",
                (unsigned int) response_code,
                (int) hr.ec);
    break;
  }
  if (NULL != wh->cb)
  {
    wh->cb (wh->cb_cls,
            &hr);
    wh->cb = NULL;
  }
  TALER_EXCHANGE_management_disable_wire_cancel (wh);
}


struct TALER_EXCHANGE_ManagementWireDisableHandle *
TALER_EXCHANGE_management_disable_wire (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const char *payto_uri,
  struct GNUNET_TIME_Absolute validity_end,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementWireDisableCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ManagementWireDisableHandle *wh;
  CURL *eh;
  json_t *body;

  wh = GNUNET_new (struct TALER_EXCHANGE_ManagementWireDisableHandle);
  wh->cb = cb;
  wh->cb_cls = cb_cls;
  wh->ctx = ctx;
  wh->url = TALER_url_join (url,
                            "management/wire/disable",
                            NULL);
  if (NULL == wh->url)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not construct request URL.\n");
    GNUNET_free (wh);
    return NULL;
  }
  body = json_pack ("{s:s, s:o, s:o}",
                    "payto_uri",
                    payto_uri,
                    "master_sig_del",
                    GNUNET_JSON_from_data_auto (master_sig),
                    "validity_end",
                    GNUNET_JSON_from_time_abs (validity_end));
  if (NULL == body)
  {
    GNUNET_break (0);
    GNUNET_free (wh->url);
    GNUNET_free (wh);
    return NULL;
  }
  eh = curl_easy_init ();
  if (GNUNET_OK !=
      TALER_curl_easy_post (&wh->post_ctx,
                            eh,
                            body))
  {
    GNUNET_break (0);
    json_decref (body);
    GNUNET_free (wh->url);
    GNUNET_free (eh);
    return NULL;
  }
  json_decref (body);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting URL '%s'\n",
              wh->url);
  GNUNET_assert (CURLE_OK == curl_easy_setopt (eh,
                                               CURLOPT_URL,
                                               wh->url));
  wh->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  wh->post_ctx.headers,
                                  &handle_auditor_disable_finished,
                                  wh);
  if (NULL == wh->job)
  {
    TALER_EXCHANGE_management_disable_wire_cancel (wh);
    return NULL;
  }
  return wh;
}


void
TALER_EXCHANGE_management_disable_wire_cancel (
  struct TALER_EXCHANGE_ManagementWireDisableHandle *wh)
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
