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
 * @brief A GET /aml/$OFFICER_PUB/decisions Handle
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

  /**
   * Array with measure information.
   */
  struct TALER_EXCHANGE_MeasureInformation *mip;

  /**
   * Array with rule information.
   */
  struct TALER_EXCHANGE_KycRule *rp;

  /**
   * Array with all the measures (of all the rules!).
   */
  const char **mp;
};


/**
 * Parse AML limits array.
 *
 * @param[in,out] lh handle to use for allocations
 * @param jlimits JSON array with AML rules
 * @param[out] ds where to write the result
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_limits (struct TALER_EXCHANGE_LookupAmlDecisions *lh,
              const json_t *jlimits,
              struct TALER_EXCHANGE_AmlDecision *ds)
{
  struct TALER_EXCHANGE_LegitimizationRuleSet *limits
    = &ds->limits;
  const json_t *jrules;
  const json_t *jmeasures;
  size_t mip_len;
  size_t rule_len;
  size_t total;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_timestamp ("expiration_time",
                                &limits->expiration_time),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_string ("successor_measure",
                               &limits->successor_measure),
      NULL),
    GNUNET_JSON_spec_array_const ("rules",
                                  &jrules),
    GNUNET_JSON_spec_object_const ("custom_measures",
                                   &jmeasures),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (jlimits,
                         spec,
                         NULL,
                         NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  mip_len = json_object_size (jmeasures);
  lh->mip = GNUNET_new_array (mip_len,
                              struct TALER_EXCHANGE_MeasureInformation);
  limits->measures = lh->mip;
  limits->measures_length = mip_len;

  {
    const char *measure_name;
    const json_t *jmeasure;

    json_object_foreach ((json_t*) jmeasures,
                         measure_name,
                         jmeasure)
    {
      struct TALER_EXCHANGE_MeasureInformation *mi
        = &lh->mip[--mip_len];
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_string ("check_name",
                                 &mi->check_name),
        GNUNET_JSON_spec_string ("prog_name",
                                 &mi->prog_name),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_object_const ("context",
                                         &mi->context),
          NULL),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (jmeasure,
                             ispec,
                             NULL,
                             NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      mi->measure_name = measure_name;
    }
  }

  total = 0;

  {
    const json_t *rule;
    size_t idx;

    json_array_foreach ((json_t *) jrules,
                        idx,
                        rule)
    {
      total += json_array_size (json_object_get (rule,
                                                 "measures"));
    }
  }

  rule_len = json_array_size (jrules);
  lh->rp = GNUNET_new_array (rule_len,
                             struct TALER_EXCHANGE_KycRule);
  lh->mp = GNUNET_new_array (total,
                             const char *);

  {
    const json_t *rule;
    size_t idx;

    json_array_foreach ((json_t *) jrules,
                        idx,
                        rule)
    {
      const json_t *smeasures;
      struct TALER_EXCHANGE_KycRule *r
        = &lh->rp[--rule_len];
      struct GNUNET_JSON_Specification ispec[] = {
        TALER_JSON_spec_kycte ("operation_type",
                               &r->operation_type),
        TALER_JSON_spec_amount_any ("threshold",
                                    &r->threshold),
        GNUNET_JSON_spec_relative_time ("timeframe",
                                        &r->timeframe),
        GNUNET_JSON_spec_array_const ("measures",
                                      &smeasures),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_bool ("exposed",
                                 &r->exposed),
          NULL),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_bool ("is_and_combinator",
                                 &r->is_and_combinator),
          NULL),
        GNUNET_JSON_spec_uint32 ("display_priority",
                                 &r->display_priority),
        GNUNET_JSON_spec_end ()
      };
      size_t mlen;

      if (GNUNET_OK !=
          GNUNET_JSON_parse (rule,
                             ispec,
                             NULL,
                             NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }

      mlen = json_array_size (smeasures);
      GNUNET_assert (mlen <= total);
      total -= mlen;

      {
        size_t midx;
        const json_t *smeasure;

        json_array_foreach (smeasures,
                            midx,
                            smeasure)
        {
          const char *sval = json_string_value (smeasure);

          if (NULL == sval)
          {
            GNUNET_break_op (0);
            return GNUNET_SYSERR;
          }
          lh->mp[total + midx] = sval;
          if (0 == strcasecmp (sval,
                               "verboten"))
            r->verboten = true;
        }
      }
      r->measures = &lh->mp[total];
      r->measures_length = r->verboten ? 0 : total;
    }
  }
  return GNUNET_OK;
}


/**
 * Parse AML decision summary array.
 *
 * @param[in,out] lh handle to use for allocations
 * @param decisions JSON array with AML decision summaries
 * @param[out] decision_ar where to write the result
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_aml_decisions (
  struct TALER_EXCHANGE_LookupAmlDecisions *lh,
  const json_t *decisions,
  struct TALER_EXCHANGE_AmlDecision *decision_ar)
{
  json_t *obj;
  size_t idx;

  json_array_foreach (decisions, idx, obj)
  {
    struct TALER_EXCHANGE_AmlDecision *decision = &decision_ar[idx];
    const json_t *jlimits;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto ("h_payto",
                                   &decision->h_payto),
      GNUNET_JSON_spec_uint64 ("rowid",
                               &decision->rowid),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_string ("justification",
                                 &decision->justification),
        NULL),
      GNUNET_JSON_spec_timestamp ("decision_time",
                                  &decision->decision_time),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_object_const ("properties",
                                       &decision->jproperties),
        NULL),
      GNUNET_JSON_spec_object_const ("limits",
                                     &jlimits),
      GNUNET_JSON_spec_bool ("to_investigate",
                             &decision->to_investigate),
      GNUNET_JSON_spec_bool ("is_active",
                             &decision->is_active),
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
    if (GNUNET_OK !=
        parse_limits (lh,
                      jlimits,
                      decision))
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
parse_decisions_ok (struct TALER_EXCHANGE_LookupAmlDecisions *lh,
                    const json_t *json)
{
  struct TALER_EXCHANGE_AmlDecisionsResponse lr = {
    .hr.reply = json,
    .hr.http_status = MHD_HTTP_OK
  };
  const json_t *records;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_array_const ("records",
                                  &records),
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
  lr.details.ok.decisions_length
    = json_array_size (records);
  {
    struct TALER_EXCHANGE_AmlDecision decisions[
      GNUNET_NZL (lr.details.ok.decisions_length)];
    enum GNUNET_GenericReturnValue ret = GNUNET_SYSERR;

    memset (decisions,
            0,
            sizeof (decisions));
    lr.details.ok.decisions = decisions;
    ret = parse_aml_decisions (lh,
                               records,
                               decisions);
    if (GNUNET_OK == ret)
    {
      lh->decisions_cb (lh->decisions_cb_cls,
                        &lr);
      lh->decisions_cb = NULL;
    }
    GNUNET_free (lh->mip);
    GNUNET_free (lh->rp);
    GNUNET_free (lh->mp);
    return ret;
  }
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
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_BAD_REQUEST:
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
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
                "Unexpected response code %u/%d for lookup AML decisions\n",
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
  const struct TALER_NormalizedPaytoHashP *h_payto,
  enum TALER_EXCHANGE_YesNoAll investigation_only,
  enum TALER_EXCHANGE_YesNoAll active_only,
  uint64_t offset,
  int64_t limit,
  const struct TALER_AmlOfficerPrivateKeyP *officer_priv,
  TALER_EXCHANGE_LookupAmlDecisionsCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_LookupAmlDecisions *lh;
  CURL *eh;
  struct TALER_AmlOfficerPublicKeyP officer_pub;
  struct TALER_AmlOfficerSignatureP officer_sig;
  char arg_str[sizeof (struct TALER_AmlOfficerPublicKeyP) * 2
               + 32];

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
                     "aml/%s/decisions",
                     pub_str);
  }
  lh = GNUNET_new (struct TALER_EXCHANGE_LookupAmlDecisions);
  lh->decisions_cb = cb;
  lh->decisions_cb_cls = cb_cls;
  {
    char limit_s[24];
    char offset_s[24];
    char payto_s[sizeof (*h_payto) * 2];
    char *end;

    if (NULL != h_payto)
    {
      end = GNUNET_STRINGS_data_to_string (
        h_payto,
        sizeof (*h_payto),
        payto_s,
        sizeof (payto_s));
      *end = '\0';
    }
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
      ( ( (limit < 0) && (UINT64_MAX == offset) ) ||
        ( (limit > 0) && (0 == offset) ) )
      ? NULL
      : offset_s,
      "h_payto",
      NULL != h_payto
      ? payto_s
      : NULL,
      "active",
      TALER_EXCHANGE_YNA_ALL != active_only
      ? TALER_yna_to_string (active_only)
      : NULL,
      "investigation",
      TALER_EXCHANGE_YNA_ALL != investigation_only
      ? TALER_yna_to_string (investigation_only)
      : NULL,
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
