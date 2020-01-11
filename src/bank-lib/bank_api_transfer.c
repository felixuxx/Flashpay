/*
  This file is part of TALER
  Copyright (C) 2015--2020 Taler Systems SA

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
 * @file bank-lib/bank_api_transfer.c
 * @brief Implementation of the /transfer/ requests of the bank's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include "bank_api_common.h"
#include <microhttpd.h> /* just for HTTP status codes */
#include "taler_signatures.h"
#include "taler_curl_lib.h"
#include "taler_bank_service.h"


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Data structure serialized in the prepare stage.
 */
struct WirePackP
{
  /**
   * Random unique identifier for the request.
   */
  struct GNUNET_HashCode request_uid;

  /**
   * Amount to be transferred.
   */
  struct TALER_AmountNBO amount;

  /**
   * Wire transfer identifier to use.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * Length of the payto:// URL of the target account,
   * including 0-terminator, in network byte order.
   */
  uint32_t account_len GNUNET_PACKED;

  /**
   * Length of the exchange's base URL,
   * including 0-terminator, in network byte order.
   */
  uint32_t exchange_url_len GNUNET_PACKED;

};

GNUNET_NETWORK_STRUCT_END

/**
 * Prepare for exeuction of a wire transfer.
 *
 * @param destination_account_url payto:// URL identifying where to send the money
 * @param amount amount to transfer, already rounded
 * @param exchange_base_url base URL of this exchange (included in subject
 *        to facilitate use of tracking API by merchant backend)
 * @param wtid wire transfer identifier to use
 * @param buf[out] set to transfer data to persist, NULL on error
 * @param buf_size[out] set to number of bytes in @a buf, 0 on error
 */
void
TALER_BANK_prepare_wire_transfer (const char *destination_account_url,
                                  const struct TALER_Amount *amount,
                                  const char *exchange_base_url,
                                  const struct
                                  TALER_WireTransferIdentifierRawP *wtid,
                                  void **buf,
                                  size_t *buf_size)
{
  struct WirePackP *wp;
  size_t d_len = strlen (destination_account_url) + 1;
  size_t u_len = strlen (exchange_base_url) + 1;
  char *end;

  *buf_size = sizeof (*wp) + d_len + u_len;
  wp = GNUNET_malloc (*buf_size);
  GNUNET_CRYPTO_hash_create_random (GNUNET_CRYPTO_QUALITY_NONCE,
                                    &wp->request_uid);
  TALER_amount_hton (&wp->amount,
                     amount);
  wp->wtid = *wtid;
  wp->account_len = htonl ((uint32_t) d_len);
  wp->exchange_url_len = htonl ((uint32_t) u_len);
  end = (char *) &wp[1];
  memcpy (end,
          destination_account_url,
          d_len);
  memcpy (end + d_len,
          exchange_base_url,
          u_len);
  *buf = (char *) wp;
}


/**
 * @brief An transfer Handle
 */
struct TALER_BANK_WireExecuteHandle
{

  /**
   * The url for this request.
   */
  char *request_url;

