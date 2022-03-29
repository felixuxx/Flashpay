/*
  This file is part of TALER
  Copyright (C) 2021 Taler Systems SA

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
   * Function to call with the result.
   */
  TALER_EXCHANGE_KycStatusCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Hash of the payto:// URL that is being KYC'ed.
   */
  struct TALER_PaytoHashP h_payto;
};


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
    .http_status = (unsigned int) response_code
  };

  kch->job = NULL;
  switch (response_code)
  {
  case 0:
    ks.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &ks.details.kyc_ok.exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &ks.details.kyc_ok.exchange_pub),
        GNUNET_JSON_spec_timestamp ("now",
                                    &ks.details.kyc_ok.timestamp),
        GNUNET_JSON_spec_end ()
      };
      const struct TALER_EXCHANGE_Keys *key_state;

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        ks.http_status = 0;
        ks.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
        break;
      }
      key_state = TALER_EXCHANGE_get_keys (kch->exchange);
      if (GNUNET_OK !=
          TALER_EXCHANGE_test_signing_key (key_state,
                                           &ks.details.kyc_ok.exchange_pub))
      {
        GNUNET_break_op (0);
        ks.http_status = 0;
        ks.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
        GNUNET_JSON_parse_free (spec);
        break;
      }

      if (GNUNET_OK !=
          TALER_exchange_online_account_setup_success_verify (
            &kch->h_payto,
            ks.details.kyc_ok.timestamp,
            &ks.details.kyc_ok.exchange_pub,
            &ks.details.kyc_ok.exchange_sig))
      {
        GNUNET_break_op (0);
        ks.http_status = 0;
        ks.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
        GNUNET_JSON_parse_free (spec);
        break;
      }
      kch->cb (kch->cb_cls,
               &ks);
      GNUNET_JSON_parse_free (spec);
      TALER_EXCHANGE_kyc_check_cancel (kch);
      return;
    }
  case MHD_HTTP_ACCEPTED:
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_string ("kyc_url",
                                 &ks.details.kyc_url),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        ks.http_status = 0;
        ks.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
        break;
      }
      kch->cb (kch->cb_cls,
               &ks);
      GNUNET_JSON_parse_free (spec);
      TALER_EXCHANGE_kyc_check_cancel (kch);
      return;
    }
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_BAD_REQUEST:
    ks.ec = TALER_JSON_get_error_code (j);
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_UNAUTHORIZED:
    ks.ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    ks.ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    ks.ec = TALER_JSON_get_error_code (j);
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    ks.ec = TALER_JSON_get_error_code (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange kyc_check\n",
                (unsigned int) response_code,
                (int) ks.ec);
    break;
  }
  kch->cb (kch->cb_cls,
           &ks);
  TALER_EXCHANGE_kyc_check_cancel (kch);
}


struct TALER_EXCHANGE_KycCheckHandle *
TALER_EXCHANGE_kyc_check (struct TALER_EXCHANGE_Handle *exchange,
                          uint64_t payment_target,
                          const struct TALER_PaytoHashP *h_payto,
                          struct GNUNET_TIME_Relative timeout,
                          TALER_EXCHANGE_KycStatusCallback cb,
                          void *cb_cls)
{
  struct TALER_EXCHANGE_KycCheckHandle *kch;
  CURL *eh;
  struct GNUNET_CURL_Context *ctx;
  char *arg_str;

  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  {
    char payto_str[sizeof (*h_payto) * 2];
    char *end;
    unsigned long long timeout_ms;

    end = GNUNET_STRINGS_data_to_string (
      h_payto,
      sizeof (*h_payto),
      payto_str,
      sizeof (payto_str) - 1);
    *end = '\0';
    timeout_ms = timeout.rel_value_us
                 / GNUNET_TIME_UNIT_MILLISECONDS.rel_value_us;
    GNUNET_asprintf (&arg_str,
                     "/kyc-check/%llu?h_payto=%s&timeout_ms=%llu",
                     (unsigned long long) payment_target,
                     payto_str,
                     timeout_ms);
  }
  kch = GNUNET_new (struct TALER_EXCHANGE_KycCheckHandle);
  kch->exchange = exchange;
  kch->h_payto = *h_payto;
  kch->cb = cb;
  kch->cb_cls = cb_cls;
  kch->url = TEAH_path_to_url (exchange,
                               arg_str);
  GNUNET_free (arg_str);
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
  ctx = TEAH_handle_to_context (exchange);
  kch->job = GNUNET_CURL_job_add_with_ct_json (ctx,
                                               eh,
                                               &handle_kyc_check_finished,
                                               kch);
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
