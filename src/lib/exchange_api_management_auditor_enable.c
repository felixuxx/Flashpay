/*
  This file is part of TALER
  Copyright (C) 2015-2021 Taler Systems SA

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
 * @file lib/exchange_api_management_auditor_enable.c
 * @brief functions to enable an auditor
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


/**
 * @brief Handle for a POST /management/auditors request.
 */
struct TALER_EXCHANGE_ManagementAuditorEnableHandle
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
  TALER_EXCHANGE_ManagementAuditorEnableCallback cb;

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
 * HTTP POST /management/auditors request.
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
  struct TALER_EXCHANGE_ManagementAuditorEnableHandle *ah = cls;
  const json_t *json = response;
  struct TALER_EXCHANGE_ManagementAuditorEnableResponse aer = {
    .hr.http_status = (unsigned int) response_code,
    .hr.reply = json
  };

  ah->job = NULL;
  switch (response_code)
  {
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_FORBIDDEN:
    aer.hr.ec = TALER_JSON_get_error_code (json);
    aer.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  case MHD_HTTP_NOT_FOUND:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Server did not find handler at `%s'. Did you configure the correct exchange base URL?\n",
                ah->url);
    if (NULL != json)
    {
      aer.hr.ec = TALER_JSON_get_error_code (json);
      aer.hr.hint = TALER_JSON_get_error_hint (json);
    }
    else
    {
      aer.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
      aer.hr.hint = TALER_ErrorCode_get_hint (aer.hr.ec);
    }
    break;
  case MHD_HTTP_CONFLICT:
    aer.hr.ec = TALER_JSON_get_error_code (json);
    aer.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    aer.hr.ec = TALER_JSON_get_error_code (json);
    aer.hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange management auditor enable\n",
                (unsigned int) response_code,
                (int) aer.hr.ec);
    break;
  }
  if (NULL != ah->cb)
  {
    ah->cb (ah->cb_cls,
            &aer);
    ah->cb = NULL;
  }
  TALER_EXCHANGE_management_enable_auditor_cancel (ah);
}


struct TALER_EXCHANGE_ManagementAuditorEnableHandle *
TALER_EXCHANGE_management_enable_auditor (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const char *auditor_url,
  const char *auditor_name,
  struct GNUNET_TIME_Timestamp validity_start,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementAuditorEnableCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ManagementAuditorEnableHandle *ah;
  CURL *eh;
  json_t *body;

  ah = GNUNET_new (struct TALER_EXCHANGE_ManagementAuditorEnableHandle);
  ah->cb = cb;
  ah->cb_cls = cb_cls;
  ah->ctx = ctx;
  ah->url = TALER_url_join (url,
                            "management/auditors",
                            NULL);
  if (NULL == ah->url)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not construct request URL.\n");
    GNUNET_free (ah);
    return NULL;
  }
  body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("auditor_url",
                             auditor_url),
    GNUNET_JSON_pack_string ("auditor_name",
                             auditor_name),
    GNUNET_JSON_pack_data_auto ("auditor_pub",
                                auditor_pub),
    GNUNET_JSON_pack_data_auto ("master_sig",
                                master_sig),
    GNUNET_JSON_pack_timestamp ("validity_start",
                                validity_start));
  eh = TALER_EXCHANGE_curl_easy_get_ (ah->url);
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&ah->post_ctx,
                              eh,
                              body)) )
  {
    GNUNET_break (0);
    json_decref (body);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    GNUNET_free (ah->url);
    return NULL;
  }
  json_decref (body);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting URL '%s'\n",
              ah->url);
  ah->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  ah->post_ctx.headers,
                                  &handle_auditor_enable_finished,
                                  ah);
  if (NULL == ah->job)
  {
    TALER_EXCHANGE_management_enable_auditor_cancel (ah);
    return NULL;
  }
  return ah;
}


void
TALER_EXCHANGE_management_enable_auditor_cancel (
  struct TALER_EXCHANGE_ManagementAuditorEnableHandle *ah)
{
  if (NULL != ah->job)
  {
    GNUNET_CURL_job_cancel (ah->job);
    ah->job = NULL;
  }
  TALER_curl_easy_post_finished (&ah->post_ctx);
  GNUNET_free (ah->url);
  GNUNET_free (ah);
}
