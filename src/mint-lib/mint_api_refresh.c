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
 * @file mint-lib/mint_api_refresh.c
 * @brief Implementation of the /refresh/melt+reveal requests of the mint's HTTP API
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


/* ********************* /refresh/ common ***************************** */


/**
 * Melt (partially spent) coins to obtain fresh coins that are
 * unlinkable to the original coin(s).  Note that melting more
 * than one coin in a single request will make those coins linkable,
 * so the safest operation only melts one coin at a time.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, is operation does
 * not actually initiate the request. Instead, it generates a buffer
 * which the caller must store before proceeding with the actual call
 * to #TALER_MINT_refresh_execute() that will generate the request.
 *
 * This function does verify that the given request data is internally
 * consistent.  However, the @a melts_sigs are only verified if @a
 * check_sigs is set to #GNUNET_YES, as this may be relatively
 * expensive and should be redundant.
 *
 * Aside from some non-trivial cryptographic operations that might
 * take a bit of CPU time to complete, this function returns
 * its result immediately and does not start any asynchronous
 * processing.  This function is also thread-safe.
 *
 * @param num_melts number of coins that are being melted (typically 1)
 * @param melt_privs array of @a num_melts private keys of the coins to melt
 * @param melt_amounts array of @a num_melts amounts specifying how much
 *                     each coin will contribute to the melt (including fee)
 * @param melt_sigs array of @a num_melts signatures affirming the
 *                   validity of the public keys corresponding to the
 *                   @a melt_privs private keys
 * @param melt_pks array of @a num_melts denomination key information
 *                   records corresponding to the @a melt_sigs
 *                   validity of the keys
 * @param check_sigs verify the validity of the signatures of @a melt_sigs
 * @param fresh_pks_len length of the @a pks array
 * @param fresh_pks array of @a pks_len denominations of fresh coins to create
 * @param[OUT] res_size set to the size of the return value, or 0 on error
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this mint).
 *         Otherwise, pointer to a buffer of @a res_size to store persistently
 *         before proceeding to #TALER_MINT_refresh_execute().
 *         Non-null results should be freed using #GNUNET_free().
 */
char *
TALER_MINT_refresh_prepare (unsigned int num_melts,
                            const struct TALER_CoinSpendPrivateKeyP *melt_privs,
                            const struct TALER_Amount *melt_amounts,
                            const struct TALER_DenominationSignature *melt_sigs,
                            const struct TALER_MINT_DenomPublicKey *melt_pks,
                            int check_sigs,
                            unsigned int fresh_pks_len,
                            const struct TALER_MINT_DenomPublicKey *fresh_pks,
                            size_t *res_size)
{
  GNUNET_break (0); // FIXME: not implemented
  *res_size = 0;
  return NULL;
}


/* ********************* /refresh/melt ***************************** */


/**
 * @brief A /refresh/melt Handle
 */
struct TALER_MINT_RefreshMeltHandle
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
   * Function to call with refresh melt failure results.
   */
  TALER_MINT_RefreshMeltCallback melt_cb;

  /**
   * Closure for @e result_cb and @e melt_failure_cb.
   */
  void *melt_cb_cls;

  /**
   * Download buffer
   */
  struct MAC_DownloadBuffer db;

};


/**
 * Function called when we're done processing the
 * HTTP /refresh/melt request.
 *
 * @param cls the `struct TALER_MINT_RefreshMeltHandle`
 * @param eh the curl request handle
 */
static void
handle_refresh_melt_finished (void *cls,
                              CURL *eh)
{
  struct TALER_MINT_RefreshMeltHandle *rmh = cls;
  long response_code;
  json_t *json;

  rmh->job = NULL;
  json = MAC_download_get_result (&rmh->db,
                                  eh,
                                  &response_code);
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    GNUNET_break (0); // FIXME: NOT implemented! (parse, check sig!)

    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the mint is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Double spending; check signatures on transaction history */
    GNUNET_break (0); // FIXME: NOT implemented!
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, mint says one of the signatures is
       invalid; assuming we checked them, this should never happen, we
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
  if (NULL != rmh->melt_cb)
    rmh->melt_cb (rmh->melt_cb_cls,
                  response_code,
                  UINT16_MAX,
                  json);
  json_decref (json);
  TALER_MINT_refresh_melt_cancel (rmh);
}