  /**
   * POST context.
   */
  struct TEAH_PostContext post_ctx;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_BANK_ConfirmationCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * Function called when we're done processing the
 * HTTP /transfer request.
 *
 * @param cls the `struct TALER_BANK_WireExecuteHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_transfer_finished (void *cls,
                          long response_code,
                          const void *response)
{
  struct TALER_BANK_WireExecuteHandle *weh = cls;
  uint64_t row_id = UINT64_MAX;
  struct GNUNET_TIME_Absolute timestamp;
  enum TALER_ErrorCode ec;
  const json_t *j = response;

  weh->job = NULL;
  timestamp = GNUNET_TIME_UNIT_FOREVER_ABS;
  switch (response_code)
  {
  case 0:
    ec = TALER_EC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_uint64 ("row_id",
                                 &row_id),
        GNUNET_JSON_spec_absolute_time ("timestamp",
                                        &timestamp),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        response_code = 0;
        ec = TALER_EC_INVALID_RESPONSE;
        break;
      }
      ec = TALER_EC_NONE;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the bank is buggy
       (or API version conflict); just pass JSON reply to the application */
    ec = TALER_BANK_parse_ec_ (j);
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Access denied */
    ec = TALER_BANK_parse_ec_ (j);
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, bank says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    ec = TALER_BANK_parse_ec_ (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    ec = TALER_BANK_parse_ec_ (j);
    break;
  case MHD_HTTP_NOT_ACCEPTABLE:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    ec = TALER_BANK_parse_ec_ (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    ec = TALER_BANK_parse_ec_ (j);
    break;
  default:
    /* unexpected response code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                (unsigned int) response_code);
    GNUNET_break (0);
    ec = TALER_BANK_parse_ec_ (j);
    response_code = 0;
    break;
  }
  weh->cb (weh->cb_cls,
           response_code,
           ec,
           row_id,
           timestamp);
  TALER_BANK_execute_wire_transfer_cancel (weh);
}


/**
 * Execute a wire transfer.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param buf buffer with the prepared execution details
 * @param buf_size number of bytes in @a buf
 * @param cc function to call upon success
 * @param cc_cls closure for @a cc
 * @return NULL on error
 */
struct TALER_BANK_WireExecuteHandle *
TALER_BANK_execute_wire_transfer (struct GNUNET_CURL_Context *ctx,
                                  const char *bank_base_url,
                                  const struct
                                  TALER_BANK_AuthenticationData *auth,
                                  const void *buf,
                                  size_t buf_size,
                                  TALER_BANK_ConfirmationCallback cc,
                                  void *cc_cls)
{
  struct TALER_BANK_WireExecuteHandle *weh;
  json_t *transfer_obj;
  CURL *eh;
  const struct WirePackP *wp = buf;
  uint32_t d_len;
  uint32_t u_len;
  const char *destination_account_url;
  const char *exchange_base_url;
  struct TALER_Amount amount;

  if (sizeof (*wp) > buf_size)
  {
    GNUNET_break (0);
    return NULL;
  }
  d_len = ntohl (wp->account_len);
  u_len = ntohl (wp->exchange_url_len);
  if (sizeof (*wp) + d_len + u_len != buf_size)
  {
    GNUNET_break (0);
    return NULL;
  }
  destination_account_url = (const char *) &wp[1];
  exchange_base_url = destination_account_url + d_len;
  if (NULL == bank_base_url)
  {
    GNUNET_break (0);
    return NULL;
  }
  TALER_amount_ntoh (&amount,
                     &wp->amount);
  transfer_obj = json_pack ("{s:o, s:o, s:s, s:o, s:o, s:s}",
                            "request_uid", GNUNET_JSON_from_data_auto (
                              &wp->request_uid),
                            "amount", TALER_JSON_from_amount (&amount),
                            "exchange_url", exchange_base_url,
                            "wtid", GNUNET_JSON_from_data_auto (&wp->wtid),
                            "credit_account", destination_account_url);
  if (NULL == transfer_obj)
  {
    GNUNET_break (0);
    return NULL;
  }
  weh = GNUNET_new (struct TALER_BANK_WireExecuteHandle);
  weh->cb = cc;
  weh->cb_cls = cc_cls;
  weh->request_url = TALER_BANK_path_to_url_ (bank_base_url,
                                              "/transfer");
  weh->post_ctx.headers = curl_slist_append
                            (weh->post_ctx.headers,
                            "Content-Type: application/json");

  eh = curl_easy_init ();
  if ( (GNUNET_OK !=
        TALER_BANK_setup_auth_ (eh,
                                auth)) ||
       (CURLE_OK !=
        curl_easy_setopt (eh,
                          CURLOPT_URL,
                          weh->request_url)) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&weh->post_ctx,
                              eh,
                              transfer_obj)) )
  {
    GNUNET_break (0);
    TALER_BANK_execute_wire_transfer_cancel (weh);
    curl_easy_cleanup (eh);
    json_decref (transfer_obj);
    return NULL;
  }
  json_decref (transfer_obj);

  weh->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   weh->post_ctx.headers,
                                   &handle_transfer_finished,
                                   weh);
  return weh;
}


/**
 * Cancel a wire transfer.  This function cannot be used on a request handle
 * if a response is already served for it.
 *
 * @param weh the wire transfer request handle
 */
void
TALER_BANK_execute_wire_transfer_cancel (struct
                                         TALER_BANK_WireExecuteHandle *weh)
{
  if (NULL != weh->job)
  {
    GNUNET_CURL_job_cancel (weh->job);
    weh->job = NULL;
  }
  TALER_curl_easy_post_finished (&weh->post_ctx);
  GNUNET_free (weh->request_url);
  GNUNET_free (weh);
}


/* end of bank_api_transfer.c */
