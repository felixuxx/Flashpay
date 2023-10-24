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
 * @file lib/exchange_api_management_add_partner.c
 * @brief functions to add an partner by an AML officer
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


struct TALER_EXCHANGE_ManagementAddPartner
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
  TALER_EXCHANGE_ManagementAddPartnerCallback cb;

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
 * HTTP POST /management/partners request.
 *
 * @param cls the `struct TALER_EXCHANGE_ManagementAddPartner *`
 * @param response_code HTTP response code, 0 on error
 * @param response response body, NULL if not in JSON
 */
static void
handle_add_partner_finished (void *cls,
                             long response_code,
                             const void *response)
{
  struct TALER_EXCHANGE_ManagementAddPartner *wh = cls;
  const json_t *json = response;
  struct TALER_EXCHANGE_ManagementAddPartnerResponse apr = {
    .hr.http_status = (unsigned int) response_code,
    .hr.reply = json
  };

  wh->job = NULL;
  switch (response_code)
  {
  case 0:
    /* no reply */
    apr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    apr.hr.hint = "server offline?";
    break;
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_FORBIDDEN:
    apr.hr.ec = TALER_JSON_get_error_code (json);
    apr.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  case MHD_HTTP_CONFLICT:
    apr.hr.ec = TALER_JSON_get_error_code (json);
    apr.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    apr.hr.ec = TALER_JSON_get_error_code (json);
    apr.hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for adding exchange partner\n",
                (unsigned int) response_code,
                (int) apr.hr.ec);
    break;
  }
  if (NULL != wh->cb)
  {
    wh->cb (wh->cb_cls,
            &apr);
    wh->cb = NULL;
  }
  TALER_EXCHANGE_management_add_partner_cancel (wh);
}


struct TALER_EXCHANGE_ManagementAddPartner *
TALER_EXCHANGE_management_add_partner (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_MasterPublicKeyP *partner_pub,
  struct GNUNET_TIME_Timestamp start_date,
  struct GNUNET_TIME_Timestamp end_date,
  struct GNUNET_TIME_Relative wad_frequency,
  const struct TALER_Amount *wad_fee,
  const char *partner_base_url,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementAddPartnerCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ManagementAddPartner *wh;
  CURL *eh;
  json_t *body;

  wh = GNUNET_new (struct TALER_EXCHANGE_ManagementAddPartner);
  wh->cb = cb;
  wh->cb_cls = cb_cls;
  wh->ctx = ctx;
  wh->url = TALER_url_join (url,
                            "management/partners",
                            NULL);
  if (NULL == wh->url)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not construct request URL.\n");
    GNUNET_free (wh);
    return NULL;
  }
  body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("partner_base_url",
                             partner_base_url),
    GNUNET_JSON_pack_timestamp ("start_date",
                                start_date),
    GNUNET_JSON_pack_timestamp ("end_date",
                                end_date),
    GNUNET_JSON_pack_time_rel ("wad_frequency",
                               wad_frequency),
    GNUNET_JSON_pack_data_auto ("partner_pub",
                                &partner_pub),
    GNUNET_JSON_pack_data_auto ("master_sig",
                                &master_sig),
    TALER_JSON_pack_amount ("wad_fee",
                            wad_fee)
    );
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
                                  &handle_add_partner_finished,
                                  wh);
  if (NULL == wh->job)
  {
    TALER_EXCHANGE_management_add_partner_cancel (wh);
    return NULL;
  }
  return wh;
}


void
TALER_EXCHANGE_management_add_partner_cancel (
  struct TALER_EXCHANGE_ManagementAddPartner *wh)
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