/**
 * Submit a melt request to the mint and get the mint's
 * response.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, the provided
 * argument should have been constructed using
 * #TALER_MINT_refresh_prepare and committed to persistent storage
 * prior to calling this function.
 *
 * @param mint the mint handle; the mint must be ready to operate
 * @param refresh_data_length size of the @a refresh_data (returned
 *        in the `res_size` argument from #TALER_MINT_refresh_prepare())
 * @param refresh_data the refresh data as returned from
          #TALER_MINT_refresh_prepare())
 * @param melt_cb the callback to call with the result
 * @param melt_cb_cls closure for @a melt_cb
 * @return a handle for this request; NULL if the argument was invalid.
 *         In this case, neither callback will be called.
 */
struct TALER_MINT_RefreshMeltHandle *
TALER_MINT_refresh_melt (struct TALER_MINT_Handle *mint,
                         size_t refresh_data_length,
                         const char *refresh_data,
                         TALER_MINT_RefreshMeltCallback melt_cb,
                         void *melt_cb_cls)
{
  json_t *melt_obj;
  struct TALER_MINT_RefreshMeltHandle *rmh;
  CURL *eh;
  struct TALER_MINT_Context *ctx;

  if (GNUNET_YES !=
      MAH_handle_is_ready (mint))
  {
    GNUNET_break (0);
    return NULL;
  }
  /* FIXME: parse "refresh_data" */

  /* FIXME: totally bogus request building here: */
  melt_obj = json_pack ("{s:o, s:O}", /* f/wire */
                        "4", 42,
                        "6", 62);


  rmh = GNUNET_new (struct TALER_MINT_RefreshMeltHandle);
  rmh->mint = mint;
  rmh->melt_cb = melt_cb;
  rmh->melt_cb_cls = melt_cb_cls;

  rmh->url = MAH_path_to_url (mint,
                              "/refresh/melt");

  eh = curl_easy_init ();
  GNUNET_assert (NULL != (rmh->json_enc =
                          json_dumps (melt_obj,
                                      JSON_COMPACT)));
  json_decref (melt_obj);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   rmh->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDS,
                                   rmh->json_enc));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDSIZE,
                                   strlen (rmh->json_enc)));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEFUNCTION,
                                   &MAC_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEDATA,
                                   &rmh->db));
  ctx = MAH_handle_to_context (mint);
  rmh->job = MAC_job_add (ctx,
                          eh,
                          GNUNET_YES,
                          &handle_refresh_melt_finished,
                          rmh);
  return rmh;
}


/**
 * Cancel a refresh execute request.  This function cannot be used
 * on a request handle if either callback was already invoked.
 *
 * @param rmh the refresh melt handle
 */
void
TALER_MINT_refresh_melt_cancel (struct TALER_MINT_RefreshMeltHandle *rmh)
{
  if (NULL != rmh->job)
  {
    MAC_job_cancel (rmh->job);
    rmh->job = NULL;
  }
  GNUNET_free_non_null (rmh->db.buf);
  GNUNET_free (rmh->url);
  GNUNET_free (rmh->json_enc);
  GNUNET_free (rmh);
}


/* ********************* /refresh/reveal ***************************** */


/**
 * @brief A /refresh/reveal Handle
 */
struct TALER_MINT_RefreshRevealHandle
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
  TALER_MINT_RefreshRevealCallback reveal_cb;

  /**
   * Closure for @e reveal_cb.
   */
  void *reveal_cb_cls;

  /**
   * Download buffer
   */
  struct MAC_DownloadBuffer db;


};


/**
 * Function called when we're done processing the
 * HTTP /refresh/reveal request.
 *
 * @param cls the `struct TALER_MINT_RefreshHandle`
 * @param eh the curl request handle
 */
