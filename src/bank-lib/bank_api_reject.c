/*
  This file is part of TALER
  Copyright (C) 2015, 2016, 2017 Taler Systems SA

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
 * @file bank-lib/bank_api_reject.c
 * @brief Implementation of the /reject request of the bank's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include "bank_api_common.h"
#include <microhttpd.h> /* just for HTTP status codes */
#include "taler_signatures.h"


/**
 * @brief A /reject Handle
 */
struct TALER_BANK_RejectHandle
{

  /**
   * The url for this request.
   */
  char *request_url;

  /**
   * JSON encoding of the request to POST.
   */
  char *json_enc;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * HTTP authentication-related headers for the request.
   */
  struct curl_slist *authh;

  /**
   * Function to call with the result.
   */
  TALER_BANK_RejectResultCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * Function called when we're done processing the
 * HTTP /reject request.
 *
 * @param cls the `struct TALER_BANK_RejectHandle`
 * @param response_code HTTP response code, 0 on error
 * @param json parsed JSON result, NULL on error
 */
static void
handle_reject_finished (void *cls,
                        long response_code,
                        const json_t *json)
{
  struct TALER_BANK_RejectHandle *rh = cls;
  enum TALER_ErrorCode ec;

  rh->job = NULL;
  switch (response_code)
  {
  case 0:
    ec = TALER_EC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    GNUNET_break_op (0);
    response_code = 0;
    ec = TALER_EC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_NO_CONTENT:
    ec = TALER_EC_NONE;
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the bank is buggy
       (or API version conflict); just pass JSON reply to the application */
    ec = TALER_BANK_parse_ec_ (json);
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Access denied */
    ec = TALER_BANK_parse_ec_ (json);
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, bank says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    ec = TALER_BANK_parse_ec_ (json);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    ec = TALER_BANK_parse_ec_ (json);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    ec = TALER_BANK_parse_ec_ (json);
    break;
  default:
    /* unexpected response code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                (unsigned int) response_code);
    GNUNET_break (0);
    ec = TALER_BANK_parse_ec_ (json);
    response_code = 0;
    break;
  }
  rh->cb (rh->cb_cls,
          response_code,
          ec);
  TALER_BANK_reject_cancel (rh);
}


/**
 * Request rejection of a wire transfer, marking it as cancelled and voiding
 * its effects.
 *
 * @param ctx curl context for the event loop
 * @param bank_base_url URL of the bank (used to execute this request)
 * @param auth authentication data to use
 * @param account_number which account number should we query
 * @param rowid transfer to reject
 * @param rcb the callback to call with the operation result
 * @param rcb_cls closure for @a rcb
 * @return NULL
 *         if the inputs are invalid.
 *         In this case, the callback is not called.
 */
struct TALER_BANK_RejectHandle *
TALER_BANK_reject (struct GNUNET_CURL_Context *ctx,
                   const char *bank_base_url,
                   const struct TALER_BANK_AuthenticationData *auth,
                   uint64_t account_number,
                   uint64_t rowid,
                   TALER_BANK_RejectResultCallback rcb,
                   void *rcb_cls)
{
  struct TALER_BANK_RejectHandle *rh;
  json_t *reject_obj;
  CURL *eh;

  reject_obj = json_pack ("{s:{s:s}, s:I, s:I}",
                          "auth", "type", "basic",
                          "row_id", (json_int_t) rowid,
                          "account_number", (json_int_t) account_number);
  if (NULL == reject_obj)
  {
    GNUNET_break (0);
    return NULL;
  }
  rh = GNUNET_new (struct TALER_BANK_RejectHandle);
  rh->cb = rcb;
  rh->cb_cls = rcb_cls;
  rh->request_url = TALER_BANK_path_to_url_ (bank_base_url,
                                             "/reject");
  rh->authh = TALER_BANK_make_auth_header_ (auth);
  /* Append content type header here, can't do it in GNUNET_CURL_job_add
     as that would override the CURLOPT_HTTPHEADER instead of appending. */
  {
    struct curl_slist *ext;

    ext = curl_slist_append (rh->authh,
                             "Content-Type: application/json");
    if (NULL == ext)
      GNUNET_break (0);
    else
      rh->authh = ext;
  }
  eh = curl_easy_init ();
  GNUNET_assert (NULL != (rh->json_enc =
                          json_dumps (reject_obj,
                                      JSON_COMPACT)));
  json_decref (reject_obj);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_HTTPHEADER,
                                   rh->authh));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   rh->request_url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDS,
                                   rh->json_enc));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDSIZE,
                                   strlen (rh->json_enc)));
  rh->job = GNUNET_CURL_job_add (ctx,
                                 eh,
                                 GNUNET_NO,
                                 &handle_reject_finished,
                                 rh);
  return rh;
}


/**
 * Cancel an reject request.  This function cannot be used on a request
 * handle if the response was is already served for it.
 *
 * @param rh the reject request handle
 */
void
TALER_BANK_reject_cancel (struct TALER_BANK_RejectHandle *rh)
{
  if (NULL != rh->job)
  {
    GNUNET_CURL_job_cancel (rh->job);
    rh->job = NULL;
  }
  curl_slist_free_all (rh->authh);
  GNUNET_free (rh->request_url);
  GNUNET_free (rh->json_enc);
  GNUNET_free (rh);
}


/* end of bank_api_reject.c */
