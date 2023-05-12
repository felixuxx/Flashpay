/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * Frees @a wfm array.
 *
 * @param wfm fee array to release
 * @param wfm_len length of the @a wfm array
 */
static void
free_fees (struct TALER_EXCHANGE_WireFeesByMethod *wfm,
           unsigned int wfm_len)
{
  for (unsigned int i = 0; i<wfm_len; i++)
  {
    struct TALER_EXCHANGE_WireFeesByMethod *wfmi = &wfm[i];

    while (NULL != wfmi->fees_head)
    {
      struct TALER_EXCHANGE_WireAggregateFees *fe
        = wfmi->fees_head;

      wfmi->fees_head = fe->next;
      GNUNET_free (fe);
    }
  }
  GNUNET_free (wfm);
}


/**
 * Parse wire @a fees and return array.
 *
 * @param master_pub master public key to use to check signatures
 * @param fees json AggregateTransferFee to parse
 * @param[out] fees_len set to length of returned array
 * @return NULL on error
 */
static struct TALER_EXCHANGE_WireFeesByMethod *
parse_fees (const struct TALER_MasterPublicKeyP *master_pub,
            const json_t *fees,
            unsigned int *fees_len)
{
  struct TALER_EXCHANGE_WireFeesByMethod *fbm;
  unsigned int fbml = json_object_size (fees);
  unsigned int i = 0;
  const char *key;
  const json_t *fee_array;

  fbm = GNUNET_new_array (fbml,
                          struct TALER_EXCHANGE_WireFeesByMethod);
  *fees_len = fbml;
  json_object_foreach ((json_t *) fees, key, fee_array) {
    struct TALER_EXCHANGE_WireFeesByMethod *fe = &fbm[i++];
    unsigned int idx;
    json_t *fee;

    fe->method = key;
    fe->fees_head = NULL;
    json_array_foreach (fee_array, idx, fee)
    {
      struct TALER_EXCHANGE_WireAggregateFees *wa
        = GNUNET_new (struct TALER_EXCHANGE_WireAggregateFees);
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("sig",
                                     &wa->master_sig),
        TALER_JSON_spec_amount_any ("wire_fee",
                                    &wa->fees.wire),
        TALER_JSON_spec_amount_any ("closing_fee",
                                    &wa->fees.closing),
        GNUNET_JSON_spec_timestamp ("start_date",
                                    &wa->start_date),
        GNUNET_JSON_spec_timestamp ("end_date",
                                    &wa->end_date),
        GNUNET_JSON_spec_end ()
      };

      wa->next = fe->fees_head;
      fe->fees_head = wa;
      if (GNUNET_OK !=
          GNUNET_JSON_parse (fee,
                             spec,
                             NULL,
                             NULL))
      {
        GNUNET_break_op (0);
        free_fees (fbm,
                   i);
        return NULL;
      }
      if (GNUNET_OK !=
          TALER_exchange_offline_wire_fee_verify (
            key,
            wa->start_date,
            wa->end_date,
            &wa->fees,
            master_pub,
            &wa->master_sig))
      {
        GNUNET_break_op (0);
        free_fees (fbm,
                   i);
        return NULL;
      }
    } /* for all fees over time */
  } /* for all methods */
  GNUNET_assert (i == fbml);
  return fbm;
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
  struct TALER_EXCHANGE_WireResponse wr = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  TALER_LOG_DEBUG ("Checking raw /wire response\n");
  wh->job = NULL;
  switch (response_code)
  {
  case 0:
    wr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    wh->exchange->wire_error_count++;
    break;
  case MHD_HTTP_OK:
    {
      const json_t *accounts;
      const json_t *fees;
      const json_t *wads;
      struct TALER_EXCHANGE_WireFeesByMethod *fbm;
      struct TALER_MasterPublicKeyP master_pub;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("master_public_key",
                                     &master_pub),
        GNUNET_JSON_spec_array_const ("accounts",
                                      &accounts),
        GNUNET_JSON_spec_object_const ("fees",
                                       &fees),
        GNUNET_JSON_spec_array_const ("wads",
                                      &wads),
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
        wr.hr.http_status = 0;
        wr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      {
        const struct TALER_EXCHANGE_Keys *key_state;

        key_state = TALER_EXCHANGE_get_keys (wh->exchange);
        if (0 != GNUNET_memcmp (&key_state->master_pub,
                                &master_pub))
        {
          /* bogus reply: master public key in /wire differs from that in /keys */
          GNUNET_break_op (0);
          wr.hr.http_status = 0;
          wr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
          break;
        }
      }

      wr.details.ok.accounts_len
        = json_array_size (accounts);
      if (0 == wr.details.ok.accounts_len)
      {
        /* bogus reply */
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        wr.hr.http_status = 0;
        wr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      fbm = parse_fees (&master_pub,
                        fees,
                        &wr.details.ok.fees_len);
      wr.details.ok.fees = fbm;
      if (NULL == fbm)
      {
        /* bogus reply */
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        wr.hr.http_status = 0;
        wr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }

      /* parse accounts */
      {
        struct TALER_EXCHANGE_WireAccount was[wr.details.ok.accounts_len];

        wr.details.ok.accounts = was;
        if (GNUNET_OK !=
            TALER_EXCHANGE_parse_accounts (&master_pub,
                                           accounts,
                                           was,
                                           wr.details.ok.accounts_len))
        {
          GNUNET_break_op (0);
          wr.hr.http_status = 0;
          wr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        }
        else if (NULL != wh->cb)
        {
          wh->cb (wh->cb_cls,
                  &wr);
          wh->cb = NULL;
        }
        TALER_EXCHANGE_free_accounts (was,
                                      wr.details.ok.accounts_len);
      } /* end of 'parse accounts */
      free_fees (fbm,
                 wr.details.ok.fees_len);
      GNUNET_JSON_parse_free (spec);
    } /* end of MHD_HTTP_OK */
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    wr.hr.ec = TALER_JSON_get_error_code (j);
    wr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    wr.hr.ec = TALER_JSON_get_error_code (j);
    wr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    wr.hr.ec = TALER_JSON_get_error_code (j);
    wr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  default:
    /* unexpected response code */
    if (MHD_HTTP_GATEWAY_TIMEOUT == response_code)
      wh->exchange->wire_error_count++;
    GNUNET_break_op (0);
    wr.hr.ec = TALER_JSON_get_error_code (j);
    wr.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange wire\n",
                (unsigned int) response_code,
                (int) wr.hr.ec);
    break;
  }
  if (NULL != wh->cb)
    wh->cb (wh->cb_cls,
            &wr);
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
  if (NULL == wh->url)
  {
    GNUNET_free (wh);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (wh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (wh->url);
    GNUNET_free (wh);
    return NULL;
  }
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_TIMEOUT,
                                  get_wire_timeout_seconds (wh->exchange)));
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
