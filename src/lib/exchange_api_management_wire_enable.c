/*
  This file is part of TALER
  Copyright (C) 2015-2023 Taler Systems SA

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
 * @file lib/exchange_api_management_wire_enable.c
 * @brief functions to enable an exchange wire method / bank account
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


struct TALER_EXCHANGE_ManagementWireEnableHandle
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
  TALER_EXCHANGE_ManagementWireEnableCallback cb;

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
 * HTTP /management/wire request.
 *
 * @param cls the `struct TALER_EXCHANGE_ManagementAuditorEnableHandle *`
 * @param response_code HTTP response code, 0 on error
 * @param response response body, NULL if not in JSON
 */
static void
handle_auditor_enable_finished (void *cls,
                                long response_code,
                                const void *response)
{
  struct TALER_EXCHANGE_ManagementWireEnableHandle *wh = cls;
  const json_t *json = response;
  struct TALER_EXCHANGE_ManagementWireEnableResponse wer = {
    .hr.http_status = (unsigned int) response_code,
    .hr.reply = json
  };

  wh->job = NULL;
  switch (response_code)
  {
  case 0:
    /* no reply */
    wer.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    wer.hr.hint = "server offline?";
    break;
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_FORBIDDEN:
    wer.hr.ec = TALER_JSON_get_error_code (json);
    wer.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  case MHD_HTTP_NOT_FOUND:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Server did not find handler at `%s'. Did you configure the correct exchange base URL?\n",
                wh->url);
    if (NULL != json)
    {
      wer.hr.ec = TALER_JSON_get_error_code (json);
      wer.hr.hint = TALER_JSON_get_error_hint (json);
    }
    else
    {
      wer.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
      wer.hr.hint = TALER_ErrorCode_get_hint (wer.hr.ec);
    }
    break;
  case MHD_HTTP_CONFLICT:
    wer.hr.ec = TALER_JSON_get_error_code (json);
    wer.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    wer.hr.ec = TALER_JSON_get_error_code (json);
    wer.hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange management enable wire\n",
                (unsigned int) response_code,
                (int) wer.hr.ec);
    break;
  }
  if (NULL != wh->cb)
  {
    wh->cb (wh->cb_cls,
            &wer);
    wh->cb = NULL;
  }
  TALER_EXCHANGE_management_enable_wire_cancel (wh);
}


struct TALER_EXCHANGE_ManagementWireEnableHandle *
TALER_EXCHANGE_management_enable_wire (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const char *payto_uri,
  const char *conversion_url,
  const json_t *debit_restrictions,
  const json_t *credit_restrictions,
  struct GNUNET_TIME_Timestamp validity_start,
  const struct TALER_MasterSignatureP *master_sig1,
  const struct TALER_MasterSignatureP *master_sig2,
  TALER_EXCHANGE_ManagementWireEnableCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ManagementWireEnableHandle *wh;
  CURL *eh;
  json_t *body;

  {
    char *msg = TALER_payto_validate (payto_uri);

    if (NULL != msg)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "payto URI is malformed: %s\n",
                  msg);
      GNUNET_free (msg);
      return NULL;
    }
  }
  wh = GNUNET_new (struct TALER_EXCHANGE_ManagementWireEnableHandle);
  wh->cb = cb;
  wh->cb_cls = cb_cls;
  wh->ctx = ctx;
  wh->url = TALER_url_join (url,
                            "management/wire",
                            NULL);
  if (NULL == wh->url)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not construct request URL.\n");
    GNUNET_free (wh);
    return NULL;
  }
  body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("payto_uri",
                             payto_uri),
    GNUNET_JSON_pack_array_incref ("debit_restrictions",
                                   (json_t *) debit_restrictions),
    GNUNET_JSON_pack_array_incref ("credit_restrictions",
                                   (json_t *) credit_restrictions),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_string ("conversion_url",
                               conversion_url)),
    GNUNET_JSON_pack_data_auto ("master_sig_add",
                                master_sig1),
    GNUNET_JSON_pack_data_auto ("master_sig_wire",
                                master_sig2),
    GNUNET_JSON_pack_timestamp ("validity_start",
                                validity_start));
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
    GNUNET_free (wh);
    return NULL;
  }
  json_decref (body);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting URL '%s'\n",
              wh->url);
  wh->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  wh->post_ctx.headers,
                                  &handle_auditor_enable_finished,
                                  wh);
  if (NULL == wh->job)
  {
    TALER_EXCHANGE_management_enable_wire_cancel (wh);
    return NULL;
  }
  return wh;
}


void
TALER_EXCHANGE_management_enable_wire_cancel (
  struct TALER_EXCHANGE_ManagementWireEnableHandle *wh)
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
