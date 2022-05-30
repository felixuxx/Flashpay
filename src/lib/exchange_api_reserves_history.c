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
 * @file lib/exchange_api_reserves_history.c
 * @brief Implementation of the POST /reserves/$RESERVE_PUB/history requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP history codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A /reserves/$RID/history Handle
 */
struct TALER_EXCHANGE_ReservesHistoryHandle
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
  TALER_EXCHANGE_ReservesHistoryCallback cb;

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
 * We received an #MHD_HTTP_OK history code. Handle the JSON
 * response.
 *
 * @param rsh handle of the request
 * @param j JSON response
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_reserves_history_ok (struct TALER_EXCHANGE_ReservesHistoryHandle *rsh,
                            const json_t *j)
{
  json_t *history;
  unsigned int len;
  struct TALER_EXCHANGE_ReserveHistory rs = {
    .hr.reply = j,
    .hr.http_status = MHD_HTTP_OK,
    .ts = rsh->ts,
    .reserve_sig = &rsh->reserve_sig
  };
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount_any ("balance",
                                &rs.details.ok.balance),
    GNUNET_JSON_spec_json ("history",
                           &history),
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
  len = json_array_size (history);
  {
    struct TALER_EXCHANGE_ReserveHistoryEntry *rhistory;

    rhistory = GNUNET_new_array (len,
                                 struct TALER_EXCHANGE_ReserveHistoryEntry);
    if (GNUNET_OK !=
        TALER_EXCHANGE_parse_reserve_history (rsh->exchange,
                                              history,
                                              &rsh->reserve_pub,
                                              rs.details.ok.balance.currency,
                                              &rs.details.ok.total_in,
                                              &rs.details.ok.total_out,
                                              len,
                                              rhistory))
    {
      GNUNET_break_op (0);
      TALER_EXCHANGE_free_reserve_history (rhistory,
                                           len);
      GNUNET_JSON_parse_free (spec);
      return GNUNET_SYSERR;
    }
    if (NULL != rsh->cb)
    {
      rs.details.ok.history = rhistory;
      rs.details.ok.history_len = len;
      rsh->cb (rsh->cb_cls,
               &rs);
      rsh->cb = NULL;
    }
    TALER_EXCHANGE_free_reserve_history (rhistory,
                                         len);
  }
  GNUNET_JSON_parse_free (spec);
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /reserves/$RID/history request.
 *
 * @param cls the `struct TALER_EXCHANGE_ReservesHistoryHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_reserves_history_finished (void *cls,
                                  long response_code,
                                  const void *response)
{
  struct TALER_EXCHANGE_ReservesHistoryHandle *rsh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_ReserveHistory rs = {
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
        handle_reserves_history_ok (rsh,
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
    /* Insufficient balance to inquire for reserve history */
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
                "Unexpected response code %u/%d for reserves history\n",
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
  TALER_EXCHANGE_reserves_history_cancel (rsh);
}


struct TALER_EXCHANGE_ReservesHistoryHandle *
TALER_EXCHANGE_reserves_history (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  TALER_EXCHANGE_ReservesHistoryCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ReservesHistoryHandle *rsh;
  struct GNUNET_CURL_Context *ctx;
  CURL *eh;
  char arg_str[sizeof (struct TALER_ReservePublicKeyP) * 2 + 32];
  const struct TALER_EXCHANGE_Keys *keys;
  const struct TALER_EXCHANGE_GlobalFee *gf;

  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  rsh = GNUNET_new (struct TALER_EXCHANGE_ReservesHistoryHandle);
  rsh->exchange = exchange;
  rsh->cb = cb;
  rsh->cb_cls = cb_cls;
  rsh->ts = GNUNET_TIME_timestamp_get ();
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
                     "/reserves/%s/history",
                     pub_str);
  }
  rsh->url = TEAH_path_to_url (exchange,
                               arg_str);
  if (NULL == rsh->url)
  {
    GNUNET_free (rsh);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (rsh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (rsh->url);
    GNUNET_free (rsh);
    return NULL;
  }
  keys = TALER_EXCHANGE_get_keys (exchange);
  if (NULL == keys)
  {
    GNUNET_break (0);
    GNUNET_free (rsh->url);
    GNUNET_free (rsh);
    return NULL;
  }
  gf = TALER_EXCHANGE_get_global_fee (keys,
                                      rsh->ts);
  if (NULL == gf)
  {
    GNUNET_break_op (0);
    GNUNET_free (rsh->url);
    GNUNET_free (rsh);
    return NULL;
  }
  TALER_wallet_reserve_history_sign (rsh->ts,
                                     &gf->fees.history,
                                     reserve_priv,
                                     &rsh->reserve_sig);
  {
    json_t *history_obj = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_timestamp ("request_timestamp",
                                  rsh->ts),
      GNUNET_JSON_pack_data_auto ("reserve_sig",
                                  &rsh->reserve_sig));

    if (GNUNET_OK !=
        TALER_curl_easy_post (&rsh->post_ctx,
                              eh,
                              history_obj))
    {
      GNUNET_break (0);
      curl_easy_cleanup (eh);
      json_decref (history_obj);
      GNUNET_free (rsh->url);
      GNUNET_free (rsh);
      return NULL;
    }
    json_decref (history_obj);
  }
  ctx = TEAH_handle_to_context (exchange);
  rsh->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   rsh->post_ctx.headers,
                                   &handle_reserves_history_finished,
                                   rsh);
  return rsh;
}


void
TALER_EXCHANGE_reserves_history_cancel (
  struct TALER_EXCHANGE_ReservesHistoryHandle *rsh)
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


/* end of exchange_api_reserves_history.c */
