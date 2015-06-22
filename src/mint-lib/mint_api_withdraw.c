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
 * @file mint-lib/mint_api_withdraw.c
 * @brief Implementation of the /withdraw requests of the mint's HTTP API
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
 * @brief A Withdraw Status Handle
 */
struct TALER_MINT_WithdrawStatusHandle
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
   * Handle for the request.
   */
  struct MAC_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_MINT_WithdrawStatusResultCallback cb;

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
 * HTTP /withdraw/status request.
 *
 * @param cls the `struct TALER_MINT_WithdrawStatusHandle`
 */
static void
handle_withdraw_status_finished (void *cls,
                                 CURL *eh)
{
  struct TALER_MINT_WithdrawStatusHandle *wsh = cls;
  long response_code;
  json_error_t error;
  json_t *json;

  json = NULL;
  if (0 == dh->eno)
  {
    json = json_loadb (dh->buf,
                       dh->buf_size,
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
  case MHD_HTTP_OK:
    GNUNET_break (0); // FIXME
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the mint is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    GNUNET_break (0); // FIXME
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
  GNUNET_break (0); // FIXME
  wsh->cb (wsh->cb_cls,
           response_code,
           NULL,
           0, NULL);
  json_decref (json);
  TALER_MINT_withdraw_status_cancel (dh);
}


/**
 * Callback used when downloading the reply to a /withdraw/status request.
 * Just appends all of the data to the `buf` in the
 * `struct TALER_MINT_WithdrawStatusHandle` for further processing. The size of
 * the download is limited to #GNUNET_MAX_MALLOC_CHECKED, if
 * the download exceeds this size, we abort with an error.
 *
 * @param bufptr data downloaded via HTTP
 * @param size size of an item in @a bufptr
 * @param nitems number of items in @a bufptr
 * @param cls the `struct TALER_MINT_DepositHandle`
 * @return number of bytes processed from @a bufptr
 */
static int
withdraw_status_download_cb (char *bufptr,
                             size_t size,
                             size_t nitems,
                             void *cls)
{
  struct TALER_MINT_WithdrawStatusHandle *wsh = cls;
  size_t msize;
  void *buf;

  if (0 == size * nitems)
  {
    /* Nothing (left) to do */
    return 0;
  }
  msize = size * nitems;
  if ( (msize + wsh->buf_size) >= GNUNET_MAX_MALLOC_CHECKED)
  {
    wsh->eno = ENOMEM;
    return 0; /* signals an error to curl */
  }
  wsh->buf = GNUNET_realloc (wsh->buf,
                            wsh->buf_size + msize);
  buf = wsh->buf + wsh->buf_size;
  memcpy (buf, bufptr, msize);
  wsh->buf_size += msize;
  return msize;
}


/**
 * Submit a request to obtain the transaction history of a reserve
 * from the mint.  Note that while we return the full response to the
 * caller for further processing, we do already verify that the
 * response is well-formed (i.e. that signatures included in the
 * response are all valid and add up to the balance).  If the mint's
 * reply is not well-formed, we return an HTTP status code of zero to
 * @a cb.
 *
 * @param mint the mint handle; the mint must be ready to operate
 * @param reserve_pub public key of the reserve to inspect
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_MINT_WithdrawStatusHandle *
TALER_MINT_withdraw_status (struct TALER_MINT_Handle *mint,
                            const struct TALER_ReservePublicKeyP *reserve_pub,
                            TALER_MINT_WithdrawStatusResultCallback cb,
                            void *cb_cls);
{
  struct TALER_MINT_WithdrawStatusHandle *wsh;
  struct TALER_MINT_Context *ctx;
  CURL *eh;

  if (GNUNET_YES !=
      MAH_handle_is_ready (mint))
  {
    GNUNET_break (0);
    return NULL;
  }
  wsh = GNUNET_new (struct TALER_MINT_WithdrawStatusHandle);
  wsh->mint = mint;
  wsh->cb = cb;
  wsh->cb_cls = cb_cls;
  wsh->url = MAH_path_to_url (mint, "/withdraw/status");

  eh = curl_easy_init ();
  GNUNET_assert (NULL != (dh->json_enc =
                          json_dumps (deposit_obj,
                                      JSON_COMPACT)));
  json_decref (deposit_obj);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   wsh->url));
#if 0
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDS,
                                   wsh->json_enc));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDSIZE,
                                   strlen (wsh->json_enc)));
#endif
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEFUNCTION,
                                   &deposit_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEDATA,
                                   wsh));
#if 0
  GNUNET_assert (NULL != (wsh->headers =
                          curl_slist_append (wsh->headers,
                                             "Content-Type: application/json")));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (wsh,
                                   CURLOPT_HTTPHEADER,
                                   wsh->headers));
#endif
  GNUNET_break (0); // FIXME
  ctx = MAH_handle_to_context (mint);
  wsh->job = MAC_job_add (ctx,
                          eh,
                          &handle_withdraw_status_finished,
                          wsh);
  return dh;
}


/**
 * Cancel a withdraw status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param wsh the withdraw status request handle
 */
void
TALER_MINT_withdraw_status_cancel (struct TALER_MINT_WithdrawStatusHandle *wsh)
{
  MAC_job_cancel (wsh->job);
#if 0
  curl_slist_free_all (wsh->headers);
  GNUNET_free (wsh->json_enc);
#endif
  GNUNET_free (wsh->url);
  GNUNET_free (wsh);
}




/**
 * Withdraw a coin from the mint using a /withdraw/sign request.  Note
 * that to ensure that no money is lost in case of hardware failures,
 * the caller must have committed (most of) the arguments to disk
 * before calling, and be ready to repeat the request with the same
 * arguments in case of failures.
 *
 * @param mint the mint handle; the mint must be ready to operate
 * @param pk kind of coin to create
 * @param coin_priv where to store the coin's private key,
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param blinding_key where to store the coin's blinding key
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return #GNUNET_OK on success, #GNUNET_SYSERR
 *         if the inputs are invalid (i.e. denomination key not with this mint).
 *         In this case, the callback is not called.
 */
struct TALER_MINT_WithdrawSignHandle *
TALER_MINT_withdraw_sign (struct TALER_MINT_Handle *mint,
                          const struct TALER_MINT_DenomPubKey *pk,
                          const struct TALER_ReservePrivateKeyP *reserve_priv,
                          const struct TALER_MINT_CoinSpendPrivateKeyP *coin_priv,
                          const struct TALER_DenominationBlindingKey *blinding_key,
                          TALER_MINT_WithdrawSignResultCallback res_cb,
                          void *res_cb_cls)
{
  GNUNET_break (0); // FIXME
  return NULL;
}


/**
 * Cancel a withdraw status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param sign the withdraw sign request handle
 */
void
TALER_MINT_withdraw_sign_cancel (struct TALER_MINT_WithdrawSignHandle *sign)
{
  GNUNET_break (0); // FIXME
}


/* end of mint_api_withdraw.c */
