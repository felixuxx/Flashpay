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
 * @file lib/exchange_api_add_aml_decision.c
 * @brief functions to add an AML decision by an AML officer
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


struct TALER_EXCHANGE_AddAmlDecision
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
  TALER_EXCHANGE_AddAmlDecisionCallback cb;

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
 * HTTP POST /aml/$OFFICER_PUB/decision request.
 *
 * @param cls the `struct TALER_EXCHANGE_AddAmlDecision *`
 * @param response_code HTTP response code, 0 on error
 * @param response response body, NULL if not in JSON
 */
static void
handle_add_aml_decision_finished (void *cls,
                                  long response_code,
                                  const void *response)
{
  struct TALER_EXCHANGE_AddAmlDecision *wh = cls;
  const json_t *json = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .http_status = (unsigned int) response_code,
    .reply = json
  };

  wh->job = NULL;
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
  case MHD_HTTP_CONFLICT:
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange AML decision\n",
                (unsigned int) response_code,
                (int) hr.ec);
    break;
  }
  if (NULL != wh->cb)
  {
    wh->cb (wh->cb_cls,
            &hr);
    wh->cb = NULL;
  }
  TALER_EXCHANGE_add_aml_decision_cancel (wh);
}


struct TALER_EXCHANGE_AddAmlDecision *
TALER_EXCHANGE_add_aml_decision (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const char *justification,
  struct GNUNET_TIME_Timestamp decision_time,
  const struct TALER_Amount *new_threshold,
  const struct TALER_PaytoHashP *h_payto,
  enum TALER_AmlDecisionState new_state,
  const struct TALER_AmlOfficerPrivateKeyP *officer_priv,
  TALER_EXCHANGE_AddAmlDecisionCallback cb,
  void *cb_cls)
{
  struct TALER_AmlOfficerPublicKeyP officer_pub;
  struct TALER_AmlOfficerSignatureP officer_sig;
  struct TALER_EXCHANGE_AddAmlDecision *wh;
  CURL *eh;
  json_t *body;

  GNUNET_CRYPTO_eddsa_key_get_public (&officer_priv->eddsa_priv,
                                      &officer_pub.eddsa_pub);
  TALER_officer_aml_decision_sign (justification,
                                   decision_time,
                                   new_threshold,
                                   h_payto,
                                   new_state,
                                   officer_priv,
                                   &officer_sig);
  wh = GNUNET_new (struct TALER_EXCHANGE_AddAmlDecision);
  wh->cb = cb;
  wh->cb_cls = cb_cls;
  wh->ctx = ctx;
  {
    char *path;
    char opus[sizeof (officer_pub) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &officer_pub,
      sizeof (officer_pub),
      opus,
      sizeof (opus));
    *end = '\0';
    GNUNET_asprintf (&path,
                     "aml/%s/decision",
                     opus);
    wh->url = TALER_url_join (url,
                              path,
                              NULL);
    GNUNET_free (path);
  }
  if (NULL == wh->url)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not construct request URL.\n");
    GNUNET_free (wh);
    return NULL;
  }
  body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("justification",
                             justification),
    GNUNET_JSON_pack_data_auto ("officer_sig",
                                &officer_sig),
    GNUNET_JSON_pack_data_auto ("h_payto",
                                h_payto),
    GNUNET_JSON_pack_uint64 ("state",
                             (uint32_t) new_state),
    TALER_JSON_pack_amount ("new_threshold",
                            new_threshold),
    GNUNET_JSON_pack_timestamp ("decision_time",
                                decision_time));
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
                                  &handle_add_aml_decision_finished,
                                  wh);
  if (NULL == wh->job)
  {
    TALER_EXCHANGE_add_aml_decision_cancel (wh);
    return NULL;
  }
  return wh;
}


void
TALER_EXCHANGE_add_aml_decision_cancel (
  struct TALER_EXCHANGE_AddAmlDecision *wh)
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
