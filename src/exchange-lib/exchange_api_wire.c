/*
  This file is part of TALER
  Copyright (C) 2014, 2015 GNUnet e.V.

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
 * @file exchange-lib/exchange_api_wire.c
 * @brief Implementation of the /wire request of the exchange's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "taler_wire_plugin.h"
#include "exchange_api_common.h"
#include "exchange_api_context.h"
#include "exchange_api_handle.h"


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
  struct MAC_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_WireResultCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Download buffer
   */
  struct MAC_DownloadBuffer db;

  /**
   * Set to the "methods" JSON array returned by the
   * /wire request.
   */
  json_t *methods;

  /**
   * Current iteration offset in the @e methods array.
   */
  unsigned int methods_off;

};


/**
 * Verify that the signature on the "200 OK" response
 * for /wire/METHOD from the exchange is valid.
 *
 * @param wh wire handle with key material
 * @param method method to verify the reply for
 * @param json json reply with the signature
 * @return #GNUNET_SYSERR if @a json is invalid,
 *         #GNUNET_NO if the method is unknown,
 *         #GNUNET_OK if the json is valid
 */
static int
verify_wire_method_signature_ok (const struct TALER_EXCHANGE_WireHandle *wh,
                                 const char *method,
                                 json_t *json)
{
  const struct TALER_EXCHANGE_Keys *key_state;
  struct TALER_WIRE_Plugin *plugin;
  char *lib_name;
  int ret;

  key_state = TALER_EXCHANGE_get_keys (wh->exchange);
  (void) GNUNET_asprintf (&lib_name,
                          "libtaler_plugin_wire_%s",
                          method);
  plugin = GNUNET_PLUGIN_load (lib_name,
                               NULL);
  if (NULL == plugin)
  {
    GNUNET_free (lib_name);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Wire transfer method `%s' not supported\n",
                method);
    return GNUNET_NO;
  }
  plugin->library_name = lib_name;
  ret = plugin->wire_validate (plugin->cls,
                               json,
                               &key_state->master_pub);
  GNUNET_PLUGIN_unload (lib_name,
                        plugin);
  GNUNET_free (lib_name);
  return (GNUNET_YES == ret) ? GNUNET_OK : GNUNET_SYSERR;
}


/**
 * Perform the next /wire/method request or signal
 * the end of the iteration.
 *
 * @param wh the wire handle
 * @return a handle for this request
 */
static void
request_wire_method (struct TALER_EXCHANGE_WireHandle *wh);


/**
 * Function called when we're done processing the
 * HTTP /wire/METHOD request.
 *
 * @param cls the `struct TALER_EXCHANGE_WireHandle`
 * @param eh the curl request handle
 */
static void
handle_wire_method_finished (void *cls,
                             CURL *eh)
{
  struct TALER_EXCHANGE_WireHandle *wh = cls;
  long response_code;
  json_t *json;

  wh->job = NULL;
  json = MAC_download_get_result (&wh->db,
                                  eh,
                                  &response_code);
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    {
      const char *method;

      method = json_string_value (json_array_get (wh->methods,
                                                  wh->methods_off - 1));
      if (GNUNET_OK !=
          verify_wire_method_signature_ok (wh,
                                           method,
                                           json))
      {
        GNUNET_break_op (0);
        response_code = 0;
        break;
      }
      break;
    }
  case MHD_HTTP_FOUND:
    /* /wire/test returns a 302 redirect, we should just give
       this information back to the callback below */
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
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
  if (0 == response_code)
  {
    /* signal end of iteration */
    wh->cb (wh->cb_cls,
            0,
            NULL,
            NULL);
    json_decref (json);
    TALER_EXCHANGE_wire_cancel (wh);
    return;
  }
  /* pass on successful reply */
  wh->cb (wh->cb_cls,
          response_code,
          json_string_value (json_array_get (wh->methods,
                                             wh->methods_off-1)),
          json);
  json_decref (json);
  /* trigger request for the next /wire/method */
  request_wire_method (wh);
}


/**
 * Perform the next /wire/method request or signal
 * the end of the iteration.
 *
 * @param wh the wire handle
 * @return a handle for this request
 */
static void
request_wire_method (struct TALER_EXCHANGE_WireHandle *wh)
{
  struct TALER_EXCHANGE_Context *ctx;
  CURL *eh;
  char *path;

  if (json_array_size (wh->methods) <= wh->methods_off)
  {
    /* we are done, signal end of iteration */
    wh->cb (wh->cb_cls,
            0,
            NULL,
            NULL);
    TALER_EXCHANGE_wire_cancel (wh);
    return;
  }
  GNUNET_free_non_null (wh->db.buf);
  wh->db.buf = NULL;
  wh->db.buf_size = 0;
  wh->db.eno = 0;
  GNUNET_free_non_null (wh->url);
  GNUNET_asprintf (&path,
                   "/wire/%s",
                   json_string_value (json_array_get (wh->methods,
                                                      wh->methods_off++)));
  wh->url = MAH_path_to_url (wh->exchange,
                             path);
  GNUNET_free (path);

  eh = curl_easy_init ();
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   wh->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEFUNCTION,
                                   &MAC_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEDATA,
                                   &wh->db));
  /* The default is 'disabled', but let's be sure */
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_FOLLOWLOCATION,
                                   (long) 0));
  ctx = MAH_handle_to_context (wh->exchange);
  wh->job = MAC_job_add (ctx,
                         eh,
                         GNUNET_YES,
                         &handle_wire_method_finished,
                         wh);
  TALER_EXCHANGE_perform (ctx);
}


/**
 * Verify that the signature on the "200 OK" response
 * for /wire from the exchange is valid.
 *
 * @param wh wire handle
 * @param json json reply with the signature
 * @return NULL if @a json is invalid, otherwise the
 *         "methods" array (with an RC of 1)
 */
static json_t *
verify_wire_signature_ok (const struct TALER_EXCHANGE_WireHandle *wh,
                          json_t *json)
{
  struct TALER_ExchangeSignatureP exchange_sig;
  struct TALER_ExchangePublicKeyP exchange_pub;
  struct TALER_ExchangeWireSupportMethodsPS mp;
  json_t *methods;
  const struct TALER_EXCHANGE_Keys *key_state;
  struct GNUNET_HashContext *hc;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("sig", &exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("pub", &exchange_pub),
    GNUNET_JSON_spec_json ("methods", &methods),
    GNUNET_JSON_spec_end()
  };
  unsigned int i;

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return NULL;
  }
  if (! json_is_array (methods))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return NULL;
  }

  key_state = TALER_EXCHANGE_get_keys (wh->exchange);
  if (GNUNET_OK !=
      TALER_EXCHANGE_test_signing_key (key_state,
                                   &exchange_pub))
  {
    GNUNET_break_op (0);
    return NULL;
  }
  hc = GNUNET_CRYPTO_hash_context_start ();
  for (i=0;i<json_array_size (methods);i++)
  {
    const json_t *element = json_array_get (methods, i);
    const char *method;

    if (! json_is_string (element))
    {
      GNUNET_CRYPTO_hash_context_abort (hc);
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
      return NULL;
    }
    method = json_string_value (element);
    GNUNET_CRYPTO_hash_context_read (hc,
                                     method,
                                     strlen (method) + 1);
  }
  mp.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_WIRE_TYPES);
  mp.purpose.size = htonl (sizeof (struct TALER_ExchangeWireSupportMethodsPS));
  GNUNET_CRYPTO_hash_context_finish (hc,
                                     &mp.h_wire_types);

  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_WIRE_TYPES,
                                  &mp.purpose,
                                  &exchange_sig.eddsa_signature,
                                  &exchange_pub.eddsa_pub))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return NULL;
  }
  return methods;
}


/**
 * Function called when we're done processing the
 * HTTP /wire request.
 *
 * @param cls the `struct TALER_EXCHANGE_WireHandle`
 * @param eh the curl request handle
 */
static void
handle_wire_finished (void *cls,
                      CURL *eh)
{
  struct TALER_EXCHANGE_WireHandle *wh = cls;
  long response_code;
  json_t *json;

  wh->job = NULL;
  json = MAC_download_get_result (&wh->db,
                                  eh,
                                  &response_code);
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    {
      json_t *methods;

      if (NULL ==
          (methods = verify_wire_signature_ok (wh,
                                               json)))
      {
        GNUNET_break_op (0);
        response_code = 0;
        break;
      }
      wh->methods = methods;
      request_wire_method (wh);
      return;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
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
  if (0 != response_code)
  {
    /* pass on successful reply */
    wh->cb (wh->cb_cls,
            response_code,
            NULL,
            json);
  }
  /* signal end of iteration */
  wh->cb (wh->cb_cls,
          0,
          NULL,
          NULL);
  if (NULL != json)
    json_decref (json);
  TALER_EXCHANGE_wire_cancel (wh);
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
                 TALER_EXCHANGE_WireResultCallback wire_cb,
                 void *wire_cb_cls)
{
  struct TALER_EXCHANGE_WireHandle *wh;
  struct TALER_EXCHANGE_Context *ctx;
  CURL *eh;

  if (GNUNET_YES !=
      MAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  wh = GNUNET_new (struct TALER_EXCHANGE_WireHandle);
  wh->exchange = exchange;
  wh->cb = wire_cb;
  wh->cb_cls = wire_cb_cls;
  wh->url = MAH_path_to_url (exchange, "/wire");

  eh = curl_easy_init ();
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   wh->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEFUNCTION,
                                   &MAC_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEDATA,
                                   &wh->db));
  ctx = MAH_handle_to_context (exchange);
  wh->job = MAC_job_add (ctx,
                         eh,
                         GNUNET_YES,
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
    MAC_job_cancel (wh->job);
    wh->job = NULL;
  }
  if (NULL != wh->methods)
  {
    json_decref (wh->methods);
    wh->methods = NULL;
  }
  GNUNET_free_non_null (wh->db.buf);
  GNUNET_free (wh->url);
  GNUNET_free (wh);
}


/* end of exchange_api_wire.c */
