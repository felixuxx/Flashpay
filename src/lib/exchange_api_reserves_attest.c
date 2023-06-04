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
 * @file lib/exchange_api_reserves_attest.c
 * @brief Implementation of the POST /reserves-attest/$RESERVE_PUB requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP attest codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A /reserves-attest/$RID Handle
 */
struct TALER_EXCHANGE_ReservesAttestHandle
{

  /**
   * The connection to exchange this request handle will use
   */
  struct TALER_EXCHANGE_Handle *exchange;

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

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_ReservesPostAttestCallback cb;

  /**
   * Public key of the reserve we are querying.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * We received an #MHD_HTTP_OK attest code. Handle the JSON
 * response.
 *
 * @param rsh handle of the request
 * @param j JSON response
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_reserves_attest_ok (struct TALER_EXCHANGE_ReservesAttestHandle *rsh,
                           const json_t *j)
{
  struct TALER_EXCHANGE_ReservePostAttestResult rs = {
    .hr.reply = j,
    .hr.http_status = MHD_HTTP_OK
  };
  const json_t *attributes;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_timestamp ("exchange_timestamp",
                                &rs.details.ok.exchange_time),
    GNUNET_JSON_spec_timestamp ("expiration_time",
                                &rs.details.ok.expiration_time),
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                 &rs.details.ok.exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 &rs.details.ok.exchange_pub),
    GNUNET_JSON_spec_object_const ("attributes",
                                   &attributes),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (j,
                         spec,
                         NULL,
                         NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  rs.details.ok.attributes = attributes;
  if (GNUNET_OK !=
      TALER_exchange_online_reserve_attest_details_verify (
        rs.details.ok.exchange_time,
        rs.details.ok.expiration_time,
        &rsh->reserve_pub,
        attributes,
        &rs.details.ok.exchange_pub,
        &rs.details.ok.exchange_sig))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return GNUNET_SYSERR;
  }
  rsh->cb (rsh->cb_cls,
           &rs);
  rsh->cb = NULL;
  GNUNET_JSON_parse_free (spec);
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /reserves-attest/$RID request.
 *
 * @param cls the `struct TALER_EXCHANGE_ReservesAttestHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_reserves_attest_finished (void *cls,
                                 long response_code,
                                 const void *response)
{
  struct TALER_EXCHANGE_ReservesAttestHandle *rsh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_ReservePostAttestResult rs = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  rsh->job = NULL;
  switch (response_code)
  {
  case 0:
    rs.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        handle_reserves_attest_ok (rsh,
                                   j))
    {
      rs.hr.http_status = 0;
      rs.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    GNUNET_break (0);
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_FORBIDDEN:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    GNUNET_break (0);
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_CONFLICT:
    /* Server doesn't have the requested attributes */
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for reserves attest\n",
                (unsigned int) response_code,
                (int) rs.hr.ec);
    break;
  }
  if (NULL != rsh->cb)
  {
    rsh->cb (rsh->cb_cls,
             &rs);
    rsh->cb = NULL;
  }
  TALER_EXCHANGE_reserves_attest_cancel (rsh);
}


struct TALER_EXCHANGE_ReservesAttestHandle *
TALER_EXCHANGE_reserves_attest (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  unsigned int attributes_length,
  const char *const*attributes,
  TALER_EXCHANGE_ReservesPostAttestCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ReservesAttestHandle *rsh;
  struct GNUNET_CURL_Context *ctx;
  CURL *eh;
  char arg_str[sizeof (struct TALER_ReservePublicKeyP) * 2 + 32];
  struct TALER_ReserveSignatureP reserve_sig;
  json_t *details;
  struct GNUNET_TIME_Timestamp ts;

  if (0 == attributes_length)
  {
    GNUNET_break (0);
    return NULL;
  }
  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  details = json_array ();
  GNUNET_assert (NULL != details);
  for (unsigned int i = 0; i<attributes_length; i++)
  {
    GNUNET_assert (0 ==
                   json_array_append_new (details,
                                          json_string (attributes[i])));
  }
  rsh = GNUNET_new (struct TALER_EXCHANGE_ReservesAttestHandle);
  rsh->exchange = exchange;
  rsh->cb = cb;
  rsh->cb_cls = cb_cls;
  GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                      &rsh->reserve_pub.eddsa_pub);
  {
    char pub_str[sizeof (struct TALER_ReservePublicKeyP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &rsh->reserve_pub,
      sizeof (rsh->reserve_pub),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/reserves-attest/%s",
                     pub_str);
  }
  rsh->url = TEAH_path_to_url (exchange,
                               arg_str);
  if (NULL == rsh->url)
  {
    json_decref (details);
    GNUNET_free (rsh);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (rsh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    json_decref (details);
    GNUNET_free (rsh->url);
    GNUNET_free (rsh);
    return NULL;
  }
  ts = GNUNET_TIME_timestamp_get ();
  TALER_wallet_reserve_attest_request_sign (ts,
                                            details,
                                            reserve_priv,
                                            &reserve_sig);
  {
    json_t *attest_obj = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_data_auto ("reserve_sig",
                                  &reserve_sig),
      GNUNET_JSON_pack_timestamp ("request_timestamp",
                                  ts),
      GNUNET_JSON_pack_array_steal ("details",
                                    details));

    if (GNUNET_OK !=
        TALER_curl_easy_post (&rsh->post_ctx,
                              eh,
                              attest_obj))
    {
      GNUNET_break (0);
      curl_easy_cleanup (eh);
      json_decref (attest_obj);
      GNUNET_free (rsh->url);
      GNUNET_free (rsh);
      return NULL;
    }
    json_decref (attest_obj);
  }
  ctx = TEAH_handle_to_context (exchange);
  rsh->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   rsh->post_ctx.headers,
                                   &handle_reserves_attest_finished,
                                   rsh);
  return rsh;
}


void
TALER_EXCHANGE_reserves_attest_cancel (
  struct TALER_EXCHANGE_ReservesAttestHandle *rsh)
{
  if (NULL != rsh->job)
  {
    GNUNET_CURL_job_cancel (rsh->job);
    rsh->job = NULL;
  }
  TALER_curl_easy_post_finished (&rsh->post_ctx);
  GNUNET_free (rsh->url);
  GNUNET_free (rsh);
}


/* end of exchange_api_reserves_attest.c */
