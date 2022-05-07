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
 * @file lib/exchange_api_purses_get.c
 * @brief Implementation of the /purses/ GET request
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
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A Contract Get Handle
 */
struct TALER_EXCHANGE_PurseGetHandle
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
  TALER_EXCHANGE_PurseGetCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * Function called when we're done processing the
 * HTTP /purses/$PID GET request.
 *
 * @param cls the `struct TALER_EXCHANGE_PurseGetHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_purse_get_finished (void *cls,
                           long response_code,
                           const void *response)
{
  struct TALER_EXCHANGE_PurseGetHandle *pgh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_PurseGetResponse dr = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  pgh->job = NULL;
  switch (response_code)
  {
  case 0:
    dr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      struct TALER_ExchangePublicKeyP exchange_pub;
      struct TALER_ExchangeSignatureP exchange_sig;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_timestamp ("merge_timestamp",
                                    &dr.details.success.merge_timestamp),
        GNUNET_JSON_spec_timestamp ("deposit_timestamp",
                                    &dr.details.success.deposit_timestamp),
        TALER_JSON_spec_amount_any ("balance",
                                    &dr.details.success.balance),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &exchange_pub),
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &exchange_sig),
        GNUNET_JSON_spec_end ()
      };
      const struct TALER_EXCHANGE_Keys *key_state;

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }

      key_state = TALER_EXCHANGE_get_keys (pgh->exchange);
      if (GNUNET_OK !=
          TALER_EXCHANGE_test_signing_key (key_state,
                                           &exchange_pub))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_EXCHANGE_PURSES_GET_INVALID_SIGNATURE_BY_EXCHANGE;
        break;
      }
      if (GNUNET_OK !=
          TALER_exchange_online_purse_status_verify (
            dr.details.success.merge_timestamp,
            dr.details.success.deposit_timestamp,
            &dr.details.success.balance,
            &exchange_pub,
            &exchange_sig))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_EXCHANGE_PURSES_GET_INVALID_SIGNATURE_BY_EXCHANGE;
        break;
      }
      pgh->cb (pgh->cb_cls,
               &dr);
      TALER_EXCHANGE_purse_get_cancel (pgh);
      return;
    }
  case MHD_HTTP_BAD_REQUEST:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
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
    /* Exchange does not know about transaction;
       we should pass the reply to the application */
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
                "Unexpected response code %u/%d for exchange GET purses\n",
                (unsigned int) response_code,
                (int) dr.hr.ec);
    GNUNET_break_op (0);
    break;
  }
  pgh->cb (pgh->cb_cls,
           &dr);
  TALER_EXCHANGE_purse_get_cancel (pgh);
}


struct TALER_EXCHANGE_PurseGetHandle *
TALER_EXCHANGE_purse_get (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct GNUNET_TIME_Relative timeout,
  bool wait_for_merge,
  TALER_EXCHANGE_PurseGetCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_PurseGetHandle *pgh;
  CURL *eh;
  char arg_str[sizeof (*purse_pub) * 2 + 64];

  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  pgh = GNUNET_new (struct TALER_EXCHANGE_PurseGetHandle);
  pgh->exchange = exchange;
  pgh->cb = cb;
  pgh->cb_cls = cb_cls;
  {
    char cpub_str[sizeof (*purse_pub) * 2];
    char *end;
    char timeout_str[32];

    end = GNUNET_STRINGS_data_to_string (purse_pub,
                                         sizeof (*purse_pub),
                                         cpub_str,
                                         sizeof (cpub_str));
    *end = '\0';
    GNUNET_snprintf (timeout_str,
                     sizeof (timeout_str),
                     "%llu",
                     (unsigned long long)
                     (timeout.rel_value_us
                      / GNUNET_TIME_UNIT_MILLISECONDS.rel_value_us));
    if (GNUNET_TIME_relative_is_zero (timeout))
      GNUNET_snprintf (arg_str,
                       sizeof (arg_str),
                       "/purses/%s/%s",
                       cpub_str,
                       wait_for_merge ? "merge" : "deposit");
    else
      GNUNET_snprintf (arg_str,
                       sizeof (arg_str),
                       "/purses/%s/%s?timeout_ms=%s",
                       cpub_str,
                       wait_for_merge ? "merge" : "deposit",
                       timeout_str);
  }
  pgh->url = TEAH_path_to_url (exchange,
                               arg_str);
  if (NULL == pgh->url)
  {
    GNUNET_free (pgh);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (pgh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (pgh->url);
    GNUNET_free (pgh);
    return NULL;
  }
  pgh->job = GNUNET_CURL_job_add (TEAH_handle_to_context (exchange),
                                  eh,
                                  &handle_purse_get_finished,
                                  pgh);
  return pgh;
}


void
TALER_EXCHANGE_purse_get_cancel (
  struct TALER_EXCHANGE_PurseGetHandle *pgh)
{
  if (NULL != pgh->job)
  {
    GNUNET_CURL_job_cancel (pgh->job);
    pgh->job = NULL;
  }
  GNUNET_free (pgh->url);
  GNUNET_free (pgh);
}


/* end of exchange_api_purses_get.c */
