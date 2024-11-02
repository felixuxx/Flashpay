/*
  This file is part of TALER
  Copyright (C) 2020-2023 Taler Systems SA

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
 * @file lib/exchange_api_management_drain_profits.c
 * @brief functions to set wire fees at an exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_curl_defaults.h"
#include "taler_exchange_service.h"
#include "taler_signatures.h"
#include "taler_curl_lib.h"
#include "taler_json_lib.h"


struct TALER_EXCHANGE_ManagementDrainProfitsHandle
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
  TALER_EXCHANGE_ManagementDrainProfitsCallback cb;

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
 * HTTP /management/drain request.
 *
 * @param cls the `struct TALER_EXCHANGE_ManagementDrainProfitsHandle *`
 * @param response_code HTTP response code, 0 on error
 * @param response response body, NULL if not in JSON
 */
static void
handle_drain_profits_finished (void *cls,
                               long response_code,
                               const void *response)
{
  struct TALER_EXCHANGE_ManagementDrainProfitsHandle *dp = cls;
  const json_t *json = response;
  struct TALER_EXCHANGE_ManagementDrainResponse dr = {
    .hr.http_status = (unsigned int) response_code,
    .hr.reply = json
  };

  dp->job = NULL;
  switch (response_code)
  {
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_FORBIDDEN:
    dr.hr.ec = TALER_JSON_get_error_code (json);
    dr.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  case MHD_HTTP_CONFLICT:
    dr.hr.ec = TALER_JSON_get_error_code (json);
    dr.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  case MHD_HTTP_PRECONDITION_FAILED:
    dr.hr.ec = TALER_JSON_get_error_code (json);
    dr.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    dr.hr.ec = TALER_JSON_get_error_code (json);
    dr.hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange management drain profits\n",
                (unsigned int) response_code,
                (int) dr.hr.ec);
    break;
  }
  if (NULL != dp->cb)
  {
    dp->cb (dp->cb_cls,
            &dr);
    dp->cb = NULL;
  }
  TALER_EXCHANGE_management_drain_profits_cancel (dp);
}


struct TALER_EXCHANGE_ManagementDrainProfitsHandle *
TALER_EXCHANGE_management_drain_profits (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_Amount *amount,
  struct GNUNET_TIME_Timestamp date,
  const char *account_section,
  const struct TALER_FullPayto payto_uri,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementDrainProfitsCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ManagementDrainProfitsHandle *dp;
  CURL *eh;
  json_t *body;

  dp = GNUNET_new (struct TALER_EXCHANGE_ManagementDrainProfitsHandle);
  dp->cb = cb;
  dp->cb_cls = cb_cls;
  dp->ctx = ctx;
  dp->url = TALER_url_join (url,
                            "management/drain",
                            NULL);
  if (NULL == dp->url)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not construct request URL.\n");
    GNUNET_free (dp);
    return NULL;
  }
  body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("debit_account_section",
                             account_section),
    TALER_JSON_pack_full_payto ("credit_payto_uri",
                                payto_uri),
    GNUNET_JSON_pack_data_auto ("wtid",
                                wtid),
    GNUNET_JSON_pack_data_auto ("master_sig",
                                master_sig),
    GNUNET_JSON_pack_timestamp ("date",
                                date),
    TALER_JSON_pack_amount ("amount",
                            amount));
  eh = TALER_EXCHANGE_curl_easy_get_ (dp->url);
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&dp->post_ctx,
                              eh,
                              body)) )
  {
    GNUNET_break (0);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (body);
    GNUNET_free (dp->url);
    return NULL;
  }
  json_decref (body);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting URL '%s'\n",
              dp->url);
  dp->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  dp->post_ctx.headers,
                                  &handle_drain_profits_finished,
                                  dp);
  if (NULL == dp->job)
  {
    TALER_EXCHANGE_management_drain_profits_cancel (dp);
    return NULL;
  }
  return dp;
}


void
TALER_EXCHANGE_management_drain_profits_cancel (
  struct TALER_EXCHANGE_ManagementDrainProfitsHandle *dp)
{
  if (NULL != dp->job)
  {
    GNUNET_CURL_job_cancel (dp->job);
    dp->job = NULL;
  }
  TALER_curl_easy_post_finished (&dp->post_ctx);
  GNUNET_free (dp->url);
  GNUNET_free (dp);
}
