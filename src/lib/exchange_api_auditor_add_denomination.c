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
 * @file lib/exchange_api_auditor_add_denomination.c
 * @brief functions for the auditor to add its signature for denomination at the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_signatures.h"
#include "taler_curl_lib.h"
#include "taler_json_lib.h"


struct TALER_EXCHANGE_AuditorAddDenominationHandle
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
  TALER_EXCHANGE_AuditorAddDenominationCallback cb;

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
 * HTTP POST /auditor/$AUDITOR_PUB/$H_DENOM_PUB request.
 *
 * @param cls the `struct TALER_EXCHANGE_AuditorAddDenominationHandle *`
 * @param response_code HTTP response code, 0 on error
 * @param response response body, NULL if not in JSON
 */
static void
handle_auditor_add_denomination_finished (void *cls,
                                          long response_code,
                                          const void *response)
{
  struct TALER_EXCHANGE_AuditorAddDenominationHandle *ah = cls;
  const json_t *json = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .http_status = (unsigned int) response_code,
    .reply = json
  };

  ah->job = NULL;
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
  case MHD_HTTP_GONE:
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
                "Unexpected response code %u/%d\n",
                (unsigned int) response_code,
                (int) hr.ec);
    break;
  }
  if (NULL != ah->cb)
  {
    ah->cb (ah->cb_cls,
            &hr);
    ah->cb = NULL;
  }
  TALER_EXCHANGE_add_auditor_denomination_cancel (ah);
}


struct TALER_EXCHANGE_AuditorAddDenominationHandle *
TALER_EXCHANGE_add_auditor_denomination (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct GNUNET_HashCode *h_denom_pub,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const struct TALER_AuditorSignatureP *auditor_sig,
  TALER_EXCHANGE_AuditorAddDenominationCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_AuditorAddDenominationHandle *ah;
  CURL *eh;
  json_t *body;

  ah = GNUNET_new (struct TALER_EXCHANGE_AuditorAddDenominationHandle);
  ah->cb = cb;
  ah->cb_cls = cb_cls;
  ah->ctx = ctx;
  {
    char apub_str[sizeof (*auditor_pub) * 2];
    char denom_str[sizeof (*h_denom_pub) * 2];
    char arg_str[sizeof (apub_str) + sizeof (denom_str) + 32];
    char *end;

    end = GNUNET_STRINGS_data_to_string (auditor_pub,
                                         sizeof (*auditor_pub),
                                         apub_str,
                                         sizeof (apub_str));
    *end = '\0';
    end = GNUNET_STRINGS_data_to_string (h_denom_pub,
                                         sizeof (*h_denom_pub),
                                         denom_str,
                                         sizeof (denom_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "auditors/%s/%s",
                     apub_str,
                     denom_str);
    ah->url = TALER_url_join (url,
                              arg_str,
                              NULL);
  }
  if (NULL == ah->url)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not construct request URL.\n");
    GNUNET_free (ah);
    return NULL;
  }
  body = json_pack ("{s:o}",
                    "auditor_sig",
                    GNUNET_JSON_from_data_auto (auditor_sig));
  if (NULL == body)
  {
    GNUNET_break (0);
    GNUNET_free (ah->url);
    GNUNET_free (ah);
    return NULL;
  }
  eh = curl_easy_init ();
  if (GNUNET_OK !=
      TALER_curl_easy_post (&ah->post_ctx,
                            eh,
                            body))
  {
    GNUNET_break (0);
    json_decref (body);
    GNUNET_free (ah->url);
    GNUNET_free (eh);
    return NULL;
  }
  json_decref (body);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting URL '%s'\n",
              ah->url);
  GNUNET_assert (CURLE_OK == curl_easy_setopt (eh,
                                               CURLOPT_URL,
                                               ah->url));
  ah->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  ah->post_ctx.headers,
                                  &handle_auditor_add_denomination_finished,
                                  ah);
  if (NULL == ah->job)
  {
    TALER_EXCHANGE_add_auditor_denomination_cancel (ah);
    return NULL;
  }
  return ah;
}


void
TALER_EXCHANGE_add_auditor_denomination_cancel (
  struct TALER_EXCHANGE_AuditorAddDenominationHandle *ah)
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
