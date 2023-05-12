/*
  This file is part of TALER
  Copyright (C) 2017-2023 Taler Systems SA

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
 * @file lib/exchange_api_recoup.c
 * @brief Implementation of the /recoup request of the exchange's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_json_lib.h"
#include "taler_exchange_service.h"
#include "exchange_api_common.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A Recoup Handle
 */
struct TALER_EXCHANGE_RecoupHandle
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
   * Context for #TEH_curl_easy_post(). Keeps the data that must
   * persist for Curl to make the upload.
   */
  struct TALER_CURL_PostContext ctx;

  /**
   * Denomination key of the coin.
   */
  struct TALER_EXCHANGE_DenomPublicKey pk;

  /**
   * Our signature requesting the recoup.
   */
  struct TALER_CoinSpendSignatureP coin_sig;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_RecoupResultCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Public key of the coin we are trying to get paid back.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

};


/**
 * Parse a recoup response.  If it is valid, call the callback.
 *
 * @param ph recoup handle
 * @param json json reply with the signature
 * @return #GNUNET_OK if the signature is valid and we called the callback;
 *         #GNUNET_SYSERR if not (callback must still be called)
 */
static enum GNUNET_GenericReturnValue
process_recoup_response (const struct TALER_EXCHANGE_RecoupHandle *ph,
                         const json_t *json)
{
  struct TALER_EXCHANGE_RecoupResponse rr = {
    .hr.reply = json,
    .hr.http_status = MHD_HTTP_OK
  };
  struct GNUNET_JSON_Specification spec_withdraw[] = {
    GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                 &rr.details.ok.reserve_pub),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec_withdraw,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  ph->cb (ph->cb_cls,
          &rr);
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /recoup request.
 *
 * @param cls the `struct TALER_EXCHANGE_RecoupHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_recoup_finished (void *cls,
                        long response_code,
                        const void *response)
{
  struct TALER_EXCHANGE_RecoupHandle *ph = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_RecoupResponse rr = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };
  const struct TALER_EXCHANGE_Keys *keys;

  ph->job = NULL;
  keys = TALER_EXCHANGE_get_keys (ph->exchange);
  switch (response_code)
  {
  case 0:
    rr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        process_recoup_response (ph,
                                 j))
    {
      GNUNET_break_op (0);
      rr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
      rr.hr.http_status = 0;
      break;
    }
    TALER_EXCHANGE_recoup_cancel (ph);
    return;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    rr.hr.ec = TALER_JSON_get_error_code (j);
    rr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_CONFLICT:
    {
      struct TALER_Amount min_key;

      rr.hr.ec = TALER_JSON_get_error_code (j);
      rr.hr.hint = TALER_JSON_get_error_hint (j);
      if (GNUNET_OK !=
          TALER_EXCHANGE_get_min_denomination_ (keys,
                                                &min_key))
      {
        GNUNET_break (0);
        rr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        rr.hr.http_status = 0;
        break;
      }
      if (GNUNET_OK !=
          TALER_EXCHANGE_check_coin_conflict_ (
            keys,
            j,
            &ph->pk,
            &ph->coin_pub,
            &ph->coin_sig,
            &min_key))
      {
        GNUNET_break (0);
        rr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        rr.hr.http_status = 0;
        break;
      }
      break;
    }
  case MHD_HTTP_FORBIDDEN:
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    rr.hr.ec = TALER_JSON_get_error_code (j);
    rr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    rr.hr.ec = TALER_JSON_get_error_code (j);
    rr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_GONE:
    /* Kind of normal: the money was already sent to the merchant
       (it was too late for the refund). */
    rr.hr.ec = TALER_JSON_get_error_code (j);
    rr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    rr.hr.ec = TALER_JSON_get_error_code (j);
    rr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  default:
    /* unexpected response code */
    rr.hr.ec = TALER_JSON_get_error_code (j);
    rr.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange recoup\n",
                (unsigned int) response_code,
                (int) rr.hr.ec);
    GNUNET_break (0);
    break;
  }
  ph->cb (ph->cb_cls,
          &rr);
  TALER_EXCHANGE_recoup_cancel (ph);
}


struct TALER_EXCHANGE_RecoupHandle *
TALER_EXCHANGE_recoup (struct TALER_EXCHANGE_Handle *exchange,
                       const struct TALER_EXCHANGE_DenomPublicKey *pk,
                       const struct TALER_DenominationSignature *denom_sig,
                       const struct TALER_ExchangeWithdrawValues *exchange_vals,
                       const struct TALER_PlanchetMasterSecretP *ps,
                       TALER_EXCHANGE_RecoupResultCallback recoup_cb,
                       void *recoup_cb_cls)
{
  struct TALER_EXCHANGE_RecoupHandle *ph;
  struct GNUNET_CURL_Context *ctx;
  struct TALER_DenominationHashP h_denom_pub;
  json_t *recoup_obj;
  CURL *eh;
  char arg_str[sizeof (struct TALER_CoinSpendPublicKeyP) * 2 + 32];
  struct TALER_CoinSpendPrivateKeyP coin_priv;
  union TALER_DenominationBlindingKeyP bks;

  GNUNET_assert (GNUNET_YES ==
                 TEAH_handle_is_ready (exchange));
  ph = GNUNET_new (struct TALER_EXCHANGE_RecoupHandle);
  TALER_planchet_setup_coin_priv (ps,
                                  exchange_vals,
                                  &coin_priv);
  TALER_planchet_blinding_secret_create (ps,
                                         exchange_vals,
                                         &bks);
  GNUNET_CRYPTO_eddsa_key_get_public (&coin_priv.eddsa_priv,
                                      &ph->coin_pub.eddsa_pub);
  TALER_denom_pub_hash (&pk->key,
                        &h_denom_pub);
  TALER_wallet_recoup_sign (&h_denom_pub,
                            &bks,
                            &coin_priv,
                            &ph->coin_sig);
  recoup_obj = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_data_auto ("denom_pub_hash",
                                &h_denom_pub),
    TALER_JSON_pack_denom_sig ("denom_sig",
                               denom_sig),
    TALER_JSON_pack_exchange_withdraw_values ("ewv",
                                              exchange_vals),
    GNUNET_JSON_pack_data_auto ("coin_sig",
                                &ph->coin_sig),
    GNUNET_JSON_pack_data_auto ("coin_blind_key_secret",
                                &bks));
  if (TALER_DENOMINATION_CS == denom_sig->cipher)
  {
    struct TALER_CsNonce nonce;

    /* NOTE: this is not elegant, and as per the note in TALER_coin_ev_hash()
       it is not strictly clear that the nonce is needed. Best case would be
       to find a way to include it more 'naturally' somehow, for example with
       the variant union version of bks! */
    TALER_cs_withdraw_nonce_derive (ps,
                                    &nonce);
    GNUNET_assert (
      0 ==
      json_object_set_new (recoup_obj,
                           "cs_nonce",
                           GNUNET_JSON_from_data_auto (
                             &nonce)));
  }

  {
    char pub_str[sizeof (struct TALER_CoinSpendPublicKeyP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &ph->coin_pub,
      sizeof (struct TALER_CoinSpendPublicKeyP),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/coins/%s/recoup",
                     pub_str);
  }

  ph->exchange = exchange;
  ph->pk = *pk;
  memset (&ph->pk.key,
          0,
          sizeof (ph->pk.key)); /* zero out, as lifetime cannot be warranted */
  ph->cb = recoup_cb;
  ph->cb_cls = recoup_cb_cls;
  ph->url = TEAH_path_to_url (exchange,
                              arg_str);
  if (NULL == ph->url)
  {
    json_decref (recoup_obj);
    GNUNET_free (ph);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (ph->url);
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&ph->ctx,
                              eh,
                              recoup_obj)) )
  {
    GNUNET_break (0);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (recoup_obj);
    GNUNET_free (ph->url);
    GNUNET_free (ph);
    return NULL;
  }
  json_decref (recoup_obj);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "URL for recoup: `%s'\n",
              ph->url);
  ctx = TEAH_handle_to_context (exchange);
  ph->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  ph->ctx.headers,
                                  &handle_recoup_finished,
                                  ph);
  return ph;
}


void
TALER_EXCHANGE_recoup_cancel (struct TALER_EXCHANGE_RecoupHandle *ph)
{
  if (NULL != ph->job)
  {
    GNUNET_CURL_job_cancel (ph->job);
    ph->job = NULL;
  }
  GNUNET_free (ph->url);
  TALER_curl_easy_post_finished (&ph->ctx);
  GNUNET_free (ph);
}


/* end of exchange_api_recoup.c */
