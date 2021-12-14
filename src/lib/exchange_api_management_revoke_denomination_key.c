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
 * @file lib/exchange_api_management_revoke_denomination_key.c
 * @brief functions to revoke an exchange denomination key
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
 * @brief Handle for a POST /management/denominations/$H_DENOM_PUB/revoke request.
 */
struct TALER_EXCHANGE_ManagementRevokeDenominationKeyHandle
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
  TALER_EXCHANGE_ManagementRevokeDenominationKeyCallback cb;

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
 * HTTP /management/denominations/$H_DENOM_PUB/revoke request.
 *
 * @param cls the `struct TALER_EXCHANGE_ManagementRevokeDenominationKeyHandle *`
 * @param response_code HTTP response code, 0 on error
 * @param response response body, NULL if not in JSON
 */
static void
handle_revoke_denomination_finished (void *cls,
                                     long response_code,
                                     const void *response)
{
  struct TALER_EXCHANGE_ManagementRevokeDenominationKeyHandle *rh = cls;
  const json_t *json = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .http_status = (unsigned int) response_code,
    .reply = json
  };

  rh->job = NULL;
  switch (response_code)
  {
  case 0:
    /* no reply */
    hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    hr.hint = "server offline?";
    break;
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_FORBIDDEN:
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange management revoke denomination\n",
                (unsigned int) response_code,
                (int) hr.ec);
    break;
  }
  if (NULL != rh->cb)
  {
    rh->cb (rh->cb_cls,
            &hr);
    rh->cb = NULL;
  }
  TALER_EXCHANGE_management_revoke_denomination_key_cancel (rh);
}


struct TALER_EXCHANGE_ManagementRevokeDenominationKeyHandle *
TALER_EXCHANGE_management_revoke_denomination_key (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_DenominationHash *h_denom_pub,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementRevokeDenominationKeyCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ManagementRevokeDenominationKeyHandle *rh;
  CURL *eh;
  json_t *body;

  rh = GNUNET_new (struct TALER_EXCHANGE_ManagementRevokeDenominationKeyHandle);
  rh->cb = cb;
  rh->cb_cls = cb_cls;
  rh->ctx = ctx;
  {
    char epub_str[sizeof (*h_denom_pub) * 2];
    char arg_str[sizeof (epub_str) + 64];
    char *end;

    end = GNUNET_STRINGS_data_to_string (h_denom_pub,
                                         sizeof (*h_denom_pub),
                                         epub_str,
                                         sizeof (epub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "management/denominations/%s/revoke",
                     epub_str);
    rh->url = TALER_url_join (url,
                              arg_str,
                              NULL);
  }
  if (NULL == rh->url)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not construct request URL.\n");
    GNUNET_free (rh);
    return NULL;
  }
  body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_data_auto ("master_sig",
                                master_sig));
  if (NULL == body)
  {
    GNUNET_break (0);
    GNUNET_free (rh->url);
    GNUNET_free (rh);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (rh->url);
  if (GNUNET_OK !=
      TALER_curl_easy_post (&rh->post_ctx,
                            eh,
                            body))
  {
    GNUNET_break (0);
    json_decref (body);
    GNUNET_free (rh->url);
    GNUNET_free (eh);
    return NULL;
  }
  json_decref (body);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting URL '%s'\n",
              rh->url);
  rh->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  rh->post_ctx.headers,
                                  &handle_revoke_denomination_finished,
                                  rh);
  if (NULL == rh->job)
  {
    TALER_EXCHANGE_management_revoke_denomination_key_cancel (rh);
    return NULL;
  }
  return rh;
}


void
TALER_EXCHANGE_management_revoke_denomination_key_cancel (
  struct TALER_EXCHANGE_ManagementRevokeDenominationKeyHandle *rh)
{
  if (NULL != rh->job)
  {
    GNUNET_CURL_job_cancel (rh->job);
    rh->job = NULL;
  }
  TALER_curl_easy_post_finished (&rh->post_ctx);
  GNUNET_free (rh->url);
  GNUNET_free (rh);
}
