/*
  This file is part of TALER
  Copyright (C) 2015--2020 Taler Systems SA

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
 * @file bank-lib/bank_api_admin.c
 * @brief Implementation of the /admin/ requests of the bank's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include "bank_api_common.h"
#include <microhttpd.h> /* just for HTTP status codes */
#include "taler_signatures.h"
#include "taler_curl_lib.h"


/**
 * @brief An admin/add-incoming Handle
 */
struct TALER_BANK_AdminAddIncomingHandle
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
  TALER_BANK_AdminAddIncomingCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * Function called when we're done processing the
 * HTTP /admin/add-incoming request.
 *
 * @param cls the `struct TALER_BANK_AdminAddIncomingHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_admin_add_incoming_finished (void *cls,
                                    long response_code,
                                    const void *response)
{
  struct TALER_BANK_AdminAddIncomingHandle *aai = cls;
  uint64_t row_id = UINT64_MAX;
  struct GNUNET_TIME_Absolute timestamp;
  enum TALER_ErrorCode ec;
  const json_t *j = response;

  aai->job = NULL;
  timestamp = GNUNET_TIME_UNIT_FOREVER_ABS;
  switch (response_code)
  {
  case 0:
    ec = TALER_EC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_uint64 ("row_id",
                                 &row_id),
        GNUNET_JSON_spec_absolute_time ("timestamp",
                                        &timestamp),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        response_code = 0;
        ec = TALER_EC_INVALID_RESPONSE;
        break;
      }
      ec = TALER_EC_NONE;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the bank is buggy
       (or API version conflict); just pass JSON reply to the application */
    GNUNET_break_op (0);
    ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Access denied */
    ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, bank says the password is invalid; we should
       pass the JSON reply to the application */
    ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, maybe account really does not exist.
       We should pass the JSON reply to the application */
    ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    ec = TALER_JSON_get_error_code (j);
    break;
  default:
    /* unexpected response code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                (unsigned int) response_code);
    GNUNET_break (0);
    ec = TALER_JSON_get_error_code (j);
    response_code = 0;
    break;
  }
  aai->cb (aai->cb_cls,
           response_code,
           ec,
           row_id,
           timestamp,
           j);
  TALER_BANK_admin_add_incoming_cancel (aai);
}


/**
 * Perform a wire transfer from some account to the exchange to fill a
 * reserve.  Note that this API is usually only used for testing (with
 * fakebank and our Python bank) and thus may not be accessible in a
 * production setting.
 *
 * @param ctx curl context for the event loop
 * @param auth authentication data to send to the bank
 * @param reserve_pub wire transfer subject for the transfer
 * @param amount amount that was is to be deposited
 * @param debit_account account to deposit from (payto URI, but used as 'payfrom')
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return NULL
 *         if the inputs are invalid (i.e. invalid amount) or internal errors.
 *         In this case, the callback is not called.
 */
struct TALER_BANK_AdminAddIncomingHandle *
TALER_BANK_admin_add_incoming (struct GNUNET_CURL_Context *ctx,
                               const struct TALER_BANK_AuthenticationData *auth,
                               const struct
                               TALER_ReservePublicKeyP *reserve_pub,
                               const struct TALER_Amount *amount,
                               const char *debit_account,
                               TALER_BANK_AdminAddIncomingCallback res_cb,
                               void *res_cb_cls)
{
  struct TALER_BANK_AdminAddIncomingHandle *aai;
  json_t *admin_obj;
  CURL *eh;

  admin_obj = json_pack ("{s:o, s:o, s:s}",
                         "reserve_pub",
                         GNUNET_JSON_from_data_auto (reserve_pub),
                         "amount",
                         TALER_JSON_from_amount (amount),
                         "debit_account",
                         debit_account);
  if (NULL == admin_obj)
  {
    GNUNET_break (0);
    return NULL;
  }
  aai = GNUNET_new (struct TALER_BANK_AdminAddIncomingHandle);
  aai->cb = res_cb;
  aai->cb_cls = res_cb_cls;
  aai->request_url = TALER_url_join (auth->wire_gateway_url,
                                     "admin/add-incoming",
                                     NULL);
  if (NULL == aai->request_url)
  {
    GNUNET_free (aai);
    json_decref (admin_obj);
    GNUNET_break (0);
    return NULL;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Requesting administrative transaction at `%s' for reserve %s\n",
              aai->request_url,
              TALER_B2S (reserve_pub));
  aai->post_ctx.headers = curl_slist_append
                            (aai->post_ctx.headers,
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
    TALER_BANK_admin_add_incoming_cancel (aai);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (admin_obj);
    return NULL;
  }
  json_decref (admin_obj);

  aai->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   aai->post_ctx.headers,
                                   &handle_admin_add_incoming_finished,
                                   aai);
  return aai;
}


/**
 * Cancel an add incoming.  This function cannot be used on a request
 * handle if a response is already served for it.
 *
 * @param aai the admin add incoming request handle
 */
void
TALER_BANK_admin_add_incoming_cancel (struct
                                      TALER_BANK_AdminAddIncomingHandle *aai)
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


/* end of bank_api_admin.c */
