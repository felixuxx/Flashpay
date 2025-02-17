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
 * @file lib/exchange_api_management_post_extensions.c
 * @brief functions to handle the settings for extensions (p2p and age restriction)
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_extensions.h"
#include "exchange_api_curl_defaults.h"
#include "taler_exchange_service.h"
#include "taler_signatures.h"
#include "taler_curl_lib.h"
#include "taler_json_lib.h"


/**
 * @brief Handle for a POST /management/extensions request.
 */
struct TALER_EXCHANGE_ManagementPostExtensionsHandle
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
  TALER_EXCHANGE_ManagementPostExtensionsCallback cb;

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
 * HTTP POST /management/extensions request.
 *
 * @param cls the `struct TALER_EXCHANGE_ManagementPostExtensionsHandle *`
 * @param response_code HTTP response code, 0 on error
 * @param response response body, NULL if not in JSON
 */
static void
handle_post_extensions_finished (void *cls,
                                 long response_code,
                                 const void *response)
{
  struct TALER_EXCHANGE_ManagementPostExtensionsHandle *ph = cls;
  const json_t *json = response;
  struct TALER_EXCHANGE_ManagementPostExtensionsResponse per = {
    .hr.http_status = (unsigned int) response_code,
    .hr.reply = json
  };

  ph->job = NULL;
  switch (response_code)
  {
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_FORBIDDEN:
    per.hr.ec = TALER_JSON_get_error_code (json);
    per.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  case MHD_HTTP_NOT_FOUND:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Server did not find handler at `%s'. Did you configure the correct exchange base URL?\n",
                ph->url);
    if (NULL != json)
    {
      per.hr.ec = TALER_JSON_get_error_code (json);
      per.hr.hint = TALER_JSON_get_error_hint (json);
    }
    else
    {
      per.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
      per.hr.hint = TALER_ErrorCode_get_hint (per.hr.ec);
    }
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    per.hr.ec = TALER_JSON_get_error_code (json);
    per.hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange management post extensions\n",
                (unsigned int) response_code,
                (int) per.hr.ec);
    break;
  }
  if (NULL != ph->cb)
  {
    ph->cb (ph->cb_cls,
            &per);
    ph->cb = NULL;
  }
  TALER_EXCHANGE_management_post_extensions_cancel (ph);
}


struct TALER_EXCHANGE_ManagementPostExtensionsHandle *
TALER_EXCHANGE_management_post_extensions (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_EXCHANGE_ManagementPostExtensionsData *ped,
  TALER_EXCHANGE_ManagementPostExtensionsCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ManagementPostExtensionsHandle *ph;
  CURL *eh = NULL;
  json_t *body = NULL;

  ph = GNUNET_new (struct TALER_EXCHANGE_ManagementPostExtensionsHandle);
  ph->cb = cb;
  ph->cb_cls = cb_cls;
  ph->ctx = ctx;
  ph->url = TALER_url_join (url,
                            "management/extensions",
                            NULL);
  if (NULL == ph->url)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not construct request URL.\n");
    GNUNET_free (ph);
    return NULL;
  }

  body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_object_steal ("extensions",
                                   (json_t *) ped->extensions),
    GNUNET_JSON_pack_data_auto ("extensions_sig",
                                &ped->extensions_sig));

  eh = TALER_EXCHANGE_curl_easy_get_ (ph->url);
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&ph->post_ctx,
                              eh,
                              body)) )
  {
    GNUNET_break (0);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (body);
    GNUNET_free (ph->url);
    return NULL;
  }
  json_decref (body);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Requesting URL '%s'\n",
              ph->url);
  ph->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  ph->post_ctx.headers,
                                  &handle_post_extensions_finished,
                                  ph);
  if (NULL == ph->job)
  {
    TALER_EXCHANGE_management_post_extensions_cancel (ph);
    return NULL;
  }
  return ph;
}


void
TALER_EXCHANGE_management_post_extensions_cancel (
  struct TALER_EXCHANGE_ManagementPostExtensionsHandle *ph)
{
  if (NULL != ph->job)
  {
    GNUNET_CURL_job_cancel (ph->job);
    ph->job = NULL;
  }
  TALER_curl_easy_post_finished (&ph->post_ctx);
  GNUNET_free (ph->url);
  GNUNET_free (ph);
}
