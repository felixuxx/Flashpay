/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 Inria and GNUnet e.V.

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
 * @file exchange-lib/exchange_api_wire.c
 * @brief Implementation of the /wire request of the exchange's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "taler_signatures.h"
#include "taler_wire_plugin.h"
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
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_WireResultCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

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
                                 const json_t *json)
{
  const struct TALER_EXCHANGE_Keys *key_state;
  struct TALER_WIRE_Plugin *plugin;
  char *lib_name;
  char *emsg;
  enum TALER_ErrorCode ec;

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
  ec = plugin->wire_validate (plugin->cls,
                              json,
                              &key_state->master_pub,
                              &emsg);
  GNUNET_free_non_null (emsg);
  GNUNET_PLUGIN_unload (lib_name,
                        plugin);
  GNUNET_free (lib_name);
  return (TALER_EC_NONE == ec) ? GNUNET_OK : GNUNET_SYSERR;
}


/**
 * Function called when we're done processing the
 * HTTP /wire request.
 *
 * @param cls the `struct TALER_EXCHANGE_WireHandle`
 * @param response_code HTTP response code, 0 on error
 * @param json parsed JSON result, NULL on error
 */
static void
handle_wire_finished (void *cls,
                      long response_code,
                      const json_t *json)
{
  struct TALER_EXCHANGE_WireHandle *wh = cls;
  json_t *keep = NULL;

  wh->job = NULL;
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    {
      const struct TALER_EXCHANGE_Keys *keys;
      const struct TALER_MasterPublicKeyP *master_pub;
      const char *key;
      json_t *method;
      int ret;

      /* We 'keep' methods that we support and that are well-formed;
         we fail (by setting response_code=0) if any method that we do
         support fails to verify. */
      keep = json_object ();
      json_object_foreach ((json_t *) json, key, method) {
        ret = verify_wire_method_signature_ok (wh,
                                               key,
                                               method);
        if (GNUNET_SYSERR == ret)
        {
          /* bogus reply */
          GNUNET_break_op (0);
          response_code = 0;
        }
        /* GNUNET_NO: not understood by us, simply skip! */
        if (GNUNET_OK == ret)
        {
          /* supported and valid, keep! */
          json_object_set (keep,
                           key,
                           method);
        }
      }
      /* check fees */
      keys = TALER_EXCHANGE_get_keys (wh->exchange);
      if (NULL == keys)
        master_pub = NULL;
      else
        master_pub = &keys->master_pub;
      if (GNUNET_OK !=
          TALER_EXCHANGE_wire_get_fees (master_pub,
                                        keep,
                                        NULL,
                                        NULL))
      {
        /* bogus reply */
        GNUNET_break_op (0);
        response_code = 0;
      }
      if (0 != response_code)
      {
        /* all supported methods were valid, use 'keep' for 'json' */
        break;
      }
      /* some supported methods were invalid, release 'keep', preserve
         full 'json' for application-level error handling. */
      json_decref (keep);
      keep = NULL;
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
                (unsigned int) response_code);
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  wh->cb (wh->cb_cls,
          response_code,
	  TALER_JSON_get_error_code (json),
          (NULL != keep) ? keep : json);
  if (NULL != keep)
    json_decref (keep);
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
  struct GNUNET_CURL_Context *ctx;
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
  ctx = MAH_handle_to_context (exchange);
  wh->job = GNUNET_CURL_job_add (ctx,
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
    GNUNET_CURL_job_cancel (wh->job);
    wh->job = NULL;
  }
  if (NULL != wh->methods)
  {
    json_decref (wh->methods);
    wh->methods = NULL;
  }
  GNUNET_free (wh->url);
  GNUNET_free (wh);
}


/**
 * Parse wire @a fee and store the result in @a af.
 *
 * @param[out] af where to write the result
 * @param fee json AggregateTransferFee to parse
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
parse_json_fees (struct TALER_EXCHANGE_WireAggregateFees *af,
                 json_t *fee)
{
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("sig",
                                 &af->master_sig),
    TALER_JSON_spec_amount ("wire_fee",
                            &af->wire_fee),
    GNUNET_JSON_spec_absolute_time ("start_date",
                                    &af->start_date),
    GNUNET_JSON_spec_absolute_time ("end_date",
                                    &af->end_date),
    GNUNET_JSON_spec_end()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (fee,
                         spec,
                         NULL,
                         NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Check the #TALER_SIGNATURE_MASTER_WIRE_FEES signature.
 *
 * @param af record to check
 * @param wire_method wire method to check against
 * @param master_pub expected signing key
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on failure
 */
static int
check_sig (const struct TALER_EXCHANGE_WireAggregateFees *af,
           const char *wire_method,
           const struct TALER_MasterPublicKeyP *master_pub)
{
  struct TALER_MasterWireFeePS wp;

  wp.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_WIRE_FEES);
  wp.purpose.size = htonl (sizeof (wp));
  GNUNET_CRYPTO_hash (wire_method,
                      strlen (wire_method) + 1,
                      &wp.h_wire_method);
  wp.start_date = GNUNET_TIME_absolute_hton (af->start_date);
  wp.end_date = GNUNET_TIME_absolute_hton (af->end_date);
  TALER_amount_hton (&wp.wire_fee,
                     &af->wire_fee);
  return GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_WIRE_FEES,
                                     &wp.purpose,
                                     &af->master_sig.eddsa_signature,
                                     &master_pub->eddsa_pub);
}


/**
 * Obtain information about wire fees encoded in @a obj
 * by wire method.
 *
 * @param master_pub public key to use to verify signatures, NULL to not verify
 * @param obj wire information as encoded in the #TALER_EXCHANGE_WireResultCallback
 * @param cb callback to invoke for the fees
 * @param cb_cls closure for @a cb
 * @return #GNUNET_OK in success, #GNUNET_SYSERR if @a obj is ill-formed
 */
int
TALER_EXCHANGE_wire_get_fees (const struct TALER_MasterPublicKeyP *master_pub,
                              const json_t *obj,
                              TALER_EXCHANGE_WireFeeCallback cb,
                              void *cb_cls)
{
  const char *wire_method;
  json_t *value;

  json_object_foreach (((json_t *) obj), wire_method, value)
  {
    json_t *fees;
    size_t num_fees;

    fees = json_object_get (value, "fees");
    if ( (NULL == fees) ||
         (! json_is_array (fees)) )
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    num_fees = json_array_size (fees);
    if (num_fees > 1024)
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    {
      struct TALER_EXCHANGE_WireAggregateFees af[num_fees + 1];

      for (size_t i=0;i<num_fees;i++)
      {
        af[i].next = &af[i+1];
        if (GNUNET_OK !=
            parse_json_fees (&af[i],
                             json_array_get (fees,
                                             i)))
        {
          GNUNET_break_op (0);
          return GNUNET_SYSERR;
        }
        if ( (NULL != master_pub) &&
             (GNUNET_OK !=
              check_sig (&af[i],
                         wire_method,
                         master_pub)) )
        {
          GNUNET_break_op (0);
          return GNUNET_SYSERR;
        }
      }
      af[num_fees].next = NULL;
      if (NULL != cb)
        cb (cb_cls,
            wire_method,
            &af[0]);
    }
  }
  return GNUNET_OK;
}


/* end of exchange_api_wire.c */
