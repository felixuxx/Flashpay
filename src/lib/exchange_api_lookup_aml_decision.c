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
 * @file lib/exchange_api_lookup_aml_decision.c
 * @brief Implementation of the /aml/$OFFICER_PUB/decision request
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
struct TALER_EXCHANGE_LookupAmlDecision
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
  TALER_EXCHANGE_LookupAmlDecisionCallback decision_cb;

  /**
   * Closure for @e cb.
   */
  void *decision_cb_cls;

  /**
   * HTTP headers for the job.
   */
  struct curl_slist *job_headers;
};


/**
 * Parse AML decision history.
 *
 * @param aml_history JSON array with AML history
 * @param[out] aml_history_ar where to write the result
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_aml_history (const json_t *aml_history,
                   struct TALER_EXCHANGE_AmlDecisionDetail *aml_history_ar)
{
  json_t *obj;
  size_t idx;

  json_array_foreach (aml_history, idx, obj)
  {
    struct TALER_EXCHANGE_AmlDecisionDetail *aml = &aml_history_ar[idx];
    uint32_t state32;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_timestamp ("decision_time",
                                  &aml->decision_time),
      GNUNET_JSON_spec_string ("justification",
                               &aml->justification),
      GNUNET_JSON_spec_uint32 ("new_state",
                               &state32),
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
    aml->new_state = (enum TALER_AmlDecisionState) state32;
  }
  return GNUNET_OK;
}


/**
 * Parse KYC response array.
 *
 * @param kyc_attributes JSON array with KYC details
 * @param[out] kyc_attributes_ar where to write the result
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_kyc_attributes (const json_t *kyc_attributes,
                      struct TALER_EXCHANGE_KycHistoryDetail *kyc_attributes_ar)
{
  json_t *obj;
  size_t idx;

  json_array_foreach (kyc_attributes, idx, obj)
  {
    struct TALER_EXCHANGE_KycHistoryDetail *kyc = &kyc_attributes_ar[idx];
    json_t *attributes = NULL;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_timestamp ("collection_time",
                                  &kyc->collection_time),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_json ("attributes",
                               &attributes),
        NULL),
      GNUNET_JSON_spec_string ("provider_section",
                               &kyc->provider_section),
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
    kyc->attributes = attributes;
    json_decref (attributes); /* this is OK, RC preserved via 'kyc_attributes' as long as needed! */
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
parse_decision_ok (struct TALER_EXCHANGE_LookupAmlDecision *lh,
                   const json_t *json)
{
  struct TALER_EXCHANGE_AmlDecisionResponse lr = {
    .hr.reply = json,
    .hr.http_status = MHD_HTTP_OK
  };
  json_t *aml_history;
  json_t *kyc_attributes;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("aml_history",
                           &aml_history),
    GNUNET_JSON_spec_json ("kyc_attributes",
                           &kyc_attributes),
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
  lr.details.success.aml_history_length = json_array_size (aml_history);
  lr.details.success.kyc_attributes_length = json_array_size (kyc_attributes);
  {
    struct TALER_EXCHANGE_AmlDecisionDetail aml_history_ar[
      GNUNET_NZL (lr.details.success.aml_history_length)];
    struct TALER_EXCHANGE_KycHistoryDetail kyc_attributes_ar[
      lr.details.success.kyc_attributes_length];
    enum GNUNET_GenericReturnValue ret = GNUNET_SYSERR;

    lr.details.success.aml_history = aml_history_ar;
    lr.details.success.kyc_attributes = kyc_attributes_ar;
    ret = parse_aml_history (aml_history,
                             aml_history_ar);
    if (GNUNET_OK == ret)
      ret = parse_kyc_attributes (kyc_attributes,
                                  kyc_attributes_ar);
    if (GNUNET_OK == ret)
    {
      lh->decision_cb (lh->decision_cb_cls,
                       &lr);
      lh->decision_cb = NULL;
    }
    return ret;
  }
}


/**
 * Function called when we're done processing the
 * HTTP /aml/$OFFICER_PUB/decision request.
 *
 * @param cls the `struct TALER_EXCHANGE_LookupAmlDecision`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_lookup_finished (void *cls,
                        long response_code,
                        const void *response)
{
  struct TALER_EXCHANGE_LookupAmlDecision *lh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_AmlDecisionResponse lr = {
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
        parse_decision_ok (lh,
                           j))
    {
      GNUNET_break_op (0);
      lr.hr.http_status = 0;
      lr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
      break;
    }
    GNUNET_assert (NULL == lh->decision_cb);
    TALER_EXCHANGE_lookup_aml_decision_cancel (lh);
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
  if (NULL != lh->decision_cb)
    lh->decision_cb (lh->decision_cb_cls,
                     &lr);
  TALER_EXCHANGE_lookup_aml_decision_cancel (lh);
}


struct TALER_EXCHANGE_LookupAmlDecision *
TALER_EXCHANGE_lookup_aml_decision (
  struct GNUNET_CURL_Context *ctx,
  const char *exchange_url,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_AmlOfficerPrivateKeyP *officer_priv,
  bool history,
  TALER_EXCHANGE_LookupAmlDecisionCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_LookupAmlDecision *lh;
  CURL *eh;
  struct TALER_AmlOfficerPublicKeyP officer_pub;
  struct TALER_AmlOfficerSignatureP officer_sig;
  char arg_str[sizeof (officer_pub) * 2
               + sizeof (*h_payto) * 2 + 32];

  GNUNET_CRYPTO_eddsa_key_get_public (&officer_priv->eddsa_priv,
                                      &officer_pub.eddsa_pub);
  TALER_officer_aml_query_sign (officer_priv,
                                &officer_sig);
  {
    char pub_str[sizeof (officer_pub) * 2];
    char pt_str[sizeof (*h_payto) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &officer_pub,
      sizeof (officer_pub),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    end = GNUNET_STRINGS_data_to_string (
      h_payto,
      sizeof (*h_payto),
      pt_str,
      sizeof (pt_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/aml/%s/decision/%s",
                     pub_str,
                     pt_str);
  }
  lh = GNUNET_new (struct TALER_EXCHANGE_LookupAmlDecision);
  lh->decision_cb = cb;
  lh->decision_cb_cls = cb_cls;
  lh->url = TALER_url_join (exchange_url,
                            arg_str,
                            "history",
                            history
                            ? "true"
                            : NULL,
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
TALER_EXCHANGE_lookup_aml_decision_cancel (
  struct TALER_EXCHANGE_LookupAmlDecision *lh)
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


/* end of exchange_api_lookup_aml_decision.c */
