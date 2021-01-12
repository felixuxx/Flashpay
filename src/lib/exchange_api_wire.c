/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file lib/exchange_api_wire.c
 * @brief Implementation of the /wire request of the exchange's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "taler_signatures.h"
#include "exchange_api_handle.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A Wire Handle
 */
struct TALER_EXCHANGE_WireHandle
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
  TALER_EXCHANGE_WireCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * List of wire fees by method.
 */
struct FeeMap
{
  /**
   * Next entry in list.
   */
  struct FeeMap *next;

  /**
   * Wire method this fee structure is for.
   */
  char *method;

  /**
   * Array of wire fees, also linked list, but allocated
   * only once.
   */
  struct TALER_EXCHANGE_WireAggregateFees *fee_list;
};


/**
 * Frees @a fm.
 *
 * @param fm memory to release
 */
static void
free_fees (struct FeeMap *fm)
{
  while (NULL != fm)
  {
    struct FeeMap *fe = fm->next;

    GNUNET_free (fm->fee_list);
    GNUNET_free (fm->method);
    GNUNET_free (fm);
    fm = fe;
  }
}


/**
 * Parse wire @a fees and return map.
 *
 * @param fees json AggregateTransferFee to parse
 * @return NULL on error
 */
static struct FeeMap *
parse_fees (json_t *fees)
{
  struct FeeMap *fm = NULL;
  const char *key;
  json_t *fee_array;

  json_object_foreach (fees, key, fee_array) {
    struct FeeMap *fe = GNUNET_new (struct FeeMap);
    unsigned int len;
    unsigned int idx;
    json_t *fee;

    if (0 == (len = json_array_size (fee_array)))
    {
      GNUNET_free (fe);
      continue; /* skip */
    }
    fe->method = GNUNET_strdup (key);
    fe->next = fm;
    fe->fee_list = GNUNET_new_array (len,
                                     struct TALER_EXCHANGE_WireAggregateFees);
    fm = fe;
    json_array_foreach (fee_array, idx, fee)
    {
      struct TALER_EXCHANGE_WireAggregateFees *wa = &fe->fee_list[idx];
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("sig",
                                     &wa->master_sig),
        TALER_JSON_spec_amount ("wire_fee",
                                &wa->wire_fee),
        TALER_JSON_spec_amount ("closing_fee",
                                &wa->closing_fee),
        TALER_JSON_spec_absolute_time ("start_date",
                                       &wa->start_date),
        TALER_JSON_spec_absolute_time ("end_date",
                                       &wa->end_date),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (fee,
                             spec,
                             NULL,
                             NULL))
      {
        GNUNET_break_op (0);
        free_fees (fm);
        return NULL;
      }
      if (idx + 1 < len)
        wa->next = &fe->fee_list[idx + 1];
      else
        wa->next = NULL;
    }
  }
  return fm;
}


/**
 * Find fee by @a method.
 *
 * @param fm map to look in
 * @param method key to look for
 * @return NULL if fee is not specified in @a fm
 */
static const struct TALER_EXCHANGE_WireAggregateFees *
lookup_fee (const struct FeeMap *fm,
            const char *method)
{
  for (; NULL != fm; fm = fm->next)
    if (0 == strcasecmp (fm->method,
                         method))
      return fm->fee_list;
  return NULL;
}


