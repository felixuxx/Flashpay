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
 * Prepare for execution of a wire transfer from the exchange to some
 * merchant.
 *
 * @param destination_account_payto_uri payto:// URL identifying where to send the money
 * @param amount amount to transfer, already rounded
 * @param exchange_base_url base URL of this exchange (included in subject
 *        to facilitate use of tracking API by merchant backend)
 * @param wtid wire transfer identifier to use
 * @param[out] buf set to transfer data to persist, NULL on error
 * @param[out] buf_size set to number of bytes in @a buf, 0 on error
 */
void
TALER_BANK_prepare_transfer (
  const char *destination_account_payto_uri,
  const struct TALER_Amount *amount,
  const char *exchange_base_url,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  void **buf,
  size_t *buf_size)
{
  struct WirePackP *wp;
  size_t d_len = strlen (destination_account_payto_uri) + 1;
  size_t u_len = strlen (exchange_base_url) + 1;
  char *end;

  if ( (d_len >= (size_t) GNUNET_MAX_MALLOC_CHECKED) ||
       (u_len >= (size_t) GNUNET_MAX_MALLOC_CHECKED) ||
       (d_len + u_len + sizeof (*wp) >= GNUNET_MAX_MALLOC_CHECKED) )
  {
    GNUNET_break (0); /* that's some long URL... */
    *buf = NULL;
    *buf_size = 0;
    return;
  }
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
          destination_account_payto_uri,
          d_len);
  memcpy (end + d_len,
          exchange_base_url,
          u_len);
  *buf = (char *) wp;
}


/**
 * @brief Handle for an active wire transfer.
 */
struct TALER_BANK_TransferHandle
{

  /**
   * The url for this request.
   */
  char *request_url;

  /**
   * POST context.
   */
  struct TALER_CURL_PostContext post_ctx;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_BANK_TransferCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * Function called when we're done processing the
 * HTTP /transfer request.
 *
 * @param cls the `struct TALER_BANK_TransferHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_transfer_finished (void *cls,
                          long response_code,
                          const void *response)
{
  struct TALER_BANK_TransferHandle *th = cls;
  const json_t *j = response;
  uint64_t row_id = UINT64_MAX;
  struct GNUNET_TIME_Absolute timestamp = GNUNET_TIME_UNIT_FOREVER_ABS;
  enum TALER_ErrorCode ec;

  th->job = NULL;
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
    GNUNET_break_op (0);
    ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, bank says our credentials are
       invalid. We should pass the JSON reply to the application. */
    ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, endpoint wrong -- could be user unknown */
    ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_CONFLICT:
    /* Nothing really to verify. Server says we used the same transfer request
       UID before, but with different details.  Should not happen if the user
       properly used #TALER_BANK_prepare_transfer() and our PRNG is not
       broken... */
    ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    ec = TALER_JSON_get_error_code (j);
    break;
  default:
    /* unexpected response code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                (unsigned int) response_code);
    GNUNET_break (0);
    ec = TALER_JSON_get_error_code (j);
    break;
  }
  th->cb (th->cb_cls,
          response_code,
          ec,
          row_id,
          timestamp);
  TALER_BANK_transfer_cancel (th);
}


/**
 * Execute a wire transfer.
 *
 * @param ctx curl context for our event loop
 * @param auth authentication data to authenticate with the bank
 * @param buf buffer with the prepared execution details
 * @param buf_size number of bytes in @a buf
 * @param cc function to call upon success
 * @param cc_cls closure for @a cc
 * @return NULL on error
 */
struct TALER_BANK_TransferHandle *
TALER_BANK_transfer (
  struct GNUNET_CURL_Context *ctx,
  const struct TALER_BANK_AuthenticationData *auth,
  const void *buf,
  size_t buf_size,
  TALER_BANK_TransferCallback cc,
  void *cc_cls)
{
  struct TALER_BANK_TransferHandle *th;
  json_t *transfer_obj;
  CURL *eh;
  const struct WirePackP *wp = buf;
  uint32_t d_len;
  uint32_t u_len;
  const char *destination_account_uri;
  const char *exchange_base_url;
  struct TALER_Amount amount;

  if (sizeof (*wp) > buf_size)
  {
    GNUNET_break (0);
    return NULL;
  }
  d_len = ntohl (wp->account_len);
  u_len = ntohl (wp->exchange_url_len);
  if ( (sizeof (*wp) + d_len + u_len != buf_size) ||
       (d_len > buf_size) ||
       (u_len > buf_size) ||
       (d_len + u_len > buf_size) )
  {
    GNUNET_break (0);
    return NULL;
  }
  destination_account_uri = (const char *) &wp[1];
  exchange_base_url = destination_account_uri + d_len;
  if ( ('\0' != destination_account_uri[d_len - 1]) ||
       ('\0' != exchange_base_url[u_len - 1]) )
  {
    GNUNET_break (0);
    return NULL;
  }
  if (NULL == auth->wire_gateway_url)
  {
    GNUNET_break (0);
    return NULL;
  }
  TALER_amount_ntoh (&amount,
                     &wp->amount);
  th = GNUNET_new (struct TALER_BANK_TransferHandle);
  th->cb = cc;
  th->cb_cls = cc_cls;
  th->request_url = TALER_url_join (auth->wire_gateway_url,
                                    "transfer",
                                    NULL);
  if (NULL == th->request_url)
  {
    GNUNET_free (th);
    GNUNET_break (0);
    return NULL;
  }
  transfer_obj = json_pack ("{s:o, s:o, s:s, s:o, s:s}",
                            "request_uid", GNUNET_JSON_from_data_auto (
                              &wp->request_uid),
                            "amount", TALER_JSON_from_amount (&amount),
                            "exchange_base_url", exchange_base_url,
                            "wtid", GNUNET_JSON_from_data_auto (&wp->wtid),
                            "credit_account", destination_account_uri);
  if (NULL == transfer_obj)
  {
    GNUNET_break (0);
    return NULL;
  }
  eh = curl_easy_init ();
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_BANK_setup_auth_ (eh,
                                auth)) ||
       (CURLE_OK !=
        curl_easy_setopt (eh,
                          CURLOPT_URL,
                          th->request_url)) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&th->post_ctx,
                              eh,
                              transfer_obj)) )
  {
    GNUNET_break (0);
    TALER_BANK_transfer_cancel (th);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (transfer_obj);
    return NULL;
  }
  json_decref (transfer_obj);

  th->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  th->post_ctx.headers,
                                  &handle_transfer_finished,
                                  th);
  return th;
}


/**
 * Abort execution of a wire transfer. For example, because we are shutting
 * down.  Note that if an execution is aborted, it may or may not still
 * succeed.
 *
 * The caller MUST run #TALER_BANK_transfer() again for the same request as
 * soon as possible, to ensure that the request either ultimately succeeds or
 * ultimately fails. Until this has been done, the transaction is in limbo
 * (i.e. may or may not have been committed).
 *
 * This function cannot be used on a request handle if a response is already
 * served for it.
 *
 * @param th the wire transfer request handle
 */
void
TALER_BANK_transfer_cancel (struct TALER_BANK_TransferHandle *th)
{
  if (NULL != th->job)
  {
    GNUNET_CURL_job_cancel (th->job);
    th->job = NULL;
  }
  TALER_curl_easy_post_finished (&th->post_ctx);
  GNUNET_free (th->request_url);
  GNUNET_free (th);
}


/* end of bank_api_transfer.c */
