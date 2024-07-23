/*
  This file is part of TALER
  Copyright (C) 2015-2023 Taler Systems SA

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
 * @file lib/exchange_api_kyc_info.c
 * @brief Implementation of the /kyc-info/$AT request
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
 * @brief A /kyc-info Handle
 */
struct TALER_EXCHANGE_KycInfoHandle
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
  TALER_EXCHANGE_KycInfoCallback kyc_info_cb;

  /**
   * Closure for @e cb.
   */
  void *kyc_info_cb_cls;

};


/**
 * Parse the provided kyc_infoage data from the "200 OK" response
 * for one of the coins.
 *
 * @param[in,out] lh kyc_info handle (callback may be zero'ed out)
 * @param json json reply with the data for one coin
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static enum GNUNET_GenericReturnValue
parse_kyc_info_ok (struct TALER_EXCHANGE_KycInfoHandle *lh,
                   const json_t *json)
{
  const json_t *jrequirements = NULL;
  const json_t *jvoluntary_checks = NULL;
  struct TALER_EXCHANGE_KycProcessClientInformation lr = {
    .hr.reply = json,
    .hr.http_status = MHD_HTTP_OK
  };
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_array_const ("requirements",
                                  &jrequirements),
    GNUNET_JSON_spec_bool ("is_and_combinator",
                           &lr.details.ok.is_and_combinator),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_object_const ("voluntary_checks",
                                     &jvoluntary_checks),
      NULL),
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

  lr.details.ok.vci_length
    = (unsigned int) json_object_size (jvoluntary_checks);
  if ( ((size_t) lr.details.ok.vci_length)
       != json_object_size (jvoluntary_checks))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  lr.details.ok.requirements_length
    = json_array_size (jrequirements);
  if ( ((size_t) lr.details.ok.requirements_length)
       != json_array_size (jrequirements))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  {
    struct TALER_EXCHANGE_VoluntaryCheckInformation vci[
      GNUNET_NZL (lr.details.ok.vci_length)];
    struct TALER_EXCHANGE_RequirementInformation requirements[
      GNUNET_NZL (lr.details.ok.requirements_length)];
    const char *name;
    const json_t *jreq;
    const json_t *jvc;
    size_t off;

    memset (vci,
            0,
            sizeof (vci));
    memset (requirements,
            0,
            sizeof (requirements));

    json_array_foreach ((json_t *) jrequirements, off, jreq)
    {
      struct TALER_EXCHANGE_RequirementInformation *req = &requirements[off];
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_string ("form",
                                 &req->form),
        GNUNET_JSON_spec_string ("description",
                                 &req->description),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_object_const ("description_i18n",
                                         &req->description_i18n),
          NULL),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_string ("id",
                                   &req->id),
          NULL),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (jreq,
                             ispec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
    }
    GNUNET_assert (off == lr.details.ok.requirements_length);

    off = 0;
    json_object_foreach ((json_t *) jvoluntary_checks, name, jvc)
    {
      struct TALER_EXCHANGE_VoluntaryCheckInformation *vc = &vci[off++];
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_string ("description",
                                 &vc->description),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_object_const ("description_i18n",
                                         &vc->description_i18n),
          NULL),
        GNUNET_JSON_spec_end ()
      };

      vc->name = name;
      if (GNUNET_OK !=
          GNUNET_JSON_parse (jvc,
                             ispec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
    }
    GNUNET_assert (off == lr.details.ok.vci_length);

    lr.details.ok.vci = vci;
    lr.details.ok.requirements = requirements;
    lh->kyc_info_cb (lh->kyc_info_cb_cls,
                     &lr);
    lh->kyc_info_cb = NULL;
    return GNUNET_OK;
  }
}


/**
 * Function called when we're done processing the
 * HTTP /kyc-info/$AT request.
 *
 * @param cls the `struct TALER_EXCHANGE_KycInfoHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_kyc_info_finished (void *cls,
                          long response_code,
                          const void *response)
{
  struct TALER_EXCHANGE_KycInfoHandle *lh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_KycProcessClientInformation lr = {
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
        parse_kyc_info_ok (lh,
                           j))
    {
      GNUNET_break_op (0);
      lr.hr.http_status = 0;
      lr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
      break;
    }
    GNUNET_assert (NULL == lh->kyc_info_cb);
    TALER_EXCHANGE_kyc_info_cancel (lh);
    return;
  case MHD_HTTP_NO_CONTENT:
    break;
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
                "Unexpected response code %u/%d for exchange /kyc-info\n",
                (unsigned int) response_code,
                (int) lr.hr.ec);
    break;
  }
  if (NULL != lh->kyc_info_cb)
    lh->kyc_info_cb (lh->kyc_info_cb_cls,
                     &lr);
  TALER_EXCHANGE_kyc_info_cancel (lh);
}


struct TALER_EXCHANGE_KycInfoHandle *
TALER_EXCHANGE_kyc_info (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_AccountAccessTokenP *token,
  const char *if_none_match,
  struct GNUNET_TIME_Relative timeout,
  TALER_EXCHANGE_KycInfoCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_KycInfoHandle *lh;
  CURL *eh;
  char arg_str[sizeof (struct TALER_AccountAccessTokenP) * 2 + 32];
  unsigned int tms
    = (unsigned int) timeout.rel_value_us
      / GNUNET_TIME_UNIT_MILLISECONDS.rel_value_us;
  struct curl_slist *job_headers = NULL;

  {
    char at_str[sizeof (struct TALER_AccountAccessTokenP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      token,
      sizeof (*token),
      at_str,
      sizeof (at_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "kyc-info/%s",
                     at_str);
  }
  lh = GNUNET_new (struct TALER_EXCHANGE_KycInfoHandle);
  lh->kyc_info_cb = cb;
  lh->kyc_info_cb_cls = cb_cls;
  {
    char timeout_str[32];

    GNUNET_snprintf (timeout_str,
                     sizeof (timeout_str),
                     "%u",
                     tms);
    lh->url = TALER_url_join (url,
                              arg_str,
                              "timeout_ms",
                              (0 == tms)
                              ? NULL
                              : timeout_str,
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
  if (0 != tms)
  {
    GNUNET_break (CURLE_OK ==
                  curl_easy_setopt (eh,
                                    CURLOPT_TIMEOUT_MS,
                                    (long) (tms + 100L)));
  }

  job_headers = curl_slist_append (job_headers,
                                   "Content-Type: application/json");
  if (NULL != if_none_match)
  {
    char *hdr;

    GNUNET_asprintf (&hdr,
                     "%s: %s",
                     MHD_HTTP_HEADER_IF_NONE_MATCH,
                     if_none_match);
    job_headers = curl_slist_append (job_headers,
                                     hdr);
    GNUNET_free (hdr);
  }
  lh->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  job_headers,
                                  &handle_kyc_info_finished,
                                  lh);
  curl_slist_free_all (job_headers);
  return lh;
}


void
TALER_EXCHANGE_kyc_info_cancel (struct TALER_EXCHANGE_KycInfoHandle *lh)
{
  if (NULL != lh->job)
  {
    GNUNET_CURL_job_cancel (lh->job);
    lh->job = NULL;
  }

  GNUNET_free (lh->url);
  GNUNET_free (lh);
}


/* end of exchange_api_kyc_info.c */
