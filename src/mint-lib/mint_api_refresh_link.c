/*
  This file is part of TALER
  Copyright (C) 2015 Christian Grothoff (and other contributing authors)

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
 * @file mint-lib/mint_api_refresh_link.c
 * @brief Implementation of the /refresh/link request of the mint's HTTP API
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
 * @brief A /refresh/link Handle
 */
struct TALER_MINT_RefreshLinkHandle
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
   * Function to call with the result.
   */
  TALER_MINT_RefreshLinkCallback link_cb;

  /**
   * Closure for @e cb.
   */
  void *link_cb_cls;

  /**
   * Download buffer
   */
  struct MAC_DownloadBuffer db;

};


/**
 * Function called when we're done processing the
 * HTTP /refresh/link request.
 *
 * @param cls the `struct TALER_MINT_RefreshLinkHandle`
 * @param eh the curl request handle
 */
static void
handle_refresh_link_finished (void *cls,
                              CURL *eh)
{
  struct TALER_MINT_RefreshLinkHandle *rlh = cls;
  long response_code;
  json_t *json;

  rlh->job = NULL;
  json = MAC_download_get_result (&rlh->db,
                                  eh,
                                  &response_code);
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    GNUNET_break (0); // FIXME: NOT implemented!
    // rh->link_cb = NULL; (call with real result, do not call again below)
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the mint is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, mint says this coin was not melted; we
       should pass the JSON reply to the application */
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
  if (NULL != rlh->link_cb)
    rlh->link_cb (rlh->link_cb_cls,
                  response_code,
                  0, NULL, NULL,
                  json);
  json_decref (json);
  TALER_MINT_refresh_link_cancel (rlh);
}


/**
 * Submit a link request to the mint and get the mint's response.
 *
 * This API is typically not used by anyone, it is more a threat
 * against those trying to receive a funds transfer by abusing the
 * /refresh protocol.
 *
 * @param mint the mint handle; the mint must be ready to operate
 * @param coin_priv private key to request link data for
 * @param link_cb the callback to call with the useful result of the
 *        refresh operation the @a coin_priv was involved in (if any)
 * @param link_cb_cls closure for @a link_cb
 * @return a handle for this request
 */
struct TALER_MINT_RefreshLinkHandle *
TALER_MINT_refresh_link (struct TALER_MINT_Handle *mint,
                         const struct TALER_CoinSpendPrivateKeyP *coin_priv,
                         TALER_MINT_RefreshLinkCallback link_cb,
                         void *link_cb_cls)
{
  json_t *link_obj;
  struct TALER_MINT_RefreshLinkHandle *rlh;
  CURL *eh;
  struct TALER_MINT_Context *ctx;

  if (GNUNET_YES !=
      MAH_handle_is_ready (mint))
  {
    GNUNET_break (0);
    return NULL;
  }
  /* FIXME: totally bogus request building here: */
  link_obj = json_pack ("{s:o, s:O}", /* f/wire */
                        "4", 42,
                        "6", 62);


  rlh = GNUNET_new (struct TALER_MINT_RefreshLinkHandle);
  rlh->mint = mint;
  rlh->link_cb = link_cb;
  rlh->link_cb_cls = link_cb_cls;

  rlh->url = MAH_path_to_url (mint, "/refresh/link");

  eh = curl_easy_init ();
  GNUNET_assert (NULL != (rlh->json_enc =
                          json_dumps (link_obj,
                                      JSON_COMPACT)));
  json_decref (link_obj);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   rlh->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDS,
                                   rlh->json_enc));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDSIZE,
                                   strlen (rlh->json_enc)));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEFUNCTION,
                                   &MAC_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEDATA,
                                   &rlh->db));
  ctx = MAH_handle_to_context (mint);
  rlh->job = MAC_job_add (ctx,
                          eh,
                          GNUNET_YES,
                          &handle_refresh_link_finished,
                          rlh);
  return rlh;
}


/**
 * Cancel a refresh link request.  This function cannot be used
 * on a request handle if the callback was already invoked.
 *
 * @param rlh the refresh link handle
 */
void
TALER_MINT_refresh_link_cancel (struct TALER_MINT_RefreshLinkHandle *rlh)
{
  if (NULL != rlh->job)
  {
    MAC_job_cancel (rlh->job);
    rlh->job = NULL;
  }
  GNUNET_free_non_null (rlh->db.buf);
  GNUNET_free (rlh->url);
  GNUNET_free (rlh->json_enc);
  GNUNET_free (rlh);
}


/* end of mint_api_refresh_link.c */
