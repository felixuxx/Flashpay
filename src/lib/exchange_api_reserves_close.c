/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * @file lib/exchange_api_reserves_close.c
 * @brief Implementation of the POST /reserves/$RESERVE_PUB/close requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP close codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A /reserves/$RID/close Handle
 */
struct TALER_EXCHANGE_ReservesCloseHandle
{

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
  TALER_EXCHANGE_ReservesCloseCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Public key of the reserve we are querying.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Our signature.
   */
  struct TALER_ReserveSignatureP reserve_sig;

  /**
   * When did we make the request.
   */
  struct GNUNET_TIME_Timestamp ts;

};


/**
 * We received an #MHD_HTTP_OK close code. Handle the JSON
 * response.
 *
 * @param rch handle of the request
 * @param j JSON response
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_reserves_close_ok (struct TALER_EXCHANGE_ReservesCloseHandle *rch,
                          const json_t *j)
{
  struct TALER_EXCHANGE_ReserveCloseResult rs = {
    .hr.reply = j,
    .hr.http_status = MHD_HTTP_OK,
  };
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount_any ("wire_amount",
                                &rs.details.ok.wire_amount),
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
  rch->cb (rch->cb_cls,
           &rs);
  rch->cb = NULL;
  GNUNET_JSON_parse_free (spec);
  return GNUNET_OK;
}


/**
 * We received an #MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS close code. Handle the JSON
 * response.
 *
 * @param rch handle of the request
 * @param j JSON response
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_reserves_close_kyc (struct TALER_EXCHANGE_ReservesCloseHandle *rch,
                           const json_t *j)
{
  struct TALER_EXCHANGE_ReserveCloseResult rs = {
    .hr.reply = j,
    .hr.http_status = MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS,
  };
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto (
      "h_payto",
      &rs.details.unavailable_for_legal_reasons.h_payto),
    GNUNET_JSON_spec_uint64 (
      "requirement_row",
      &rs.details.unavailable_for_legal_reasons.requirement_row),
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
  rch->cb (rch->cb_cls,
           &rs);
  rch->cb = NULL;
  GNUNET_JSON_parse_free (spec);
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /reserves/$RID/close request.
 *
 * @param cls the `struct TALER_EXCHANGE_ReservesCloseHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_reserves_close_finished (void *cls,
                                long response_code,
                                const void *response)
{
  struct TALER_EXCHANGE_ReservesCloseHandle *rch = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_ReserveCloseResult rs = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  rch->job = NULL;
  switch (response_code)
  {
  case 0:
    rs.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        handle_reserves_close_ok (rch,
                                  j))
    {
      GNUNET_break_op (0);
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
    /* Insufficient balance to inquire for reserve close */
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS:
    if (GNUNET_OK !=
        handle_reserves_close_kyc (rch,
                                   j))
    {
      GNUNET_break_op (0);
      rs.hr.http_status = 0;
      rs.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
    }
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
                "Unexpected response code %u/%d for reserves close\n",
                (unsigned int) response_code,
                (int) rs.hr.ec);
    break;
  }
  if (NULL != rch->cb)
  {
    rch->cb (rch->cb_cls,
             &rs);
    rch->cb = NULL;
  }
  TALER_EXCHANGE_reserves_close_cancel (rch);
}


struct TALER_EXCHANGE_ReservesCloseHandle *
TALER_EXCHANGE_reserves_close (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  const struct TALER_FullPayto target_payto_uri,
  TALER_EXCHANGE_ReservesCloseCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ReservesCloseHandle *rch;
  CURL *eh;
  char arg_str[sizeof (struct TALER_ReservePublicKeyP) * 2 + 32];
  struct TALER_FullPaytoHashP h_payto;

  rch = GNUNET_new (struct TALER_EXCHANGE_ReservesCloseHandle);
  rch->cb = cb;
  rch->cb_cls = cb_cls;
  rch->ts = GNUNET_TIME_timestamp_get ();
  GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                      &rch->reserve_pub.eddsa_pub);
  {
    char pub_str[sizeof (struct TALER_ReservePublicKeyP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &rch->reserve_pub,
      sizeof (rch->reserve_pub),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "reserves/%s/close",
                     pub_str);
  }
  rch->url = TALER_url_join (url,
                             arg_str,
                             NULL);
  if (NULL == rch->url)
  {
    GNUNET_free (rch);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (rch->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (rch->url);
    GNUNET_free (rch);
    return NULL;
  }
  if (NULL != target_payto_uri.full_payto)
    TALER_full_payto_hash (target_payto_uri,
                           &h_payto);
  TALER_wallet_reserve_close_sign (rch->ts,
                                   (NULL != target_payto_uri.full_payto)
                                   ? &h_payto
                                   : NULL,
                                   reserve_priv,
                                   &rch->reserve_sig);
  {
    json_t *close_obj = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_allow_null (
        TALER_JSON_pack_full_payto ("payto_uri",
                                    target_payto_uri)),
      GNUNET_JSON_pack_timestamp ("request_timestamp",
                                  rch->ts),
      GNUNET_JSON_pack_data_auto ("reserve_sig",
                                  &rch->reserve_sig));

    if (GNUNET_OK !=
        TALER_curl_easy_post (&rch->post_ctx,
                              eh,
                              close_obj))
    {
      GNUNET_break (0);
      curl_easy_cleanup (eh);
      json_decref (close_obj);
      GNUNET_free (rch->url);
      GNUNET_free (rch);
      return NULL;
    }
    json_decref (close_obj);
  }
  rch->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   rch->post_ctx.headers,
                                   &handle_reserves_close_finished,
                                   rch);
  return rch;
}


void
TALER_EXCHANGE_reserves_close_cancel (
  struct TALER_EXCHANGE_ReservesCloseHandle *rch)
{
  if (NULL != rch->job)
  {
    GNUNET_CURL_job_cancel (rch->job);
    rch->job = NULL;
  }
  TALER_curl_easy_post_finished (&rch->post_ctx);
  GNUNET_free (rch->url);
  GNUNET_free (rch);
}


/* end of exchange_api_reserves_close.c */
