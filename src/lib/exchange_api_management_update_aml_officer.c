/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file lib/exchange_api_management_update_aml_officer.c
 * @brief functions to update AML officer status
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


struct TALER_EXCHANGE_ManagementUpdateAmlOfficer
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
  TALER_EXCHANGE_ManagementUpdateAmlOfficerCallback cb;

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
handle_update_aml_officer_finished (void *cls,
                                    long response_code,
                                    const void *response)
{
  struct TALER_EXCHANGE_ManagementUpdateAmlOfficer *wh = cls;
  const json_t *json = response;
  struct TALER_EXCHANGE_ManagementUpdateAmlOfficerResponse uar = {
    .hr.http_status = (unsigned int) response_code,
    .hr.reply = json
  };

  wh->job = NULL;
  switch (response_code)
  {
  case 0:
    /* no reply */
    uar.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    uar.hr.hint = "server offline?";
    break;
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_FORBIDDEN:
    uar.hr.ec = TALER_JSON_get_error_code (json);
    uar.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  case MHD_HTTP_NOT_FOUND:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Server did not find handler at `%s'. Did you configure the correct exchange base URL?\n",
                wh->url);
    if (NULL != json)
    {
      uar.hr.ec = TALER_JSON_get_error_code (json);
      uar.hr.hint = TALER_JSON_get_error_hint (json);
    }
    else
    {
      uar.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
      uar.hr.hint = TALER_ErrorCode_get_hint (uar.hr.ec);
    }
    break;
  case MHD_HTTP_CONFLICT:
    uar.hr.ec = TALER_JSON_get_error_code (json);
    uar.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    uar.hr.ec = TALER_JSON_get_error_code (json);
    uar.hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange management update AML officer\n",
                (unsigned int) response_code,
                (int) uar.hr.ec);
    break;
  }
  if (NULL != wh->cb)
  {
    wh->cb (wh->cb_cls,
            &uar);
    wh->cb = NULL;
  }
  TALER_EXCHANGE_management_update_aml_officer_cancel (wh);
}


struct TALER_EXCHANGE_ManagementUpdateAmlOfficer *
TALER_EXCHANGE_management_update_aml_officer (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_AmlOfficerPublicKeyP *officer_pub,
  const char *officer_name,
  struct GNUNET_TIME_Timestamp change_date,
  bool is_active,
  bool read_only,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementUpdateAmlOfficerCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ManagementUpdateAmlOfficer *wh;
  CURL *eh;
  json_t *body;

  wh = GNUNET_new (struct TALER_EXCHANGE_ManagementUpdateAmlOfficer);
  wh->cb = cb;
  wh->cb_cls = cb_cls;
  wh->ctx = ctx;
  wh->url = TALER_url_join (url,
                            "management/aml-officers",
                            NULL);
  if (NULL == wh->url)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not construct request URL.\n");
    GNUNET_free (wh);
    return NULL;
  }
  body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("officer_name",
                             officer_name),
    GNUNET_JSON_pack_data_auto ("officer_pub",
                                officer_pub),
    GNUNET_JSON_pack_data_auto ("master_sig",
                                master_sig),
    GNUNET_JSON_pack_bool ("is_active",
                           is_active),
    GNUNET_JSON_pack_bool ("read_only",
                           read_only),
    GNUNET_JSON_pack_timestamp ("change_date",
                                change_date));
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
                                  &handle_update_aml_officer_finished,
                                  wh);
  if (NULL == wh->job)
  {
    TALER_EXCHANGE_management_update_aml_officer_cancel (wh);
    return NULL;
  }
  return wh;
}


void
TALER_EXCHANGE_management_update_aml_officer_cancel (
  struct TALER_EXCHANGE_ManagementUpdateAmlOfficer *wh)
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