static void
handle_refresh_reveal_finished (void *cls,
                                CURL *eh)
{
  struct TALER_MINT_RefreshRevealHandle *rrh = cls;
  long response_code;
  json_t *json;

  rrh->job = NULL;
  json = MAC_download_get_result (&rrh->db,
                                  eh,
                                  &response_code);
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    GNUNET_break (0); // FIXME: NOT implemented!
    // rrh->reveal_cb = NULL; (call with real result, do not call again below)
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the mint is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_CONFLICT:
    /* Nothing really to verify, mint says our reveal is inconsitent
       with our commitment, so either side is buggy; we
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
  if (NULL != rrh->reveal_cb)
    rrh->reveal_cb (rrh->reveal_cb_cls,
                    response_code,
                    0, NULL, NULL,
                    json);
  json_decref (json);
  TALER_MINT_refresh_reveal_cancel (rrh);
}



/**
 * Submit a /refresh/reval request to the mint and get the mint's
 * response.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, the provided
 * arguments should have been committed to persistent storage
 * prior to calling this function.
 *
 * @param mint the mint handle; the mint must be ready to operate
 * @param refresh_data_length size of the @a refresh_data (returned
 *        in the `res_size` argument from #TALER_MINT_refresh_prepare())
 * @param refresh_data the refresh data as returned from
          #TALER_MINT_refresh_prepare())
 * @param noreveal_index response from the mint to the
 *        #TALER_MINT_refresh_melt() invocation
 * @param reveal_cb the callback to call with the final result of the
 *        refresh operation
 * @param reveal_cb_cls closure for the above callback
 * @return a handle for this request; NULL if the argument was invalid.
 *         In this case, neither callback will be called.
 */
struct TALER_MINT_RefreshRevealHandle *
TALER_MINT_refresh_reveal (struct TALER_MINT_Handle *mint,
                           size_t refresh_data_length,
                           const char *refresh_data,
                           uint16_t noreveal_index,
                           TALER_MINT_RefreshRevealCallback reveal_cb,
                           void *reveal_cb_cls)
{
  struct TALER_MINT_RefreshRevealHandle *rrh;
  json_t *reveal_obj;
  CURL *eh;
  struct TALER_MINT_Context *ctx;

  if (GNUNET_YES !=
      MAH_handle_is_ready (mint))
  {
    GNUNET_break (0);
    return NULL;
  }
  /* FIXME: parse "refresh_data" */

  /* FIXME: totally bogus request building here: */
  reveal_obj = json_pack ("{s:o, s:O}", /* f/wire */
                          "4", 42,
                          "6", 62);

  rrh = GNUNET_new (struct TALER_MINT_RefreshRevealHandle);
  rrh->mint = mint;
  rrh->reveal_cb = reveal_cb;
  rrh->reveal_cb_cls = reveal_cb_cls;

  rrh->url = MAH_path_to_url (rrh->mint,
                              "/refresh/reveal");

  eh = curl_easy_init ();
  GNUNET_assert (NULL != (rrh->json_enc =
                          json_dumps (reveal_obj,
                                      JSON_COMPACT)));
  json_decref (reveal_obj);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   rrh->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDS,
                                   rrh->json_enc));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDSIZE,
                                   strlen (rrh->json_enc)));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEFUNCTION,
                                   &MAC_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEDATA,
                                   &rrh->db));
  ctx = MAH_handle_to_context (rrh->mint);
  rrh->job = MAC_job_add (ctx,
                          eh,
                          GNUNET_YES,
                          &handle_refresh_reveal_finished,
                          rrh);
  return rrh;
}


/**
 * Cancel a refresh reveal request.  This function cannot be used
 * on a request handle if the callback was already invoked.
 *
 * @param rrh the refresh reval handle
 */
void
TALER_MINT_refresh_reveal_cancel (struct TALER_MINT_RefreshRevealHandle *rrh)
{
  if (NULL != rrh->job)
  {
    MAC_job_cancel (rrh->job);
    rrh->job = NULL;
  }
  GNUNET_free_non_null (rrh->db.buf);
  GNUNET_free (rrh->url);
  GNUNET_free (rrh->json_enc);
  GNUNET_free (rrh);
}


/* end of mint_api_refresh.c */
