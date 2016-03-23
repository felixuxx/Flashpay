/*
  This file is part of TALER
  Copyright (C) 2015, 2016 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file bank-lib/bank_api_admin.c
 * @brief Implementation of the /admin/ requests of the bank's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include "taler_bank_service.h"
#include "taler_json_lib.h"
#include "bank_api_context.h"
#include "taler_signatures.h"


/**
 * @brief An admin/add/incoming Handle
 */
struct TALER_BANK_AdminAddIncomingHandle
{

  /**
   * The connection to bank this request handle will use
   */
  struct TALER_BANK_Context *bank;

  /**
   * The url for this request.
   */
  char *url;

  /**
   * JSON encoding of the request to POST.
   */
  char *json_enc;

  /**
   * Handle for the request.
   */
  struct BAC_Job *job;

  /**
   * HTTP headers for the request.
   */
  struct curl_slist *headers;

  /**
   * Function to call with the result.
   */
  TALER_BANK_AdminAddIncomingResultCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Download buffer
   */
  struct BAC_DownloadBuffer db;

};


/**
 * Function called when we're done processing the
 * HTTP /admin/add/incoming request.
 *
 * @param cls the `struct TALER_BANK_AdminAddIncomingHandle`
 * @param eh the curl request handle
 */
static void
handle_admin_add_incoming_finished (void *cls,
                                    CURL *eh)
{
  struct TALER_BANK_AdminAddIncomingHandle *aai = cls;
  long response_code;
  json_t *json;

  aai->job = NULL;
  json = BAC_download_get_result (&aai->db,
                                  eh,
                                  &response_code);
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the bank is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Access denied */
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, bank says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                response_code);
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  aai->cb (aai->cb_cls,
           response_code,
           json);
  json_decref (json);
  TALER_BANK_admin_add_incoming_cancel (aai);
}


/**
 * Notify the bank that we have received an incoming transaction
 * which fills a reserve.  Note that this API is an administrative
 * API and thus not accessible to typical bank clients, but only
 * to the operators of the bank.
 *
 * @param bank the bank handle; the bank must be ready to operate
 * @param reserve_pub public key of the reserve
 * @param amount amount that was deposited
 * @param execution_date when did we receive the amount
 * @param debit_account_no account number to withdraw from (53 bits at most)
 * @param credit_account_no account number to deposit into (53 bits at most)
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return NULL
 *         if the inputs are invalid (i.e. invalid amount).
 *         In this case, the callback is not called.
 */
struct TALER_BANK_AdminAddIncomingHandle *
TALER_BANK_admin_add_incoming (struct TALER_BANK_Context *bank,
                               const struct TALER_WireTransferIdentifierRawP *wtid,
                               const struct TALER_Amount *amount,
                               uint64_t debit_account_no,
                               uint64_t credit_account_no,
                               TALER_BANK_AdminAddIncomingResultCallback res_cb,
                               void *res_cb_cls)
{
  struct TALER_BANK_AdminAddIncomingHandle *aai;
  json_t *admin_obj;
  CURL *eh;

  admin_obj = json_pack ("{s:o, s:o,"
                         " s:I, s:I}",
                         "wid", GNUNET_JSON_from_data (wtid,
                                                       sizeof (*wtid)),
                         "amount", TALER_JSON_from_amount (amount),
                         "debit_account", (json_int_t) debit_account_no,
                         "credit_account", (json_int_t) credit_account_no);
  aai = GNUNET_new (struct TALER_BANK_AdminAddIncomingHandle);
  aai->bank = bank;
  aai->cb = res_cb;
  aai->cb_cls = res_cb_cls;
  aai->url = BAC_path_to_url (bank, "/admin/add/incoming");

  eh = curl_easy_init ();
  GNUNET_assert (NULL != (aai->json_enc =
                          json_dumps (admin_obj,
                                      JSON_COMPACT)));
  json_decref (admin_obj);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   aai->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDS,
                                   aai->json_enc));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDSIZE,
                                   strlen (aai->json_enc)));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEFUNCTION,
                                   &BAC_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEDATA,
                                   &aai->db));
  aai->job = BAC_job_add (bank,
                          eh,
                          GNUNET_YES,
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
TALER_BANK_admin_add_incoming_cancel (struct TALER_BANK_AdminAddIncomingHandle *aai)
{
  if (NULL != aai->job)
  {
    BAC_job_cancel (aai->job);
    aai->job = NULL;
  }
  curl_slist_free_all (aai->headers);
  GNUNET_free_non_null (aai->db.buf);
  GNUNET_free (aai->url);
  GNUNET_free (aai->json_enc);
  GNUNET_free (aai);
}


/* end of bank_api_admin.c */
