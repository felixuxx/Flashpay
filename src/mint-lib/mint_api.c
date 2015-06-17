/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

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
 * @file mint-lib/mint_api.c
 * @brief Implementation of the client interface to mint's HTTP API
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include <curl/curl.h>
#include <jansson.h>
#include <gnunet/gnunet_util_lib.h>
#include "taler_mint_service.h"
#include "taler_signatures.h"


// leftovers follow...

/**
 * Log error related to CURL operations.
 *
 * @param type log level
 * @param function which function failed to run
 * @param code what was the curl error code
 */
#define CURL_STRERROR(type, function, code)      \
 GNUNET_log (type, "Curl function `%s' has failed at `%s:%d' with error: %s", \
             function, __FILE__, __LINE__, curl_easy_strerror (code));


/**
 * Print JSON parsing related error information
 */
#define JSON_WARN(error)                                                \
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,                              \
                "JSON parsing failed at %s:%u: %s (%s)",                \
                __FILE__, __LINE__, error.text, error.source)

/**
 * Failsafe flag. Raised if our constructor fails to initialize
 * the Curl library.
 */
static int TALER_MINT_curl_fail;

/**
 * A handle to submit a deposit permission and get its status
 */
struct TALER_MINT_DepositHandle
{
  /**
   *The connection to mint this request handle will use
   */
  struct TALER_MINT_Handle *mint;

  /**
   * The url for this handle
   */
  char *url;

  TALER_MINT_DepositResultCallback cb;

  void *cb_cls;

  char *json_enc;

  struct curl_slist *headers;

};



#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)



static int
parse_deposit_response (void *buf, size_t size, int *r_status, json_t **r_obj)
{
  json_t *obj;
  const char *status_str;
  json_error_t error;

  status_str = NULL;
  obj = NULL;
  obj = json_loadb (buf, size,
                    JSON_REJECT_DUPLICATES | JSON_DISABLE_EOF_CHECK, &error);
  if (NULL == obj)
  {
    JSON_WARN (error);
    return GNUNET_SYSERR;
  }
  EXITIF (-1 == json_unpack (obj, "{s:s}", "status", &status_str));
  TALER_LOG_DEBUG ("Received deposit response: %s from mint\n", status_str);
  if (0 == strcmp ("DEPOSIT_OK", status_str))
    *r_status = 1;
  else if (0 == strcmp ("DEPOSIT_QUEUED", status_str))
    *r_status = 2;
  else
    *r_status = 0;
  *r_obj = obj;

  return GNUNET_OK;
 EXITIF_exit:
  json_decref (obj);
  return GNUNET_SYSERR;
}

#undef EXITIF


/**
 * Submit a deposit permission to the mint and get the mint's response
 *
 * @param mint the mint handle
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @param deposit_obj the deposit permission received from the customer along
 *         with the wireformat JSON object
 * @return a handle for this request; NULL if the JSON object could not be
 *         parsed or is of incorrect format or any other error.  In this case,
 *         the callback is not called.
 */
struct TALER_MINT_DepositHandle *
TALER_MINT_deposit_submit_json (struct TALER_MINT_Handle *mint,
                                TALER_MINT_DepositResultCallback cb,
                                void *cb_cls,
                                json_t *deposit_obj)
{
  struct TALER_MINT_DepositHandle *dh;

  GNUNET_assert (REQUEST_TYPE_NONE == mint->req_type);
  dh = GNUNET_new (struct TALER_MINT_DepositHandle);
  dh->mint = mint;
  mint->req_type = REQUEST_TYPE_DEPOSIT;
  mint->req.deposit = dh;
  dh->cb = cb;
  dh->cb_cls = cb_cls;
  GNUNET_asprintf (&dh->url, "http://%s:%hu/deposit", mint->hostname, mint->port);
  GNUNET_assert (NULL != (dh->json_enc = json_dumps (deposit_obj, JSON_COMPACT)));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (mint->curl, CURLOPT_URL, dh->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (mint->curl, CURLOPT_POSTFIELDS,
                                   dh->json_enc));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (mint->curl, CURLOPT_POSTFIELDSIZE,
                                   strlen (dh->json_enc)));
  GNUNET_assert (NULL != (dh->headers =
                          curl_slist_append (dh->headers, "Content-Type: application/json")));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (mint->curl, CURLOPT_HTTPHEADER, dh->headers));
  if (GNUNET_NO == mint->connected)
    mint_connect (mint);
  perform_now (mint->ctx);
  return dh;
}


/* end of mint_api.c */
