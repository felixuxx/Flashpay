/*
  This file is part of TALER
  Copyright (C) 2015--2024 Taler Systems SA

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
 * @file bank-lib/bank_api_account_token.c
 * @brief Implementation of the /account/$ACC/token requests of the bank's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include "bank_api_common.h"
#include <microhttpd.h> /* just for HTTP status codes */
#include "taler_signatures.h"
#include "taler_curl_lib.h"


struct TALER_BANK_AccountTokenHandle
{

  /**
   * The url for this request.
   */
  char *request_url;

  /**
   * POST context.
   */
  struct TALER_CURL_PostContext post_ctx;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_BANK_AccountTokenCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * Function called when we're done processing the
 * HTTP /account/$ACC/token request.
 *
 * @param cls the `struct TALER_BANK_AccountTokenHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_account_token_finished (void *cls,
                               long response_code,
                               const void *response)
{
  struct TALER_BANK_AccountTokenHandle *aai = cls;
  const json_t *j = response;
  struct TALER_BANK_AccountTokenResponse ir = {
    .http_status = response_code,
    .response = response
  };

  aai->job = NULL;
  switch (response_code)
  {
  case 0:
    ir.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_string ("access_token",
                                 &ir.details.ok.access_token),
        GNUNET_JSON_spec_timestamp ("expiration",
                                    &ir.details.ok.expiration),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        ir.http_status = 0;
        ir.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
        break;
      }
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the bank is buggy
       (or API version conflict); just pass JSON reply to the application */
    GNUNET_break_op (0);
    ir.ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Access denied */
    ir.ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, bank says the password is invalid; we should
       pass the JSON reply to the application */
    ir.ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, maybe account really does not exist.
       We should pass the JSON reply to the application */
    ir.ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    ir.ec = TALER_JSON_get_error_code (j);
    break;
  default:
    /* unexpected response code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                (unsigned int) response_code);
    GNUNET_break (0);
    ir.ec = TALER_JSON_get_error_code (j);
    break;
  }
  aai->cb (aai->cb_cls,
           &ir);
  TALER_BANK_account_token_cancel (aai);
}


/**
 * Convert @a scope to string.
 *
 * @param scope a scope
 * @return string encoding of the scope
 */
static const char *
scope_to_string (enum TALER_BANK_TokenScope scope)
{
  switch (scope)
  {
  case TALER_BANK_TOKEN_SCOPE_READONLY:
    return "readonly";
  case TALER_BANK_TOKEN_SCOPE_READWRITE:
    return "readwrite";
  case TALER_BANK_TOKEN_SCOPE_REVENUE:
    return "revenue";
  case TALER_BANK_TOKEN_SCOPE_WIREGATEWAY:
    return "wiregateway";
  }
  GNUNET_break (0);
  return NULL;
}


struct TALER_BANK_AccountTokenHandle *
TALER_BANK_account_token (
  struct GNUNET_CURL_Context *ctx,
  const struct TALER_BANK_AuthenticationData *auth,
  const char *account_name,
  enum TALER_BANK_TokenScope scope,
  bool refreshable,
  const char *description,
  struct GNUNET_TIME_Relative duration,
  TALER_BANK_AccountTokenCallback res_cb,
  void *res_cb_cls)
{
  struct TALER_BANK_AccountTokenHandle *ath;
  json_t *token_req;
  CURL *eh;

  token_req = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("scope",
                             scope_to_string (scope)),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_string ("description",
                               description)),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_time_rel ("duration",
                                 duration)),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_bool ("refreshable",
                             refreshable)));
  if (NULL == token_req)
  {
    GNUNET_break (0);
    return NULL;
  }
  ath = GNUNET_new (struct TALER_BANK_AccountTokenHandle);
  ath->cb = res_cb;
  ath->cb_cls = res_cb_cls;
  {
    char *path;

    GNUNET_asprintf (&path,
                     "accounts/%s/token",
                     account_name);
    ath->request_url = TALER_url_join (auth->wire_gateway_url,
                                       path,
                                       NULL);
    GNUNET_free (path);
  }
  if (NULL == ath->request_url)
  {
    GNUNET_free (ath);
    json_decref (token_req);
    return NULL;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Requesting access token at `%s'\n",
              ath->request_url);
  ath->post_ctx.headers
    = curl_slist_append (
        ath->post_ctx.headers,
        "Content-Type: application/json");
  eh = curl_easy_init ();
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_BANK_setup_auth_ (eh,
                                auth)) ||
       (CURLE_OK !=
        curl_easy_setopt (eh,
                          CURLOPT_URL,
                          ath->request_url)) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&ath->post_ctx,
                              eh,
                              token_req)) )
  {
    GNUNET_break (0);
    TALER_BANK_account_token_cancel (ath);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (token_req);
    return NULL;
  }
  json_decref (token_req);
  ath->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   ath->post_ctx.headers,
                                   &handle_account_token_finished,
                                   ath);
  GNUNET_assert (NULL != ath->job);
  return ath;
}


void
TALER_BANK_account_token_cancel (
  struct TALER_BANK_AccountTokenHandle *ath)
{
  if (NULL != ath->job)
  {
    GNUNET_CURL_job_cancel (ath->job);
    ath->job = NULL;
  }
  TALER_curl_easy_post_finished (&ath->post_ctx);
  GNUNET_free (ath->request_url);
  GNUNET_free (ath);
}


/* end of bank_api_account_token.c */
