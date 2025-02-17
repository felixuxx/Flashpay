/*
  This file is part of TALER
  Copyright (C) 2020-2022 Taler Systems SA

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
 * @file lib/exchange_api_management_set_global_fee.c
 * @brief functions to set global fees at an exchange
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


struct TALER_EXCHANGE_ManagementSetGlobalFeeHandle
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
  TALER_EXCHANGE_ManagementSetGlobalFeeCallback cb;

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
 * HTTP /management/global request.
 *
 * @param cls the `struct TALER_EXCHANGE_ManagementAuditorEnableHandle *`
 * @param response_code HTTP response code, 0 on error
 * @param response response body, NULL if not in JSON
 */
static void
handle_set_global_fee_finished (void *cls,
                                long response_code,
                                const void *response)
{
  struct TALER_EXCHANGE_ManagementSetGlobalFeeHandle *sgfh = cls;
  const json_t *json = response;
  struct TALER_EXCHANGE_ManagementSetGlobalFeeResponse sfr = {
    .hr.http_status = (unsigned int) response_code,
    .hr.reply = json
  };

  sgfh->job = NULL;
  switch (response_code)
  {
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_FORBIDDEN:
    sfr.hr.ec = TALER_JSON_get_error_code (json);
    sfr.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  case MHD_HTTP_NOT_FOUND:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Server did not find handler at `%s'. Did you configure the correct exchange base URL?\n",
                sgfh->url);
    if (NULL != json)
    {
      sfr.hr.ec = TALER_JSON_get_error_code (json);
      sfr.hr.hint = TALER_JSON_get_error_hint (json);
    }
    else
    {
      sfr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
      sfr.hr.hint = TALER_ErrorCode_get_hint (sfr.hr.ec);
    }
    break;
  case MHD_HTTP_CONFLICT:
    sfr.hr.ec = TALER_JSON_get_error_code (json);
    sfr.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  case MHD_HTTP_PRECONDITION_FAILED:
    sfr.hr.ec = TALER_JSON_get_error_code (json);
    sfr.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    sfr.hr.ec = TALER_JSON_get_error_code (json);
    sfr.hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange management set global fee\n",
                (unsigned int) response_code,
                (int) sfr.hr.ec);
    break;
  }
  if (NULL != sgfh->cb)
  {
    sgfh->cb (sgfh->cb_cls,
              &sfr);
    sgfh->cb = NULL;
  }
  TALER_EXCHANGE_management_set_global_fees_cancel (sgfh);
}


struct TALER_EXCHANGE_ManagementSetGlobalFeeHandle *
TALER_EXCHANGE_management_set_global_fees (
  struct GNUNET_CURL_Context *ctx,
  const char *exchange_base_url,
  struct GNUNET_TIME_Timestamp validity_start,
  struct GNUNET_TIME_Timestamp validity_end,
  const struct TALER_GlobalFeeSet *fees,
  struct GNUNET_TIME_Relative purse_timeout,
  struct GNUNET_TIME_Relative history_expiration,
  uint32_t purse_account_limit,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementSetGlobalFeeCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ManagementSetGlobalFeeHandle *sgfh;
  CURL *eh;
  json_t *body;

  sgfh = GNUNET_new (struct TALER_EXCHANGE_ManagementSetGlobalFeeHandle);
  sgfh->cb = cb;
  sgfh->cb_cls = cb_cls;
  sgfh->ctx = ctx;
  sgfh->url = TALER_url_join (exchange_base_url,
                              "management/global-fee",
                              NULL);
  if (NULL == sgfh->url)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not construct request URL.\n");
    GNUNET_free (sgfh);
    return NULL;
  }
  body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_data_auto ("master_sig",
                                master_sig),
    GNUNET_JSON_pack_timestamp ("fee_start",
                                validity_start),
    GNUNET_JSON_pack_timestamp ("fee_end",
                                validity_end),
    TALER_JSON_pack_amount ("history_fee",
                            &fees->history),
    TALER_JSON_pack_amount ("account_fee",
                            &fees->account),
    TALER_JSON_pack_amount ("purse_fee",
                            &fees->purse),
    GNUNET_JSON_pack_time_rel ("purse_timeout",
                               purse_timeout),
    GNUNET_JSON_pack_time_rel ("history_expiration",
                               history_expiration),
    GNUNET_JSON_pack_uint64 ("purse_account_limit",
                             purse_account_limit));
  eh = TALER_EXCHANGE_curl_easy_get_ (sgfh->url);
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&sgfh->post_ctx,
                              eh,
                              body)) )
  {
    GNUNET_break (0);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (body);
    GNUNET_free (sgfh->url);
    GNUNET_free (sgfh);
    return NULL;
  }
  json_decref (body);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting URL '%s'\n",
              sgfh->url);
  sgfh->job = GNUNET_CURL_job_add2 (ctx,
                                    eh,
                                    sgfh->post_ctx.headers,
                                    &handle_set_global_fee_finished,
                                    sgfh);
  if (NULL == sgfh->job)
  {
    TALER_EXCHANGE_management_set_global_fees_cancel (sgfh);
    return NULL;
  }
  return sgfh;
}


void
TALER_EXCHANGE_management_set_global_fees_cancel (
  struct TALER_EXCHANGE_ManagementSetGlobalFeeHandle *sgfh)
{
  if (NULL != sgfh->job)
  {
    GNUNET_CURL_job_cancel (sgfh->job);
    sgfh->job = NULL;
  }
  TALER_curl_easy_post_finished (&sgfh->post_ctx);
  GNUNET_free (sgfh->url);
  GNUNET_free (sgfh);
}
