/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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
 * @file lib/exchange_api_csr.c
 * @brief Implementation of /csr requests (get R in exchange used for Clause Schnorr withdraw and refresh)
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
struct TALER_EXCHANGE_CsRHandle
{
  /**
   * The connection to exchange this request handle will use
   */
  struct TALER_EXCHANGE_Handle *exchange;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_CsRCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Denomination key we are withdrawing.
   */
  struct TALER_EXCHANGE_DenomPublicKey pk;

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
 * @param wh operation handle
 * @param json reply from the exchange
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static enum GNUNET_GenericReturnValue
csr_ok (const json_t *json,
        struct TALER_EXCHANGE_CsRResponse *csrr)
{
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed ("r_pub_0",
                            &csrr->details.success.r_pubs.r_pub[0],
                            sizeof (struct GNUNET_CRYPTO_CsRPublic)),
    GNUNET_JSON_spec_fixed ("r_pub_1",
                            &csrr->details.success.r_pubs.r_pub[1],
                            sizeof (struct GNUNET_CRYPTO_CsRPublic)),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  GNUNET_JSON_parse_free (spec);
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the HTTP /csr request.
 *
 * @param cls the `struct TALER_EXCHANGE_CsRHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_csr_finished (void *cls,
                     long response_code,
                     const void *response)
{
  struct TALER_EXCHANGE_CsRHandle *csrh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .reply = j,
    .http_status = (unsigned int) response_code
  };
  struct TALER_EXCHANGE_CsRResponse csrr = {
    .hr = hr
  };

  csrh->job = NULL;
  switch (response_code)
  {
  case 0:
    csrr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        csr_ok (j,
                &csrr))
    {
      GNUNET_break_op (0);
      csrr.hr.http_status = 0;
      csrr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
      break;
    }
    break;
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
  TALER_EXCHANGE_csr_cancel (csrh);
}


struct TALER_EXCHANGE_CsRHandle *
TALER_EXCHANGE_csr (struct TALER_EXCHANGE_Handle *exchange,
                    const struct TALER_EXCHANGE_DenomPublicKey *pk,
                    const struct TALER_WithdrawNonce *nonce,
                    TALER_EXCHANGE_CsRCallback res_cb,
                    void *res_cb_cls)
{
  struct TALER_EXCHANGE_CsRHandle *csrh;

  if (TALER_DENOMINATION_CS != pk->key.cipher)
  {
    GNUNET_break (0);
    return NULL;
  }

  csrh = GNUNET_new (struct TALER_EXCHANGE_CsRHandle);
  csrh->exchange = exchange;
  csrh->cb = res_cb;
  csrh->cb_cls = res_cb_cls;
  csrh->pk = *pk;

  {
    json_t *csr_obj;

    csr_obj = GNUNET_JSON_PACK (GNUNET_JSON_pack_data_varsize ("nonce",
                                                               nonce,
                                                               sizeof(struct
                                                                      TALER_WithdrawNonce)),
                                GNUNET_JSON_pack_data_varsize ("denom_pub_hash",
                                                               &pk->h_key,
                                                               sizeof(struct
                                                                      TALER_DenominationHash)));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Attempting to request R with denomination public key %s\n",
                TALER_B2S (&pk->key.details.cs_public_key));
    csrh->url = TEAH_path_to_url (exchange,
                                  "/csr");
    if (NULL == csrh->url)
    {
      json_decref (csr_obj);
      GNUNET_free (csrh);
      return NULL;
    }
    {
      CURL *eh;
      struct GNUNET_CURL_Context *ctx;

      ctx = TEAH_handle_to_context (exchange);
      eh = TALER_EXCHANGE_curl_easy_get_ (csrh->url);
      if ( (NULL == eh) ||
           (GNUNET_OK !=
            TALER_curl_easy_post (&csrh->post_ctx,
                                  eh,
                                  csr_obj)) )
      {
        GNUNET_break (0);
        if (NULL != eh)
          curl_easy_cleanup (eh);
        json_decref (csr_obj);
        GNUNET_free (csrh->url);
        GNUNET_free (csrh);
        return NULL;
      }
      json_decref (csr_obj);
      csrh->job = GNUNET_CURL_job_add2 (ctx,
                                        eh,
                                        csrh->post_ctx.headers,
                                        &handle_csr_finished,
                                        csrh);
    }
  }

  return csrh;
}


void
TALER_EXCHANGE_csr_cancel (struct TALER_EXCHANGE_CsRHandle *csrh)
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
