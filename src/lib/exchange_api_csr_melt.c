/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file lib/exchange_api_csr_melt.c
 * @brief Implementation of /csr-melt requests (get R in exchange used for Clause Schnorr refresh)
 * @author Lucien Heuzeveldt
 * @author Gian Demarmels
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A Clause Schnorr R Handle
 */
struct TALER_EXCHANGE_CsRMeltHandle
{

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_CsRMeltCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * The url for this request.
   */
  char *url;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Context for #TEH_curl_easy_post(). Keeps the data that must
   * persist for Curl to make the upload.
   */
  struct TALER_CURL_PostContext post_ctx;
};


/**
 * We got a 200 OK response for the /reserves/$RESERVE_PUB/withdraw operation.
 * Extract the coin's signature and return it to the caller.  The signature we
 * get from the exchange is for the blinded value.  Thus, we first must
 * unblind it and then should verify its validity against our coin's hash.
 *
 * If everything checks out, we return the unblinded signature
 * to the application via the callback.
 *
 * @param csrh operation handle
 * @param arr reply from the exchange
 * @param hr http response details
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static enum GNUNET_GenericReturnValue
csr_ok (struct TALER_EXCHANGE_CsRMeltHandle *csrh,
        const json_t *arr,
        struct TALER_EXCHANGE_HttpResponse *hr)
{
  unsigned int alen = json_array_size (arr);
  struct TALER_ExchangeWithdrawValues alg_values[GNUNET_NZL (alen)];
  struct TALER_EXCHANGE_CsRMeltResponse csrr = {
    .hr = *hr,
    .details.ok.alg_values_len = alen,
    .details.ok.alg_values = alg_values
  };

  for (unsigned int i = 0; i<alen; i++)
  {
    json_t *av = json_array_get (arr,
                                 i);
    struct GNUNET_JSON_Specification spec[] = {
      TALER_JSON_spec_exchange_withdraw_values (
        "ewv",
        &alg_values[i]),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (av,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }
  csrh->cb (csrh->cb_cls,
            &csrr);
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the HTTP /csr request.
 *
 * @param cls the `struct TALER_EXCHANGE_CsRMeltHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_csr_finished (void *cls,
                     long response_code,
                     const void *response)
{
  struct TALER_EXCHANGE_CsRMeltHandle *csrh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .reply = j,
    .http_status = (unsigned int) response_code
  };
  struct TALER_EXCHANGE_CsRMeltResponse csrr = {
    .hr = hr
  };

  csrh->job = NULL;
  switch (response_code)
  {
  case 0:
    csrr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      json_t *arr;

      arr = json_object_get (j,
                             "ewvs");
      if ( (NULL == arr) ||
           (0 == json_array_size (arr)) ||
           (GNUNET_OK !=
            csr_ok (csrh,
                    arr,
                    &hr)) )
      {
        GNUNET_break_op (0);
        csrr.hr.http_status = 0;
        csrr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
    }
    TALER_EXCHANGE_csr_melt_cancel (csrh);
    return;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    csrr.hr.ec = TALER_JSON_get_error_code (j);
    csrr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, the exchange basically just says
       that it doesn't know the /csr endpoint or denomination.
       Can happen if the exchange doesn't support Clause Schnorr.
       We should simply pass the JSON reply to the application. */
    csrr.hr.ec = TALER_JSON_get_error_code (j);
    csrr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_GONE:
    /* could happen if denomination was revoked */
    /* Note: one might want to check /keys for revocation
       signature here, alas tricky in case our /keys
       is outdated => left to clients */
    csrr.hr.ec = TALER_JSON_get_error_code (j);
    csrr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    csrr.hr.ec = TALER_JSON_get_error_code (j);
    csrr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    csrr.hr.ec = TALER_JSON_get_error_code (j);
    csrr.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for CS R request\n",
                (unsigned int) response_code,
                (int) hr.ec);
    break;
  }
  csrh->cb (csrh->cb_cls,
            &csrr);
  csrh->cb = NULL;
  TALER_EXCHANGE_csr_melt_cancel (csrh);
}


struct TALER_EXCHANGE_CsRMeltHandle *
TALER_EXCHANGE_csr_melt (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_RefreshMasterSecretP *rms,
  unsigned int nks_len,
  struct TALER_EXCHANGE_NonceKey *nks,
  TALER_EXCHANGE_CsRMeltCallback res_cb,
  void *res_cb_cls)
{
  struct TALER_EXCHANGE_CsRMeltHandle *csrh;
  json_t *csr_arr;

  if (0 == nks_len)
  {
    GNUNET_break (0);
    return NULL;
  }
  for (unsigned int i = 0; i<nks_len; i++)
    if (TALER_DENOMINATION_CS != nks[i].pk->key.cipher)
    {
      GNUNET_break (0);
      return NULL;
    }
  csrh = GNUNET_new (struct TALER_EXCHANGE_CsRMeltHandle);
  csrh->cb = res_cb;
  csrh->cb_cls = res_cb_cls;
  csr_arr = json_array ();
  GNUNET_assert (NULL != csr_arr);
  for (unsigned int i = 0; i<nks_len; i++)
  {
    const struct TALER_EXCHANGE_NonceKey *nk = &nks[i];
    json_t *csr_obj;

    csr_obj = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("coin_offset",
                               nk->cnc_num),
      GNUNET_JSON_pack_data_auto ("denom_pub_hash",
                                  &nk->pk->h_key));
    GNUNET_assert (NULL != csr_obj);
    GNUNET_assert (0 ==
                   json_array_append_new (csr_arr,
                                          csr_obj));
  }
  csrh->url = TALER_url_join (url,
                              "csr-melt",
                              NULL);
  if (NULL == csrh->url)
  {
    json_decref (csr_arr);
    GNUNET_free (csrh);
    return NULL;
  }
  {
    CURL *eh;
    json_t *req;

    req = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_data_auto ("rms",
                                  rms),
      GNUNET_JSON_pack_array_steal ("nks",
                                    csr_arr));
    eh = TALER_EXCHANGE_curl_easy_get_ (csrh->url);
    if ( (NULL == eh) ||
         (GNUNET_OK !=
          TALER_curl_easy_post (&csrh->post_ctx,
                                eh,
                                req)) )
    {
      GNUNET_break (0);
      if (NULL != eh)
        curl_easy_cleanup (eh);
      json_decref (req);
      GNUNET_free (csrh->url);
      GNUNET_free (csrh);
      return NULL;
    }
    json_decref (req);
    csrh->job = GNUNET_CURL_job_add2 (ctx,
                                      eh,
                                      csrh->post_ctx.headers,
                                      &handle_csr_finished,
                                      csrh);
  }
  return csrh;
}


void
TALER_EXCHANGE_csr_melt_cancel (struct TALER_EXCHANGE_CsRMeltHandle *csrh)
{
  if (NULL != csrh->job)
  {
    GNUNET_CURL_job_cancel (csrh->job);
    csrh->job = NULL;
  }
  GNUNET_free (csrh->url);
  TALER_curl_easy_post_finished (&csrh->post_ctx);
  GNUNET_free (csrh);
}
