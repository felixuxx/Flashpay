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
 * @file lib/exchange_api_management_post_keys.c
 * @brief functions to affirm the validity of exchange keys using the master private key
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
 * @brief Handle for a POST /management/keys request.
 */
struct TALER_EXCHANGE_ManagementPostKeysHandle
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
  TALER_EXCHANGE_ManagementPostKeysCallback cb;

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
 * HTTP POST /management/keys request.
 *
 * @param cls the `struct TALER_EXCHANGE_ManagementPostKeysHandle *`
 * @param response_code HTTP response code, 0 on error
 * @param response response body, NULL if not in JSON
 */
static void
handle_post_keys_finished (void *cls,
                           long response_code,
                           const void *response)
{
  struct TALER_EXCHANGE_ManagementPostKeysHandle *ph = cls;
  const json_t *json = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .http_status = (unsigned int) response_code,
    .reply = json
  };

  ph->job = NULL;
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
  case MHD_HTTP_REQUEST_ENTITY_TOO_LARGE:
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange management post keys\n",
                (unsigned int) response_code,
                (int) hr.ec);
    break;
  }
  if (NULL != ph->cb)
  {
    ph->cb (ph->cb_cls,
            &hr);
    ph->cb = NULL;
  }
  TALER_EXCHANGE_post_management_keys_cancel (ph);
}


struct TALER_EXCHANGE_ManagementPostKeysHandle *
TALER_EXCHANGE_post_management_keys (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_EXCHANGE_ManagementPostKeysData *pkd,
  TALER_EXCHANGE_ManagementPostKeysCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ManagementPostKeysHandle *ph;
  CURL *eh;
  json_t *body;
  json_t *denom_sigs;
  json_t *signkey_sigs;

  ph = GNUNET_new (struct TALER_EXCHANGE_ManagementPostKeysHandle);
  ph->cb = cb;
  ph->cb_cls = cb_cls;
  ph->ctx = ctx;
  ph->url = TALER_url_join (url,
                            "management/keys",
                            NULL);
  if (NULL == ph->url)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not construct request URL.\n");
    GNUNET_free (ph);
    return NULL;
  }
  denom_sigs = json_array ();
  GNUNET_assert (NULL != denom_sigs);
  for (unsigned int i = 0; i<pkd->num_denom_sigs; i++)
  {
    const struct TALER_EXCHANGE_DenominationKeySignature *dks
      = &pkd->denom_sigs[i];

    GNUNET_assert (0 ==
                   json_array_append_new (
                     denom_sigs,
                     GNUNET_JSON_PACK (
                       GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                                   &dks->h_denom_pub),
                       GNUNET_JSON_pack_data_auto ("master_sig",
                                                   &dks->master_sig))));
  }
  signkey_sigs = json_array ();
  GNUNET_assert (NULL != signkey_sigs);
  for (unsigned int i = 0; i<pkd->num_sign_sigs; i++)
  {
    const struct TALER_EXCHANGE_SigningKeySignature *sks
      = &pkd->sign_sigs[i];

    GNUNET_assert (0 ==
                   json_array_append_new (
                     signkey_sigs,
                     GNUNET_JSON_PACK (
                       GNUNET_JSON_pack_data_auto ("exchange_pub",
                                                   &sks->exchange_pub),
                       GNUNET_JSON_pack_data_auto ("master_sig",
                                                   &sks->master_sig))));
  }
  body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_array_steal ("denom_sigs",
                                  denom_sigs),
    GNUNET_JSON_pack_array_steal ("signkey_sigs",
                                  signkey_sigs));
  eh = TALER_EXCHANGE_curl_easy_get_ (ph->url);
  GNUNET_assert (NULL != eh);
  if (GNUNET_OK !=
      TALER_curl_easy_post (&ph->post_ctx,
                            eh,
                            body))
  {
    GNUNET_break (0);
    json_decref (body);
    GNUNET_free (ph->url);
    GNUNET_free (eh);
    return NULL;
  }
  json_decref (body);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting URL '%s'\n",
              ph->url);
  ph->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  ph->post_ctx.headers,
                                  &handle_post_keys_finished,
                                  ph);
  if (NULL == ph->job)
  {
    TALER_EXCHANGE_post_management_keys_cancel (ph);
    return NULL;
  }
  return ph;
}


void
TALER_EXCHANGE_post_management_keys_cancel (
  struct TALER_EXCHANGE_ManagementPostKeysHandle *ph)
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
