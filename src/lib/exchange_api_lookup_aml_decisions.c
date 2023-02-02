/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file lib/exchange_api_lookup_aml_decisions.c
 * @brief Implementation of the /aml/$OFFICER_PUB/decisions request
 * @author Christian Grothoff
 */
#include "platform.h"
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A /coins/$COIN_PUB/link Handle
 */
struct TALER_EXCHANGE_LookupAmlDecisions
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
  TALER_EXCHANGE_LookupAmlDecisionsCallback decisions_cb;

  /**
   * Closure for @e cb.
   */
  void *decisions_cb_cls;

  /**
   * HTTP headers for the job.
   */
  struct curl_slist *job_headers;
};


/**
 * Parse the provided decision data from the "200 OK" response.
 *
 * @param[in,out] lh handle (callback may be zero'ed out)
 * @param json json reply with the data for one coin
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static enum GNUNET_GenericReturnValue
parse_decisions_ok (struct TALER_EXCHANGE_LookupAmlDecisions *lh,
                    const json_t *json)
{
  struct TALER_EXCHANGE_AmlDecisionsResponse lr = {
    .hr.reply = json,
    .hr.http_status = MHD_HTTP_OK
  };
  int ret = GNUNET_SYSERR;

  GNUNET_break (0); // FIXME: parse response!
  return ret;
}


/**
 * Function called when we're done processing the
 * HTTP /aml/$OFFICER_PUB/decisions request.
 *
 * @param cls the `struct TALER_EXCHANGE_LookupAmlDecisions`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_lookup_finished (void *cls,
                        long response_code,
                        const void *response)
{
  struct TALER_EXCHANGE_LookupAmlDecisions *lh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_AmlDecisionsResponse lr = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  lh->job = NULL;
  switch (response_code)
  {
  case 0:
    lr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        parse_decisions_ok (lh,
                            j))
    {
      GNUNET_break_op (0);
      lr.hr.http_status = 0;
      lr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
      break;
    }
    GNUNET_assert (NULL == lh->decisions_cb);
    TALER_EXCHANGE_lookup_aml_decisions_cancel (lh);
    return;
  case MHD_HTTP_BAD_REQUEST:
    lr.hr.ec = TALER_JSON_get_error_code (j);
    lr.hr.hint = TALER_JSON_get_error_hint (j);
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    lr.hr.ec = TALER_JSON_get_error_code (j);
    lr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Nothing really to verify, exchange says this coin was not melted; we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    lr.hr.ec = TALER_JSON_get_error_code (j);
    lr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    lr.hr.ec = TALER_JSON_get_error_code (j);
    lr.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange link\n",
                (unsigned int) response_code,
                (int) lr.hr.ec);
    break;
  }
  if (NULL != lh->decisions_cb)
    lh->decisions_cb (lh->decisions_cb_cls,
                      &lr);
  TALER_EXCHANGE_lookup_aml_decisions_cancel (lh);
}


struct TALER_EXCHANGE_LookupAmlDecisions *
TALER_EXCHANGE_lookup_aml_decisions (
  struct GNUNET_CURL_Context *ctx,
  const char *exchange_url,
  uint64_t start,
  int delta,
  bool filter_frozen,
  bool filter_pending,
  bool filter_normal,
  const struct TALER_AmlOfficerPrivateKeyP *officer_priv,
  TALER_EXCHANGE_LookupAmlDecisionsCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_LookupAmlDecisions *lh;
  CURL *eh;
  struct TALER_AmlOfficerPublicKeyP officer_pub;
  struct TALER_AmlOfficerSignatureP officer_sig;
  char arg_str[sizeof (struct TALER_AmlOfficerPublicKeyP) * 2 + 32];

  GNUNET_CRYPTO_eddsa_key_get_public (&officer_priv->eddsa_priv,
                                      &officer_pub.eddsa_pub);
  TALER_officer_aml_query_sign (officer_priv,
                                &officer_sig);
  {
    char pub_str[sizeof (officer_pub) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &officer_pub,
      sizeof (officer_pub),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/aml/%s/decisions",
                     pub_str);
  }
  lh = GNUNET_new (struct TALER_EXCHANGE_LookupAmlDecisions);
  lh->decisions_cb = cb;
  lh->decisions_cb_cls = cb_cls;
  lh->url = TALER_url_join (exchange_url,
                            arg_str,
                            "frozen",
                            filter_frozen ? "yes" : NULL,
                            "pending",
                            filter_pending ? "yes" : NULL,
                            "normal",
                            filter_normal ? "yes" : NULL,
                            NULL);
  if (NULL == lh->url)
  {
    GNUNET_free (lh);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (lh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (lh->url);
    GNUNET_free (lh);
    return NULL;
  }
  {
    char *hdr;
    char sig_str[sizeof (officer_sig) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &officer_sig,
      sizeof (officer_sig),
      sig_str,
      sizeof (sig_str));
    *end = '\0';

    GNUNET_asprintf (&hdr,
                     "%s: %s",
                     TALER_AML_OFFICER_SIGNATURE_HEADER,
                     sig_str);
    lh->job_headers = curl_slist_append (NULL,
                                         hdr);
    GNUNET_free (hdr);
    lh->job_headers = curl_slist_append (lh->job_headers,
                                         "Content-type: application/json");
    lh->job = GNUNET_CURL_job_add2 (ctx,
                                    eh,
                                    lh->job_headers,
                                    &handle_lookup_finished,
                                    lh);
  }
  return lh;
}


void
TALER_EXCHANGE_lookup_aml_decisions_cancel (
  struct TALER_EXCHANGE_LookupAmlDecisions *lh)
{
  if (NULL != lh->job)
  {
    GNUNET_CURL_job_cancel (lh->job);
    lh->job = NULL;
  }
  curl_slist_free_all (lh->job_headers);
  GNUNET_free (lh->url);
  GNUNET_free (lh);
}


/* end of exchange_api_lookup_aml_decisions.c */