/**
 * Function called when we're done processing the
 * HTTP /wire request.
 *
 * @param cls the `struct TALER_EXCHANGE_WireHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_wire_finished (void *cls,
                      long response_code,
                      const void *response)
{
  struct TALER_EXCHANGE_WireHandle *wh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .reply = j,
    .http_status = (unsigned int) response_code
  };

  TALER_LOG_DEBUG ("Checking raw /wire response\n");
  wh->job = NULL;
  switch (response_code)
  {
  case 0:
    hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    /* FIXME:  Maybe we should only increment when we know it's a timeout? */
    wh->exchange->wire_error_count++;
    break;
  case MHD_HTTP_OK:
    {
      json_t *accounts;
      json_t *fees;
      unsigned int num_accounts;
      struct FeeMap *fm;
      const struct TALER_EXCHANGE_Keys *key_state;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_json ("accounts", &accounts),
        GNUNET_JSON_spec_json ("fees", &fees),
        GNUNET_JSON_spec_end ()
      };

      wh->exchange->wire_error_count = 0;

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        /* bogus reply */
        GNUNET_break_op (0);
        hr.http_status = 0;
        hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      if (0 == (num_accounts = json_array_size (accounts)))
      {
        /* bogus reply */
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        hr.http_status = 0;
        hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      if (NULL == (fm = parse_fees (fees)))
      {
        /* bogus reply */
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        hr.http_status = 0;
        hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }

      key_state = TALER_EXCHANGE_get_keys (wh->exchange);
      /* parse accounts */
      {
        struct TALER_EXCHANGE_WireAccount was[num_accounts];

        for (unsigned int i = 0; i<num_accounts; i++)
        {
          struct TALER_EXCHANGE_WireAccount *wa = &was[i];
          json_t *account;
          struct GNUNET_JSON_Specification spec_account[] = {
            GNUNET_JSON_spec_string ("payto_uri", &wa->payto_uri),
            GNUNET_JSON_spec_fixed_auto ("master_sig", &wa->master_sig),
            GNUNET_JSON_spec_end ()
          };
          char *method;

          account = json_array_get (accounts,
                                    i);
          if (GNUNET_OK !=
              TALER_JSON_exchange_wire_signature_check (account,
                                                        &key_state->master_pub))
          {
            /* bogus reply */
            GNUNET_break_op (0);
            hr.http_status = 0;
            hr.ec = TALER_EC_EXCHANGE_WIRE_SIGNATURE_INVALID;
            break;
          }
          if (GNUNET_OK !=
              GNUNET_JSON_parse (account,
                                 spec_account,
                                 NULL, NULL))
          {
            /* bogus reply */
            GNUNET_break_op (0);
            hr.http_status = 0;
            hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
            break;
          }
          if (NULL == (method = TALER_payto_get_method (wa->payto_uri)))
          {
            /* bogus reply */
            GNUNET_break_op (0);
            hr.http_status = 0;
            hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
            break;
          }
          if (NULL == (wa->fees = lookup_fee (fm,
                                              method)))
          {
            /* bogus reply */
            GNUNET_break_op (0);
            hr.http_status = 0;
            hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
            GNUNET_free (method);
            break;
          }
          GNUNET_free (method);
        } /* end 'for all accounts */
        if ( (0 != response_code) &&
             (NULL != wh->cb) )
        {
          wh->cb (wh->cb_cls,
                  &hr,
                  num_accounts,
                  was);
          wh->cb = NULL;
        }
      } /* end of 'parse accounts */
      free_fees (fm);
      GNUNET_JSON_parse_free (spec);
    } /* end of MHD_HTTP_OK */
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  default:
    /* unexpected response code */
    if (MHD_HTTP_GATEWAY_TIMEOUT == response_code)
      wh->exchange->wire_error_count++;
    GNUNET_break_op (0);
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange wire\n",
                (unsigned int) response_code,
                (int) hr.ec);
    break;
  }
  if (NULL != wh->cb)
    wh->cb (wh->cb_cls,
            &hr,
            0,
            NULL);
  TALER_EXCHANGE_wire_cancel (wh);
}


/**
 * Compute the network timeout for the next request to /wire.
 *
 * @param exchange the exchange handle
 * @returns the timeout in seconds (for use by CURL)
 */
static long
get_wire_timeout_seconds (struct TALER_EXCHANGE_Handle *exchange)
{
  return GNUNET_MIN (60,
                     5 + (1L << exchange->wire_error_count));
}


/**
 * Obtain information about a exchange's wire instructions.
 * A exchange may provide wire instructions for creating
 * a reserve.  The wire instructions also indicate
 * which wire formats merchants may use with the exchange.
 * This API is typically used by a wallet for wiring
 * funds, and possibly by a merchant to determine
 * supported wire formats.
 *
 * Note that while we return the (main) response verbatim to the
 * caller for further processing, we do already verify that the
 * response is well-formed (i.e. that signatures included in the
 * response are all valid).  If the exchange's reply is not well-formed,
 * we return an HTTP status code of zero to @a cb.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param wire_cb the callback to call when a reply for this request is available
 * @param wire_cb_cls closure for the above callback
 * @return a handle for this request
 */
struct TALER_EXCHANGE_WireHandle *
TALER_EXCHANGE_wire (struct TALER_EXCHANGE_Handle *exchange,
                     TALER_EXCHANGE_WireCallback wire_cb,
                     void *wire_cb_cls)
{
  struct TALER_EXCHANGE_WireHandle *wh;
  struct GNUNET_CURL_Context *ctx;
  CURL *eh;

  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  wh = GNUNET_new (struct TALER_EXCHANGE_WireHandle);
  wh->exchange = exchange;
  wh->cb = wire_cb;
  wh->cb_cls = wire_cb_cls;
  wh->url = TEAH_path_to_url (exchange,
                              "/wire");
  eh = TALER_EXCHANGE_curl_easy_get_ (wh->url);
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_TIMEOUT,
                                  get_wire_timeout_seconds (wh->exchange)));
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (wh->url);
    GNUNET_free (wh);
    return NULL;
  }
  ctx = TEAH_handle_to_context (exchange);
  wh->job = GNUNET_CURL_job_add_with_ct_json (ctx,
                                              eh,
                                              &handle_wire_finished,
                                              wh);
  return wh;
}


/**
 * Cancel a wire information request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param wh the wire information request handle
 */
void
TALER_EXCHANGE_wire_cancel (struct TALER_EXCHANGE_WireHandle *wh)
{
  if (NULL != wh->job)
  {
    GNUNET_CURL_job_cancel (wh->job);
    wh->job = NULL;
  }
  GNUNET_free (wh->url);
  GNUNET_free (wh);
}


/* end of exchange_api_wire.c */
