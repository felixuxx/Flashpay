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
 * @file bank-lib/bank_api_admin_add_kycauth.c
 * @brief Implementation of the /admin/add-kycauth requests of the bank's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include "bank_api_common.h"
#include <microhttpd.h> /* just for HTTP status codes */
#include "taler_signatures.h"
#include "taler_curl_lib.h"


/**
 * @brief An /admin/add-kycauth Handle
 */
struct TALER_BANK_AdminAddKycauthHandle
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
  TALER_BANK_AdminAddKycauthCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * Function called when we're done processing the
 * HTTP /admin/add-kycauth request.
 *
 * @param cls the `struct TALER_BANK_AdminAddKycauthHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_admin_add_kycauth_finished (void *cls,
                                   long response_code,
                                   const void *response)
{
  struct TALER_BANK_AdminAddKycauthHandle *aai = cls;
  const json_t *j = response;
  struct TALER_BANK_AdminAddKycauthResponse ir = {
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
        GNUNET_JSON_spec_uint64 ("row_id",
                                 &ir.details.ok.serial_id),
        GNUNET_JSON_spec_timestamp ("timestamp",
                                    &ir.details.ok.timestamp),
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
  TALER_BANK_admin_add_kycauth_cancel (aai);
}


struct TALER_BANK_AdminAddKycauthHandle *
TALER_BANK_admin_add_kycauth (
  struct GNUNET_CURL_Context *ctx,
  const struct TALER_BANK_AuthenticationData *auth,
  const union TALER_AccountPublicKeyP *account_pub,
  const struct TALER_Amount *amount,
  const char *debit_account,
  TALER_BANK_AdminAddKycauthCallback res_cb,
  void *res_cb_cls)
{
  struct TALER_BANK_AdminAddKycauthHandle *aai;
  json_t *admin_obj;
  CURL *eh;

  if (NULL == debit_account)
  {
    GNUNET_break (0);
    return NULL;
  }
  if (NULL == account_pub)
  {
    GNUNET_break (0);
    return NULL;
  }
  if (NULL == amount)
  {
    GNUNET_break (0);
    return NULL;
  }
  admin_obj = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_data_auto ("account_pub",
                                account_pub),
    TALER_JSON_pack_amount ("amount",
                            amount),
    GNUNET_JSON_pack_string ("debit_account",
                             debit_account));
  if (NULL == admin_obj)
  {
    GNUNET_break (0);
    return NULL;
  }
  aai = GNUNET_new (struct TALER_BANK_AdminAddKycauthHandle);
  aai->cb = res_cb;
  aai->cb_cls = res_cb_cls;
  aai->request_url = TALER_url_join (auth->wire_gateway_url,
                                     "admin/add-kycauth",
                                     NULL);
  if (NULL == aai->request_url)
  {
    GNUNET_free (aai);
    json_decref (admin_obj);
    return NULL;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Requesting administrative transaction at `%s' for account %s\n",
              aai->request_url,
              TALER_B2S (account_pub));
  aai->post_ctx.headers
    = curl_slist_append (
        aai->post_ctx.headers,
        "Content-Type: application/json");

  eh = curl_easy_init ();
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_BANK_setup_auth_ (eh,
                                auth)) ||
       (CURLE_OK !=
        curl_easy_setopt (eh,
                          CURLOPT_URL,
                          aai->request_url)) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&aai->post_ctx,
                              eh,
                              admin_obj)) )
  {
    GNUNET_break (0);
    TALER_BANK_admin_add_kycauth_cancel (aai);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (admin_obj);
    return NULL;
  }
  json_decref (admin_obj);

  aai->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   aai->post_ctx.headers,
                                   &handle_admin_add_kycauth_finished,
                                   aai);
  return aai;
}


void
TALER_BANK_admin_add_kycauth_cancel (
  struct TALER_BANK_AdminAddKycauthHandle *aai)
{
  if (NULL != aai->job)
  {
    GNUNET_CURL_job_cancel (aai->job);
    aai->job = NULL;
  }
  TALER_curl_easy_post_finished (&aai->post_ctx);
  GNUNET_free (aai->request_url);
  GNUNET_free (aai);
}


/* end of bank_api_admin_add_kycauth.c */
