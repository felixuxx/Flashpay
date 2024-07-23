/*
  This file is part of TALER
  Copyright (C) 2021-2024 Taler Systems SA

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
 * @file lib/exchange_api_kyc_check.c
 * @brief Implementation of the /kyc-check request
 * @author Christian Grothoff
 */
#include "platform.h"
#include <microhttpd.h> /* just for HTTP check codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A ``/kyc-check`` handle
 */
struct TALER_EXCHANGE_KycCheckHandle
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
  TALER_EXCHANGE_KycStatusCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

};


static enum GNUNET_GenericReturnValue
parse_account_status (struct TALER_EXCHANGE_KycCheckHandle *kch,
                      const json_t *j,
                      struct TALER_EXCHANGE_KycStatus *ks,
                      struct TALER_EXCHANGE_AccountKycStatus *aks)
{
  const json_t *limits = NULL;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_bool ("aml_review",
                           &aks->aml_review),
    GNUNET_JSON_spec_fixed_auto ("access_token",
                                 &aks->access_token),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_array_const ("limits",
                                    &limits),
      NULL),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (j,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if ( (NULL != limits) &&
       (0 != json_array_size (limits)) )
  {
    size_t als = json_array_size (limits);
    struct TALER_EXCHANGE_AccountLimit ala[GNUNET_NZL (als)];
    size_t i;
    json_t *limit;

    json_array_foreach (limits, i, limit)
    {
      struct TALER_EXCHANGE_AccountLimit *al = &ala[i];
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_bool ("soft_limit",
                               &al->soft_limit),
        GNUNET_JSON_spec_relative_time ("timeframe",
                                        &al->timeframe),
        TALER_JSON_spec_kycte ("operation_type",
                               &al->operation_type),
        TALER_JSON_spec_amount_any ("threshold",
                                    &al->threshold),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (limit,
                             ispec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
    }
    aks->limits = ala;
    aks->limits_length = als;
    kch->cb (kch->cb_cls,
             ks);
  }
  else
  {
    kch->cb (kch->cb_cls,
             ks);
  }
  GNUNET_JSON_parse_free (spec);
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /kyc-check request.
 *
 * @param cls the `struct TALER_EXCHANGE_KycCheckHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_kyc_check_finished (void *cls,
                           long response_code,
                           const void *response)
{
  struct TALER_EXCHANGE_KycCheckHandle *kch = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_KycStatus ks = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  kch->job = NULL;
  switch (response_code)
  {
  case 0:
    ks.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      if (GNUNET_OK !=
          parse_account_status (kch,
                                j,
                                &ks,
                                &ks.details.ok))
      {
        GNUNET_break_op (0);
        ks.hr.http_status = 0;
        ks.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
        break;
      }
      TALER_EXCHANGE_kyc_check_cancel (kch);
      return;
    }
  case MHD_HTTP_ACCEPTED:
    {
      if (GNUNET_OK !=
          parse_account_status (kch,
                                j,
                                &ks,
                                &ks.details.accepted))
      {
        GNUNET_break_op (0);
        ks.hr.http_status = 0;
        ks.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
        break;
      }
      TALER_EXCHANGE_kyc_check_cancel (kch);
      return;
    }
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_BAD_REQUEST:
    ks.hr.ec = TALER_JSON_get_error_code (j);
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    ks.hr.ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    ks.hr.ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_CONFLICT:
    ks.hr.ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    ks.hr.ec = TALER_JSON_get_error_code (j);
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    ks.hr.ec = TALER_JSON_get_error_code (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange kyc_check\n",
                (unsigned int) response_code,
                (int) ks.hr.ec);
    break;
  }
  kch->cb (kch->cb_cls,
           &ks);
  TALER_EXCHANGE_kyc_check_cancel (kch);
}


struct TALER_EXCHANGE_KycCheckHandle *
TALER_EXCHANGE_kyc_check (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  uint64_t requirement_row,
  const union TALER_AccountPrivateKeyP *account_priv,
  struct GNUNET_TIME_Relative timeout,
  TALER_EXCHANGE_KycStatusCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_KycCheckHandle *kch;
  CURL *eh;
  char arg_str[128];
  struct curl_slist *job_headers = NULL;
  unsigned long long tms;

  tms = timeout.rel_value_us
        / GNUNET_TIME_UNIT_MILLISECONDS.rel_value_us;
  if (0 != tms)
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "kyc-check/%llu?timeout_ms=%llu",
                     (unsigned long long) requirement_row,
                     tms);
  else
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "kyc-check/%llu",
                     (unsigned long long) requirement_row);
  kch = GNUNET_new (struct TALER_EXCHANGE_KycCheckHandle);
  kch->cb = cb;
  kch->cb_cls = cb_cls;
  kch->url = TALER_url_join (url,
                             arg_str,
                             NULL);
  if (NULL == kch->url)
  {
    GNUNET_free (kch);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (kch->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (kch->url);
    GNUNET_free (kch);
    return NULL;
  }
  if (0 != tms)
  {
    GNUNET_break (CURLE_OK ==
                  curl_easy_setopt (eh,
                                    CURLOPT_TIMEOUT_MS,
                                    (long) (tms + 500L)));
  }
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_VERBOSE,
                                  1L));

  job_headers = curl_slist_append (job_headers,
                                   "Content-Type: application/json");
  {
    union TALER_AccountSignatureP account_sig;
    char *sig_hdr;
    char *hdr;

    TALER_account_kyc_auth_sign (account_priv,
                                 &account_sig);

    sig_hdr = GNUNET_STRINGS_data_to_string_alloc (
      &account_sig,
      sizeof (account_sig));
    GNUNET_asprintf (&hdr,
                     "%s: %s",
                     TALER_HTTP_HEADER_ACCOUNT_OWNER_SIGNATURE,
                     sig_hdr);
    GNUNET_free (sig_hdr);
    job_headers = curl_slist_append (job_headers,
                                     hdr);
    GNUNET_free (hdr);
    if (NULL == job_headers)
    {
      GNUNET_break (0);
      curl_easy_cleanup (eh);
      return NULL;
    }
  }
  kch->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   job_headers,
                                   &handle_kyc_check_finished,
                                   kch);
  curl_slist_free_all (job_headers);
  return kch;
}


void
TALER_EXCHANGE_kyc_check_cancel (struct TALER_EXCHANGE_KycCheckHandle *kch)
{
  if (NULL != kch->job)
  {
    GNUNET_CURL_job_cancel (kch->job);
    kch->job = NULL;
  }
  GNUNET_free (kch->url);
  GNUNET_free (kch);
}


/* end of exchange_api_kyc_check.c */
