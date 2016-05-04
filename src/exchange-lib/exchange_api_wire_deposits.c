/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file exchange-lib/exchange_api_wire_deposits.c
 * @brief Implementation of the /wire/deposits request of the exchange's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "exchange_api_common.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"


/**
 * @brief A /wire/deposits Handle
 */
struct TALER_EXCHANGE_WireDepositsHandle
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
  TALER_EXCHANGE_WireDepositsCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * Function called when we're done processing the
 * HTTP /wire/deposits request.
 *
 * @param cls the `struct TALER_EXCHANGE_WireDepositsHandle`
 * @param response_code HTTP response code, 0 on error
 * @param json parsed JSON result, NULL on error
 */
static void
handle_wire_deposits_finished (void *cls,
                               long response_code,
                               const json_t *json)
{
  struct TALER_EXCHANGE_WireDepositsHandle *wdh = cls;

  wdh->job = NULL;
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    {
      json_t *details_j;
      struct GNUNET_HashCode h_wire;
      struct TALER_Amount total_amount;
      struct TALER_MerchantPublicKeyP merchant_pub;
      unsigned int num_details;
      struct TALER_ExchangePublicKeyP exchange_pub;
      struct TALER_ExchangeSignatureP exchange_sig;
      struct GNUNET_JSON_Specification spec[] = {
        TALER_JSON_spec_amount ("total", &total_amount),
        GNUNET_JSON_spec_fixed_auto ("merchant_pub", &merchant_pub),
        GNUNET_JSON_spec_fixed_auto ("H_wire", &h_wire),
        GNUNET_JSON_spec_json ("deposits", &details_j),
        GNUNET_JSON_spec_fixed_auto ("exchange_sig", &exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub", &exchange_pub),
        GNUNET_JSON_spec_end()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (json,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        response_code = 0;
        break;
      }
      num_details = json_array_size (details_j);
      {
        struct TALER_WireDepositDetails details[num_details];
        unsigned int i;
        struct GNUNET_HashContext *hash_context;
        struct TALER_WireDepositDetailP dd;
        struct TALER_WireDepositDataPS wdp;

        hash_context = GNUNET_CRYPTO_hash_context_start ();
        for (i=0;i<num_details;i++)
        {
          struct TALER_WireDepositDetails *detail = &details[i];
          struct json_t *detail_j = json_array_get (details_j, i);
          struct GNUNET_JSON_Specification spec_detail[] = {
            GNUNET_JSON_spec_fixed_auto ("H_contract", &detail->h_contract),
            GNUNET_JSON_spec_uint64 ("transaction_id", &detail->transaction_id),
            GNUNET_JSON_spec_fixed_auto ("coin_pub", &detail->coin_pub),
            TALER_JSON_spec_amount ("deposit_value", &detail->coin_value),
            TALER_JSON_spec_amount ("deposit_fee", &detail->coin_fee),
            GNUNET_JSON_spec_end()
          };

          if (GNUNET_OK !=
              GNUNET_JSON_parse (detail_j,
                                 spec_detail,
                                 NULL, NULL))
          {
            GNUNET_break_op (0);
            response_code = 0;
            break;
          }
          /* build up big hash for signature checking later */
          dd.h_contract = detail->h_contract;
          dd.transaction_id = GNUNET_htonll (detail->transaction_id);
          dd.coin_pub = detail->coin_pub;
          TALER_amount_hton (&dd.deposit_value,
                             &detail->coin_value);
          TALER_amount_hton (&dd.deposit_fee,
                             &detail->coin_fee);
          GNUNET_CRYPTO_hash_context_read (hash_context,
                                           &dd,
                                           sizeof (struct TALER_WireDepositDetailP));
        }
        /* Check signature */
        wdp.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE_DEPOSIT);
        wdp.purpose.size = htonl (sizeof (struct TALER_WireDepositDataPS));
        TALER_amount_hton (&wdp.total,
                           &total_amount);
        wdp.merchant_pub = merchant_pub;
        wdp.h_wire = h_wire;
        GNUNET_CRYPTO_hash_context_finish (hash_context,
                                           &wdp.h_details);
        if ( (0 == response_code /* avoid crypto if things are already wrong */) &&
             (GNUNET_OK !=
              TALER_EXCHANGE_test_signing_key (TALER_EXCHANGE_get_keys (wdh->exchange),
                                               &exchange_pub)) )
        {
          GNUNET_break_op (0);
          response_code = 0;
        }
        if ( (0 == response_code /* avoid crypto if things are already wrong */) &&
             (GNUNET_OK !=
              TALER_EXCHANGE_test_signing_key (TALER_EXCHANGE_get_keys (wdh->exchange),
                                               &exchange_pub)) )
        {
          GNUNET_break_op (0);
          response_code = 0;
        }
        if (0 == response_code)
          break;
        wdh->cb (wdh->cb_cls,
                 response_code,
                 json,
                 &h_wire,
                 &total_amount,
                 num_details,
                 details);
        TALER_EXCHANGE_wire_deposits_cancel (wdh);
        return;
      }
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Exchange does not know about transaction;
       we should pass the reply to the application */
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                response_code);
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  wdh->cb (wdh->cb_cls,
           response_code,
           json,
           NULL, NULL, 0, NULL);
  TALER_EXCHANGE_wire_deposits_cancel (wdh);
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
struct TALER_EXCHANGE_WireDepositsHandle *
TALER_EXCHANGE_wire_deposits (struct TALER_EXCHANGE_Handle *exchange,
                              const struct TALER_WireTransferIdentifierRawP *wtid,
                              TALER_EXCHANGE_WireDepositsCallback cb,
                              void *cb_cls)
{
  struct TALER_EXCHANGE_WireDepositsHandle *wdh;
  struct GNUNET_CURL_Context *ctx;
  char *buf;
  char *path;
  CURL *eh;

  if (GNUNET_YES !=
      MAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }

  wdh = GNUNET_new (struct TALER_EXCHANGE_WireDepositsHandle);
  wdh->exchange = exchange;
  wdh->cb = cb;
  wdh->cb_cls = cb_cls;

  buf = GNUNET_STRINGS_data_to_string_alloc (wtid,
                                             sizeof (struct TALER_WireTransferIdentifierRawP));
  GNUNET_asprintf (&path,
                   "/wire/deposits?wtid=%s",
                   buf);
  wdh->url = MAH_path_to_url (wdh->exchange,
                              path);
  GNUNET_free (buf);
  GNUNET_free (path);

  eh = curl_easy_init ();
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   wdh->url));
  ctx = MAH_handle_to_context (exchange);
  wdh->job = GNUNET_CURL_job_add (ctx,
                          eh,
                          GNUNET_YES,
                          &handle_wire_deposits_finished,
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
TALER_EXCHANGE_wire_deposits_cancel (struct TALER_EXCHANGE_WireDepositsHandle *wdh)
{
  if (NULL != wdh->job)
  {
    GNUNET_CURL_job_cancel (wdh->job);
    wdh->job = NULL;
  }
  GNUNET_free (wdh->url);
  GNUNET_free (wdh);
}


/* end of exchange_api_wire_deposits.c */
