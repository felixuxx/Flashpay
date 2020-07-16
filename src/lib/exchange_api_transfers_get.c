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
 * @file lib/exchange_api_transfers_get.c
 * @brief Implementation of the GET /transfers/ request
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A /transfers/ GET Handle
 */
struct TALER_EXCHANGE_TransfersGetHandle
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
  TALER_EXCHANGE_TransfersGetCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * We got a #MHD_HTTP_OK response for the /transfers/ request.
 * Check that the response is well-formed and if it is, call the
 * callback.  If not, return an error code.
 *
 * This code is very similar to
 * merchant_api_track_transfer.c::check_transfers_get_response_ok.
 * Any changes should likely be reflected there as well.
 *
 * @param wdh handle to the operation
 * @param json response we got
 * @return #GNUNET_OK if we are done and all is well,
 *         #GNUNET_SYSERR if the response was bogus
 */
static int
check_transfers_get_response_ok (
  struct TALER_EXCHANGE_TransfersGetHandle *wdh,
  const json_t *json)
{
  json_t *details_j;
  struct TALER_EXCHANGE_TransferData td;
  struct TALER_Amount total_expected;
  struct TALER_MerchantPublicKeyP merchant_pub;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("total", &td.total_amount),
    TALER_JSON_spec_amount ("wire_fee", &td.wire_fee),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub", &merchant_pub),
    GNUNET_JSON_spec_fixed_auto ("h_wire", &td.h_wire),
    TALER_JSON_spec_absolute_time ("execution_time", &td.execution_time),
    GNUNET_JSON_spec_json ("deposits", &details_j),
    GNUNET_JSON_spec_fixed_auto ("exchange_sig", &td.exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub", &td.exchange_pub),
    GNUNET_JSON_spec_end ()
  };
  struct TALER_EXCHANGE_HttpResponse hr = {
    .reply = json,
    .http_status = MHD_HTTP_OK
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_amount_get_zero (td.total_amount.currency,
                             &total_expected))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_EXCHANGE_test_signing_key (
        TALER_EXCHANGE_get_keys (wdh->exchange),
        &td.exchange_pub))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return GNUNET_SYSERR;
  }
  td.details_length = json_array_size (details_j);
  {
    struct GNUNET_HashContext *hash_context;
    struct TALER_TrackTransferDetails *details;

    details = GNUNET_new_array (td.details_length,
                                struct TALER_TrackTransferDetails);
    td.details = details;
    hash_context = GNUNET_CRYPTO_hash_context_start ();
    for (unsigned int i = 0; i<td.details_length; i++)
    {
      struct TALER_TrackTransferDetails *detail = &details[i];
      struct json_t *detail_j = json_array_get (details_j, i);
      struct GNUNET_JSON_Specification spec_detail[] = {
        GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                     &detail->h_contract_terms),
        GNUNET_JSON_spec_fixed_auto ("coin_pub", &detail->coin_pub),
        TALER_JSON_spec_amount ("deposit_value", &detail->coin_value),
        TALER_JSON_spec_amount ("deposit_fee", &detail->coin_fee),
        GNUNET_JSON_spec_end ()
      };

      if ( (GNUNET_OK !=
            GNUNET_JSON_parse (detail_j,
                               spec_detail,
                               NULL, NULL)) ||
           (GNUNET_OK !=
            TALER_amount_cmp_currency (&total_expected,
                                       &detail->coin_value)) ||
           (GNUNET_OK !=
            TALER_amount_cmp_currency (&total_expected,
                                       &detail->coin_fee)) ||
           (0 >
            TALER_amount_add (&total_expected,
                              &total_expected,
                              &detail->coin_value)) ||
           (0 >
            TALER_amount_subtract (&total_expected,
                                   &total_expected,
                                   &detail->coin_fee)) )
      {
        GNUNET_break_op (0);
        GNUNET_CRYPTO_hash_context_abort (hash_context);
        GNUNET_JSON_parse_free (spec);
        GNUNET_free (details);
        return GNUNET_SYSERR;
      }
      /* build up big hash for signature checking later */
      {
        struct TALER_WireDepositDetailP dd;

        dd.h_contract_terms = detail->h_contract_terms;
        dd.execution_time = GNUNET_TIME_absolute_hton (td.execution_time);
        dd.coin_pub = detail->coin_pub;
        TALER_amount_hton (&dd.deposit_value,
                           &detail->coin_value);
        TALER_amount_hton (&dd.deposit_fee,
                           &detail->coin_fee);
        GNUNET_CRYPTO_hash_context_read (hash_context,
                                         &dd,
                                         sizeof (dd));
      }
    }
    /* Check signature */
    {
      struct TALER_WireDepositDataPS wdp = {
        .purpose.purpose = htonl (
          TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE_DEPOSIT),
        .purpose.size = htonl (sizeof (wdp)),
        .merchant_pub = merchant_pub,
        .h_wire = td.h_wire
      };

      TALER_amount_hton (&wdp.total,
                         &td.total_amount);
      TALER_amount_hton (&wdp.wire_fee,
                         &td.wire_fee);
      GNUNET_CRYPTO_hash_context_finish (hash_context,
                                         &wdp.h_details);
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (
            TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE_DEPOSIT,
            &wdp,
            &td.exchange_sig.eddsa_signature,
            &td.exchange_pub.eddsa_pub))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        GNUNET_free (details);
        return GNUNET_SYSERR;
      }
    }

    if (0 >
        TALER_amount_subtract (&total_expected,
                               &total_expected,
                               &td.wire_fee))
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
      GNUNET_free (details);
      return GNUNET_SYSERR;
    }
    if (0 !=
        TALER_amount_cmp (&total_expected,
                          &td.total_amount))
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
      GNUNET_free (details);
      return GNUNET_SYSERR;
    }
    wdh->cb (wdh->cb_cls,
             &hr,
             &td);
    GNUNET_free (details);
  }
  GNUNET_JSON_parse_free (spec);
  TALER_EXCHANGE_transfers_get_cancel (wdh);
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /transfers/ request.
 *
 * @param cls the `struct TALER_EXCHANGE_TransfersGetHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_transfers_get_finished (void *cls,
                               long response_code,
                               const void *response)
{
  struct TALER_EXCHANGE_TransfersGetHandle *wdh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .reply = j,
    .http_status = (unsigned int) response_code
  };

  wdh->job = NULL;
  switch (response_code)
  {
  case 0:
    hr.ec = TALER_EC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK ==
        check_transfers_get_response_ok (wdh,
                                         j))
      return;
    GNUNET_break_op (0);
    hr.ec = TALER_EC_TRANSFERS_GET_REPLY_MALFORMED;
    hr.http_status = 0;
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Exchange does not know about transaction;
       we should pass the reply to the application */
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
    GNUNET_break_op (0);
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d\n",
                (unsigned int) response_code,
                (int) hr.ec);
    break;
  }
  wdh->cb (wdh->cb_cls,
           &hr,
           NULL);
  TALER_EXCHANGE_transfers_get_cancel (wdh);
}


/**
 * Query the exchange about which transactions were combined
 * to create a wire transfer.
 *
 * @param exchange exchange to query
 * @param wtid raw wire transfer identifier to get information about
 * @param cb callback to call
 * @param cb_cls closure for @a cb
 * @return handle to cancel operation
 */
struct TALER_EXCHANGE_TransfersGetHandle *
TALER_EXCHANGE_transfers_get (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  TALER_EXCHANGE_TransfersGetCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_TransfersGetHandle *wdh;
  struct GNUNET_CURL_Context *ctx;
  CURL *eh;
  char arg_str[sizeof (struct TALER_WireTransferIdentifierRawP) * 2 + 32];

  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }

  wdh = GNUNET_new (struct TALER_EXCHANGE_TransfersGetHandle);
  wdh->exchange = exchange;
  wdh->cb = cb;
  wdh->cb_cls = cb_cls;

  {
    char wtid_str[sizeof (struct TALER_WireTransferIdentifierRawP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (wtid,
                                         sizeof (struct
                                                 TALER_WireTransferIdentifierRawP),
                                         wtid_str,
                                         sizeof (wtid_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/transfers/%s",
                     wtid_str);
  }
  wdh->url = TEAH_path_to_url (wdh->exchange,
                               arg_str);
  eh = TALER_EXCHANGE_curl_easy_get_ (wdh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (wdh->url);
    GNUNET_free (wdh);
    return NULL;
  }
  ctx = TEAH_handle_to_context (exchange);
  wdh->job = GNUNET_CURL_job_add_with_ct_json (ctx,
                                               eh,
                                               &handle_transfers_get_finished,
                                               wdh);
  return wdh;
}


/**
 * Cancel wire deposits request.  This function cannot be used on a request
 * handle if a response is already served for it.
 *
 * @param wdh the wire deposits request handle
 */
void
TALER_EXCHANGE_transfers_get_cancel (
  struct TALER_EXCHANGE_TransfersGetHandle *wdh)
{
  if (NULL != wdh->job)
  {
    GNUNET_CURL_job_cancel (wdh->job);
    wdh->job = NULL;
  }
  GNUNET_free (wdh->url);
  GNUNET_free (wdh);
}


/* end of exchange_api_transfers_get.c */
