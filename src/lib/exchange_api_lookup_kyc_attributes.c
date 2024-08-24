/*
  This file is part of TALER
  Copyright (C) 2023, 2024 Taler Systems SA

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
 * @file lib/exchange_api_lookup_kyc_attributes.c
 * @brief Implementation of the /aml/$OFFICER_PUB/attributes request
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
 * @brief A GET /aml/$OFFICER_PUB/attributes Handle
 */
struct TALER_EXCHANGE_LookupKycAttributes
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
  TALER_EXCHANGE_LookupKycAttributesCallback attributes_cb;

  /**
   * Closure for @e cb.
   */
  void *attributes_cb_cls;

  /**
   * HTTP headers for the job.
   */
  struct curl_slist *job_headers;

};


/**
 * Parse AML decision summary array.
 *
 * @param[in,out] lh handle to use for allocations
 * @param jdetails JSON array with AML decision summaries
 * @param[out] detail_ar where to write the result
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_kyc_attributes (
  struct TALER_EXCHANGE_LookupKycAttributes *lh,
  const json_t *jdetails,
  struct TALER_EXCHANGE_KycAttributeDetail *detail_ar)
{
  json_t *obj;
  size_t idx;

  json_array_foreach (jdetails, idx, obj)
  {
    struct TALER_EXCHANGE_KycAttributeDetail *detail
      = &detail_ar[idx];
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_uint64 ("rowid",
                               &detail->row_id),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_string ("provider_name",
                                 &detail->provider_name),
        NULL),
      GNUNET_JSON_spec_object_const ("attributes",
                                     &detail->attributes),
      GNUNET_JSON_spec_timestamp ("collection_time",
                                  &detail->collection_time),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (obj,
                           spec,
                           NULL,
                           NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
}


/**
 * Parse the provided decision data from the "200 OK" response.
 *
 * @param[in,out] lh handle (callback may be zero'ed out)
 * @param json json reply with the data for one coin
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static enum GNUNET_GenericReturnValue
parse_attributes_ok (struct TALER_EXCHANGE_LookupKycAttributes *lh,
                     const json_t *json)
{
  struct TALER_EXCHANGE_KycAttributesResponse lr = {
    .hr.reply = json,
    .hr.http_status = MHD_HTTP_OK
  };
  const json_t *jdetails;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_array_const ("details",
                                  &jdetails),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL,
                         NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  lr.details.ok.kyc_attributes_length
    = json_array_size (jdetails);
  {
    struct TALER_EXCHANGE_KycAttributeDetail details[
      GNUNET_NZL (lr.details.ok.kyc_attributes_length)];
    enum GNUNET_GenericReturnValue ret = GNUNET_SYSERR;

    memset (details,
            0,
            sizeof (details));
    lr.details.ok.kyc_attributes = details;
    ret = parse_kyc_attributes (lh,
                                jdetails,
                                details);
    if (GNUNET_OK == ret)
    {
      lh->attributes_cb (lh->attributes_cb_cls,
                         &lr);
      lh->attributes_cb = NULL;
    }
    return ret;
  }
}


/**
 * Function called when we're done processing the
 * HTTP /aml/$OFFICER_PUB/attributes request.
 *
 * @param cls the `struct TALER_EXCHANGE_LookupKycAttributes`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_lookup_finished (void *cls,
                        long response_code,
                        const void *response)
{
  struct TALER_EXCHANGE_LookupKycAttributes *lh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_KycAttributesResponse lr = {
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
        parse_attributes_ok (lh,
                             j))
    {
      GNUNET_break_op (0);
      lr.hr.http_status = 0;
      lr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
      break;
    }
    GNUNET_assert (NULL == lh->attributes_cb);
    TALER_EXCHANGE_lookup_kyc_attributes_cancel (lh);
    return;
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_BAD_REQUEST:
    lr.hr.ec = TALER_JSON_get_error_code (j);
    lr.hr.hint = TALER_JSON_get_error_hint (j);
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    lr.hr.ec = TALER_JSON_get_error_code (j);
    lr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Nothing really to verify, exchange says this coin was not melted; we
       should pass the JSON reply to the application */
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
                "Unexpected response code %u/%d for lookup AML attributes\n",
                (unsigned int) response_code,
                (int) lr.hr.ec);
    break;
  }
  if (NULL != lh->attributes_cb)
    lh->attributes_cb (lh->attributes_cb_cls,
                       &lr);
  TALER_EXCHANGE_lookup_kyc_attributes_cancel (lh);
}


struct TALER_EXCHANGE_LookupKycAttributes *
TALER_EXCHANGE_lookup_kyc_attributes (
  struct GNUNET_CURL_Context *ctx,
  const char *exchange_url,
  const struct TALER_PaytoHashP *h_payto,
  uint64_t offset,
  int64_t limit,
  const struct TALER_AmlOfficerPrivateKeyP *officer_priv,
  TALER_EXCHANGE_LookupKycAttributesCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_LookupKycAttributes *lh;
  CURL *eh;
  struct TALER_AmlOfficerPublicKeyP officer_pub;
  struct TALER_AmlOfficerSignatureP officer_sig;
  char arg_str[sizeof (struct TALER_AmlOfficerPublicKeyP) * 2
               + sizeof (struct TALER_PaytoHashP) * 2
               + 32];

  GNUNET_CRYPTO_eddsa_key_get_public (&officer_priv->eddsa_priv,
                                      &officer_pub.eddsa_pub);
  TALER_officer_aml_query_sign (officer_priv,
                                &officer_sig);

  {
    char payto_s[sizeof (*h_payto) * 2];
    char pub_str[sizeof (officer_pub) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      h_payto,
      sizeof (*h_payto),
      payto_s,
      sizeof (payto_s));
    *end = '\0';
    end = GNUNET_STRINGS_data_to_string (
      &officer_pub,
      sizeof (officer_pub),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "aml/%s/attributes/%s",
                     pub_str,
                     payto_s);
  }
  lh = GNUNET_new (struct TALER_EXCHANGE_LookupKycAttributes);
  lh->attributes_cb = cb;
  lh->attributes_cb_cls = cb_cls;
  {
    char limit_s[24];
    char offset_s[24];

    GNUNET_snprintf (limit_s,
                     sizeof (limit_s),
                     "%lld",
                     (long long) limit);
    GNUNET_snprintf (offset_s,
                     sizeof (offset_s),
                     "%llu",
                     (unsigned long long) offset);
    lh->url = TALER_url_join (
      exchange_url,
      arg_str,
      "limit",
      limit_s,
      "offset",
      offset_s,
      "h_payto",
      NULL);
  }
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
TALER_EXCHANGE_lookup_kyc_attributes_cancel (
  struct TALER_EXCHANGE_LookupKycAttributes *lh)
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


/* end of exchange_api_lookup_kyc_attributes.c */
