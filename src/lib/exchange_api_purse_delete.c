/*
   This file is part of TALER
   Copyright (C) 2022 Taler Systems SA

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
 * @file lib/exchange_api_purse_delete.c
 * @brief Implementation of the client to delete a purse
 *        into an account
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_json_lib.h"
#include "taler_exchange_service.h"
#include "exchange_api_handle.h"
#include "exchange_api_common.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A purse delete with deposit handle
 */
struct TALER_EXCHANGE_PurseDeleteHandle
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
   * Function to call with the result.
   */
  TALER_EXCHANGE_PurseDeleteCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Header with the purse_sig.
   */
  struct curl_slist *xhdr;
};


/**
 * Function called when we're done processing the
 * HTTP DELETE /purse/$PID request.
 *
 * @param cls the `struct TALER_EXCHANGE_PurseDeleteHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_purse_delete_finished (void *cls,
                              long response_code,
                              const void *response)
{
  struct TALER_EXCHANGE_PurseDeleteHandle *pdh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_PurseDeleteResponse dr = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  pdh->job = NULL;
  switch (response_code)
  {
  case 0:
    dr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_FORBIDDEN:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    break;
  case MHD_HTTP_CONFLICT:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange deposit\n",
                (unsigned int) response_code,
                dr.hr.ec);
    GNUNET_break_op (0);
    break;
  }
  pdh->cb (pdh->cb_cls,
           &dr);
  TALER_EXCHANGE_purse_delete_cancel (pdh);
}


struct TALER_EXCHANGE_PurseDeleteHandle *
TALER_EXCHANGE_purse_delete (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_PurseContractPrivateKeyP *purse_priv,
  TALER_EXCHANGE_PurseDeleteCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_PurseDeleteHandle *pdh;
  CURL *eh;
  struct TALER_PurseContractPublicKeyP purse_pub;
  struct TALER_PurseContractSignatureP purse_sig;
  char arg_str[sizeof (purse_pub) * 2 + 32];

  pdh = GNUNET_new (struct TALER_EXCHANGE_PurseDeleteHandle);
  pdh->cb = cb;
  pdh->cb_cls = cb_cls;
  GNUNET_CRYPTO_eddsa_key_get_public (&purse_priv->eddsa_priv,
                                      &purse_pub.eddsa_pub);
  {
    char pub_str[sizeof (purse_pub) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (&purse_pub,
                                         sizeof (purse_pub),
                                         pub_str,
                                         sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "purses/%s",
                     pub_str);
  }
  pdh->url = TALER_url_join (url,
                             arg_str,
                             NULL);
  if (NULL == pdh->url)
  {
    GNUNET_break (0);
    GNUNET_free (pdh);
    return NULL;
  }
  TALER_wallet_purse_delete_sign (purse_priv,
                                  &purse_sig);
  {
    char *delete_str;
    char *xhdr;

    delete_str =
      GNUNET_STRINGS_data_to_string_alloc (&purse_sig,
                                           sizeof (purse_sig));
    GNUNET_asprintf (&xhdr,
                     "Taler-Purse-Signature: %s",
                     delete_str);
    GNUNET_free (delete_str);
    pdh->xhdr = curl_slist_append (NULL,
                                   xhdr);
    GNUNET_free (xhdr);
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (pdh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    curl_slist_free_all (pdh->xhdr);
    GNUNET_free (pdh->url);
    GNUNET_free (pdh);
    return NULL;
  }
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_CUSTOMREQUEST,
                                   MHD_HTTP_METHOD_DELETE));
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "URL for purse delete: `%s'\n",
              pdh->url);
  pdh->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   pdh->xhdr,
                                   &handle_purse_delete_finished,
                                   pdh);
  return pdh;
}


void
TALER_EXCHANGE_purse_delete_cancel (
  struct TALER_EXCHANGE_PurseDeleteHandle *pdh)
{
  if (NULL != pdh->job)
  {
    GNUNET_CURL_job_cancel (pdh->job);
    pdh->job = NULL;
  }
  curl_slist_free_all (pdh->xhdr);
  GNUNET_free (pdh->url);
  GNUNET_free (pdh);
}


/* end of exchange_api_purse_delete.c */
