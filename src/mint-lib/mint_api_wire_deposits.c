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
 * @file mint-lib/mint_api_wire_deposits.c
 * @brief Implementation of the /wire/deposits request of the mint's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include "taler_mint_service.h"
#include "mint_api_common.h"
#include "mint_api_json.h"
#include "mint_api_context.h"
#include "mint_api_handle.h"
#include "taler_signatures.h"


/**
 * @brief A /wire/deposits Handle
 */
struct TALER_MINT_WireDepositsHandle
{

  /**
   * The connection to mint this request handle will use
   */
  struct TALER_MINT_Handle *mint;

  /**
   * The url for this request.
   */
  char *url;

  /**
   * Handle for the request.
   */
  struct MAC_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_MINT_WireDepositsCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Download buffer
   */
  struct MAC_DownloadBuffer db;

};


/**
 * Function called when we're done processing the
 * HTTP /wire/deposits request.
 *
 * @param cls the `struct TALER_MINT_WireDepositsHandle`
 * @param eh the curl request handle
 */
static void
handle_wire_deposits_finished (void *cls,
                               CURL *eh)
{
  struct TALER_MINT_WireDepositsHandle *wdh = cls;
  long response_code;
  json_t *json;

  wdh->job = NULL;
  json = MAC_download_get_result (&wdh->db,
                                  eh,
                                  &response_code);
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
      struct MAJ_Specification spec[] = {
        MAJ_spec_fixed_auto ("H_wire", &h_wire),
        MAJ_spec_fixed_auto ("merchant_pub", &merchant_pub),
        MAJ_spec_amount ("total_amount", &total_amount),
        MAJ_spec_json ("details", &details_j),
        MAJ_spec_end
      };

      if (GNUNET_OK !=
          MAJ_parse_json (json,
                          spec))
      {
        GNUNET_break_op (0);
        response_code = 0;
        break;
      }
      num_details = json_array_size (details_j);
      {
        struct TALER_WireDepositDetails details[num_details];
        unsigned int i;

        for (i=0;i<num_details;i++)
        {
          struct TALER_WireDepositDetails *detail = &details[i];
          struct json_t *detail_j = json_array_get (details_j, i);
          struct MAJ_Specification spec_detail[] = {
            MAJ_spec_fixed_auto ("H_contract", &detail->h_contract),
            MAJ_spec_amount ("deposit_value", &detail->coin_value),
            MAJ_spec_amount ("deposit_fee", &detail->coin_fee),
            MAJ_spec_uint64 ("transaction_id", &detail->transaction_id),
            MAJ_spec_fixed_auto ("coin_pub", &detail->coin_pub),
            MAJ_spec_end
          };

          if (GNUNET_OK !=
              MAJ_parse_json (detail_j,
                              spec_detail))
          {
            GNUNET_break_op (0);
            response_code = 0;
            break;
          }
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
        json_decref (json);
        TALER_MINT_wire_deposits_cancel (wdh);
        return;
      }
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the mint is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, mint says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Mint does not know about transaction;
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
  json_decref (json);
  TALER_MINT_wire_deposits_cancel (wdh);
}


/**
 * Query the mint about which transactions were combined
 * to create a wire transfer.
 *
 * @param mint mint to query
 * @param wtid raw wire transfer identifier to get information about
 * @param cb callback to call
 * @param cb_cls closure for @a cb
 * @return handle to cancel operation
 */
struct TALER_MINT_WireDepositsHandle *
TALER_MINT_wire_deposits (struct TALER_MINT_Handle *mint,
                          const struct TALER_WireTransferIdentifierRawP *wtid,
                          TALER_MINT_WireDepositsCallback cb,
                          void *cb_cls)
{
  struct TALER_MINT_WireDepositsHandle *wdh;
  struct TALER_MINT_Context *ctx;
  char *buf;
  char *path;
  CURL *eh;

  if (GNUNET_YES !=
      MAH_handle_is_ready (mint))
  {
    GNUNET_break (0);
    return NULL;
  }

  wdh = GNUNET_new (struct TALER_MINT_WireDepositsHandle);
  wdh->mint = mint;
  wdh->cb = cb;
  wdh->cb_cls = cb_cls;

  buf = GNUNET_STRINGS_data_to_string_alloc (wtid,
                                             sizeof (struct TALER_WireTransferIdentifierRawP));
  GNUNET_asprintf (&path,
                   "/wire/deposits?wtid=%s",
                   buf);
  wdh->url = MAH_path_to_url (wdh->mint,
                              path);
  GNUNET_free (buf);
  GNUNET_free (path);

  eh = curl_easy_init ();
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   wdh->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEFUNCTION,
                                   &MAC_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEDATA,
                                   &wdh->db));
  ctx = MAH_handle_to_context (mint);
  wdh->job = MAC_job_add (ctx,
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
TALER_MINT_wire_deposits_cancel (struct TALER_MINT_WireDepositsHandle *wdh)
{
  if (NULL != wdh->job)
  {
    MAC_job_cancel (wdh->job);
    wdh->job = NULL;
  }
  GNUNET_free_non_null (wdh->db.buf);
  GNUNET_free (wdh->url);
  GNUNET_free (wdh);
}


/* end of mint_api_wire_deposits.c */
