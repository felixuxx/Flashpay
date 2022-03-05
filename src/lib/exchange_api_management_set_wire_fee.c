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
 * @file lib/exchange_api_management_set_wire_fee.c
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


struct TALER_EXCHANGE_ManagementSetWireFeeHandle
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
  TALER_EXCHANGE_ManagementSetWireFeeCallback cb;

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
handle_set_wire_fee_finished (void *cls,
                              long response_code,
                              const void *response)
{
  struct TALER_EXCHANGE_ManagementSetWireFeeHandle *swfh = cls;
  const json_t *json = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .http_status = (unsigned int) response_code,
    .reply = json
  };

  swfh->job = NULL;
  switch (response_code)
  {
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_FORBIDDEN:
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    break;
  case MHD_HTTP_CONFLICT:
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    break;
  case MHD_HTTP_PRECONDITION_FAILED:
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange management set wire fee\n",
                (unsigned int) response_code,
                (int) hr.ec);
    break;
  }
  if (NULL != swfh->cb)
  {
    swfh->cb (swfh->cb_cls,
              &hr);
    swfh->cb = NULL;
  }
  TALER_EXCHANGE_management_set_wire_fees_cancel (swfh);
}


struct TALER_EXCHANGE_ManagementSetWireFeeHandle *
TALER_EXCHANGE_management_set_wire_fees (
  struct GNUNET_CURL_Context *ctx,
  const char *exchange_base_url,
  const char *wire_method,
  struct GNUNET_TIME_Timestamp validity_start,
  struct GNUNET_TIME_Timestamp validity_end,
  const struct TALER_WireFeeSet *fees,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementWireEnableCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ManagementSetWireFeeHandle *swfh;
  CURL *eh;
  json_t *body;

  swfh = GNUNET_new (struct TALER_EXCHANGE_ManagementSetWireFeeHandle);
  swfh->cb = cb;
  swfh->cb_cls = cb_cls;
  swfh->ctx = ctx;
  swfh->url = TALER_url_join (exchange_base_url,
                              "management/wire-fee",
                              NULL);
  if (NULL == swfh->url)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not construct request URL.\n");
    GNUNET_free (swfh);
    return NULL;
  }
  body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("wire_method",
                             wire_method),
    GNUNET_JSON_pack_data_auto ("master_sig",
                                master_sig),
    GNUNET_JSON_pack_timestamp ("fee_start",
                                validity_start),
    GNUNET_JSON_pack_timestamp ("fee_end",
                                validity_end),
    TALER_JSON_pack_amount ("closing_fee",
                            &fees->closing),
    TALER_JSON_pack_amount ("wad_fee",
                            &fees->wad),
    TALER_JSON_pack_amount ("wire_fee",
                            &fees->wire));
  eh = TALER_EXCHANGE_curl_easy_get_ (swfh->url);
  GNUNET_assert (NULL != eh);
  if (GNUNET_OK !=
      TALER_curl_easy_post (&swfh->post_ctx,
                            eh,
                            body))
  {
    GNUNET_break (0);
    json_decref (body);
    GNUNET_free (swfh->url);
    GNUNET_free (eh);
    return NULL;
  }
  json_decref (body);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting URL '%s'\n",
              swfh->url);
  swfh->job = GNUNET_CURL_job_add2 (ctx,
                                    eh,
                                    swfh->post_ctx.headers,
                                    &handle_set_wire_fee_finished,
                                    swfh);
  if (NULL == swfh->job)
  {
    TALER_EXCHANGE_management_set_wire_fees_cancel (swfh);
    return NULL;
  }
  return swfh;
}


void
TALER_EXCHANGE_management_set_wire_fees_cancel (
  struct TALER_EXCHANGE_ManagementSetWireFeeHandle *swfh)
{
  if (NULL != swfh->job)
  {
    GNUNET_CURL_job_cancel (swfh->job);
    swfh->job = NULL;
  }
  TALER_curl_easy_post_finished (&swfh->post_ctx);
  GNUNET_free (swfh->url);
  GNUNET_free (swfh);
}
