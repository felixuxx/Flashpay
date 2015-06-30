/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

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
 * @file mint-lib/mint_api_admin.c
 * @brief Implementation of the /admin/ requests of the mint's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include "taler_mint_service.h"
#include "mint_api_json.h"
#include "mint_api_context.h"
#include "mint_api_handle.h"
#include "taler_signatures.h"


/**
 * Print JSON parsing related error information
 */
#define JSON_WARN(error)                                                \
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,                              \
                "JSON parsing failed at %s:%u: %s (%s)",                \
                __FILE__, __LINE__, error.text, error.source)


/**
 * @brief An admin/add/incoming Handle
 */
struct TALER_MINT_AdminAddIncomingHandle
{

  /**
   * The connection to mint this request handle will use
   */
  struct TALER_MINT_Handle *mint;

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
  struct MAC_Job *job;

  /**
   * HTTP headers for the request.
   */
  struct curl_slist *headers;

  /**
   * Function to call with the result.
   */
  TALER_MINT_AdminAddIncomingResultCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Download buffer
   */
  void *buf;

  /**
   * The size of the download buffer
   */
  size_t buf_size;

  /**
   * Error code (based on libc errno) if we failed to download
   * (i.e. response too large).
   */
  int eno;

};


/**
 * Function called when we're done processing the
 * HTTP /admin/add/incoming request.
 *
 * @param cls the `struct TALER_MINT_AdminAddIncomingHandle`
 */
static void
handle_admin_add_incoming_finished (void *cls,
                                    CURL *eh)
{
  struct TALER_MINT_AdminAddIncomingHandle *aai = cls;
  long response_code;
  json_error_t error;
  json_t *json;

  json = NULL;
  if (0 == aai->eno)
  {
    json = json_loadb (aai->buf,
                       aai->buf_size,
                       JSON_REJECT_DUPLICATES | JSON_DISABLE_EOF_CHECK,
                       &error);
    if (NULL == json)
    {
      JSON_WARN (error);
      response_code = 0;
    }
  }
  if (NULL != json)
  {
    if (CURLE_OK !=
        curl_easy_getinfo (eh,
                           CURLINFO_RESPONSE_CODE,
                           &response_code))
    {
      /* unexpected error... */
      GNUNET_break (0);
      response_code = 0;
    }
  }
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the mint is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Access denied */
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, mint says one of the signatures is
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
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  aai->cb (aai->cb_cls,
           response_code,
           json);
  json_decref (json);
  TALER_MINT_admin_add_incoming_cancel (aai);
}


/**
 * Callback used when downloading the reply to a /admin/add/incoming
 * request.  Just appends all of the data to the `buf` in the `struct
 * TALER_MINT_AdminAddIncomingHandle` for further processing. The size
 * of the download is limited to #GNUNET_MAX_MALLOC_CHECKED, if the
 * download exceeds this size, we abort with an error.
 *
 * @param bufptr data downloaded via HTTP
 * @param size size of an item in @a bufptr
 * @param nitems number of items in @a bufptr
 * @param cls the `struct TALER_MINT_DepositHandle`
 * @return number of bytes processed from @a bufptr
 */
static int
admin_add_incoming_download_cb (char *bufptr,
                                size_t size,
                                size_t nitems,
                                void *cls)
{
  struct TALER_MINT_AdminAddIncomingHandle *aai = cls;
  size_t msize;
  void *buf;

  if (0 == size * nitems)
  {
    /* Nothing (left) to do */
    return 0;
  }
  msize = size * nitems;
  if ( (msize + aai->buf_size) >= GNUNET_MAX_MALLOC_CHECKED)
  {
    aai->eno = ENOMEM;
    return 0; /* signals an error to curl */
  }
  aai->buf = GNUNET_realloc (aai->buf,
                             aai->buf_size + msize);
  buf = aai->buf + aai->buf_size;
  memcpy (buf, bufptr, msize);
  aai->buf_size += msize;
  return msize;
}


/**
 * Notify the mint that we have received an incoming transaction
 * which fills a reserve.  Note that this API is an administrative
 * API and thus not accessible to typical mint clients, but only
 * to the operators of the mint.
 *
 * @param mint the mint handle; the mint must be ready to operate
 * @param reserve_pub public key of the reserve
 * @param amount amount that was deposited
 * @param execution_date when did we receive the amount
 * @param wire wire details
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return NULL
 *         if the inputs are invalid (i.e. invalid amount).
 *         In this case, the callback is not called.
 */
struct TALER_MINT_AdminAddIncomingHandle *
TALER_MINT_admin_add_incoming (struct TALER_MINT_Handle *mint,
                               const struct TALER_ReservePublicKeyP *reserve_pub,
                               const struct TALER_Amount *amount,
                               const struct GNUNET_TIME_Absolute execution_date,
                               const json_t *wire,
                               TALER_MINT_AdminAddIncomingResultCallback res_cb,
                               void *res_cb_cls)
{
  struct TALER_MINT_AdminAddIncomingHandle *aai;
  struct TALER_MINT_Context *ctx;
  json_t *admin_obj;
  CURL *eh;

  if (GNUNET_YES !=
      MAH_handle_is_ready (mint))
  {
    GNUNET_break (0);
    return NULL;
  }
  admin_obj = json_pack ("{s:o, s:o," /* reserve_pub/amount */
                         " s:o, s:o}", /* execution_Date/wire */
                         "reserve_pub", TALER_json_from_data (reserve_pub,
                                                               sizeof (*reserve_pub)),
                         "amount", TALER_json_from_amount (amount),
                         "execution_date", TALER_json_from_abs (execution_date),
                         "wire", wire);
  aai = GNUNET_new (struct TALER_MINT_AdminAddIncomingHandle);
  aai->mint = mint;
  aai->cb = res_cb;
  aai->cb_cls = res_cb_cls;
  aai->url = MAH_path_to_url (mint, "/admin/add/incoming");

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
                                   &admin_add_incoming_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEDATA,
                                   aai));
  GNUNET_assert (NULL != (aai->headers =
                          curl_slist_append (aai->headers,
                                             "Content-Type: application/json")));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_HTTPHEADER,
                                   aai->headers));
  ctx = MAH_handle_to_context (mint);
  aai->job = MAC_job_add (ctx,
                          eh,
                          &handle_admin_add_incoming_finished,
                          aai);
  return aai;
}


/**
 * Cancel an add incoming.  This function cannot be used on a request
 * handle if a response is already served for it.
 *
 * @param sign the admin add incoming request handle
 */
void
TALER_MINT_admin_add_incoming_cancel (struct TALER_MINT_AdminAddIncomingHandle *aai)
{
  MAC_job_cancel (aai->job);
  curl_slist_free_all (aai->headers);
  GNUNET_free (aai->url);
  GNUNET_free (aai->json_enc);
  GNUNET_free (aai);
}


/* end of mint_api_admin.c */
