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
 * @file lib/exchange_api_batch_withdraw2.c
 * @brief Implementation of /reserves/$RESERVE_PUB/batch-withdraw requests without blinding/unblinding
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A batch withdraw handle
 */
struct TALER_EXCHANGE_BatchWithdraw2Handle
{

  /**
   * The url for this request.
   */
  char *url;

  /**
   * The /keys material from the exchange
   */
  const struct TALER_EXCHANGE_Keys *keys;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_BatchWithdraw2Callback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Context for #TEH_curl_easy_post(). Keeps the data that must
   * persist for Curl to make the upload.
   */
  struct TALER_CURL_PostContext post_ctx;

  /**
   * Total amount requested (value plus withdraw fee).
   */
  struct TALER_Amount requested_amount;

  /**
   * Public key of the reserve we are withdrawing from.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Number of coins expected.
   */
  unsigned int num_coins;
};


/**
 * We got a 200 OK response for the /reserves/$RESERVE_PUB/batch-withdraw operation.
 * Extract the coin's signature and return it to the caller.  The signature we
 * get from the exchange is for the blinded value.  Thus, we first must
 * unblind it and then should verify its validity against our coin's hash.
 *
 * If everything checks out, we return the unblinded signature
 * to the application via the callback.
 *
 * @param wh operation handle
 * @param json reply from the exchange
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static enum GNUNET_GenericReturnValue
reserve_batch_withdraw_ok (struct TALER_EXCHANGE_BatchWithdraw2Handle *wh,
                           const json_t *json)
{
  struct TALER_BlindedDenominationSignature blind_sigs[wh->num_coins];
  const json_t *ja = json_object_get (json,
                                      "ev_sigs");
  const json_t *j;
  unsigned int index;
  struct TALER_EXCHANGE_BatchWithdraw2Response bwr = {
    .hr.reply = json,
    .hr.http_status = MHD_HTTP_OK
  };

  if ( (NULL == ja) ||
       (! json_is_array (ja)) ||
       (wh->num_coins != json_array_size (ja)) )
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  json_array_foreach (ja, index, j)
  {
    struct GNUNET_JSON_Specification spec[] = {
      TALER_JSON_spec_blinded_denom_sig ("ev_sig",
                                         &blind_sigs[index]),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (j,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      for (unsigned int i = 0; i<index; i++)
        TALER_blinded_denom_sig_free (&blind_sigs[i]);
      return GNUNET_SYSERR;
    }
  }

  /* signature is valid, return it to the application */
  bwr.details.ok.blind_sigs = blind_sigs;
  bwr.details.ok.blind_sigs_length = wh->num_coins;
  wh->cb (wh->cb_cls,
          &bwr);
  /* make sure callback isn't called again after return */
  wh->cb = NULL;
  for (unsigned int i = 0; i<wh->num_coins; i++)
    TALER_blinded_denom_sig_free (&blind_sigs[i]);

  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /reserves/$RESERVE_PUB/batch-withdraw request.
 *
 * @param cls the `struct TALER_EXCHANGE_BatchWithdraw2Handle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_reserve_batch_withdraw_finished (void *cls,
                                        long response_code,
                                        const void *response)
{
  struct TALER_EXCHANGE_BatchWithdraw2Handle *wh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_BatchWithdraw2Response bwr = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  wh->job = NULL;
  switch (response_code)
  {
  case 0:
    bwr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        reserve_batch_withdraw_ok (wh,
                                   j))
    {
      GNUNET_break_op (0);
      bwr.hr.http_status = 0;
      bwr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
      break;
    }
    GNUNET_assert (NULL == wh->cb);
    TALER_EXCHANGE_batch_withdraw2_cancel (wh);
    return;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    bwr.hr.ec = TALER_JSON_get_error_code (j);
    bwr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_FORBIDDEN:
    GNUNET_break_op (0);
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    bwr.hr.ec = TALER_JSON_get_error_code (j);
    bwr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, the exchange basically just says
       that it doesn't know this reserve.  Can happen if we
       query before the wire transfer went through.
       We should simply pass the JSON reply to the application. */
    bwr.hr.ec = TALER_JSON_get_error_code (j);
    bwr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_CONFLICT:
    bwr.hr.ec = TALER_JSON_get_error_code (j);
    bwr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_GONE:
    /* could happen if denomination was revoked */
    /* Note: one might want to check /keys for revocation
       signature here, alas tricky in case our /keys
       is outdated => left to clients */
    bwr.hr.ec = TALER_JSON_get_error_code (j);
    bwr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS:
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto (
          "h_payto",
          &bwr.details.unavailable_for_legal_reasons.h_payto),
        GNUNET_JSON_spec_uint64 ("requirement_row",
                                 &bwr.details.unavailable_for_legal_reasons.
                                 kyc_requirement_id),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        bwr.hr.http_status = 0;
        bwr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
    }
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    bwr.hr.ec = TALER_JSON_get_error_code (j);
    bwr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    bwr.hr.ec = TALER_JSON_get_error_code (j);
    bwr.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange batch withdraw\n",
                (unsigned int) response_code,
                (int) bwr.hr.ec);
    break;
  }
  if (NULL != wh->cb)
  {
    wh->cb (wh->cb_cls,
            &bwr);
    wh->cb = NULL;
  }
  TALER_EXCHANGE_batch_withdraw2_cancel (wh);
}


struct TALER_EXCHANGE_BatchWithdraw2Handle *
TALER_EXCHANGE_batch_withdraw2 (
  struct GNUNET_CURL_Context *curl_ctx,
  const char *exchange_url,
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  unsigned int pds_length,
  const struct TALER_PlanchetDetail pds[static pds_length],
  TALER_EXCHANGE_BatchWithdraw2Callback res_cb,
  void *res_cb_cls)
{
  struct TALER_EXCHANGE_BatchWithdraw2Handle *wh;
  const struct TALER_EXCHANGE_DenomPublicKey *dk;
  struct TALER_ReserveSignatureP reserve_sig;
  char arg_str[sizeof (struct TALER_ReservePublicKeyP) * 2 + 32];
  struct TALER_BlindedCoinHashP bch;
  json_t *jc;

  GNUNET_assert (NULL != keys);
  wh = GNUNET_new (struct TALER_EXCHANGE_BatchWithdraw2Handle);
  wh->keys = keys;
  wh->cb = res_cb;
  wh->cb_cls = res_cb_cls;
  wh->num_coins = pds_length;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (keys->currency,
                                        &wh->requested_amount));
  GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                      &wh->reserve_pub.eddsa_pub);
  {
    char pub_str[sizeof (struct TALER_ReservePublicKeyP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &wh->reserve_pub,
      sizeof (struct TALER_ReservePublicKeyP),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "reserves/%s/batch-withdraw",
                     pub_str);
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Attempting to batch-withdraw from reserve %s\n",
              TALER_B2S (&wh->reserve_pub));
  wh->url = TALER_url_join (exchange_url,
                            arg_str,
                            NULL);
  if (NULL == wh->url)
  {
    GNUNET_break (0);
    TALER_EXCHANGE_batch_withdraw2_cancel (wh);
    return NULL;
  }
  jc = json_array ();
  GNUNET_assert (NULL != jc);
  for (unsigned int i = 0; i<pds_length; i++)
  {
    const struct TALER_PlanchetDetail *pd = &pds[i];
    struct TALER_Amount coin_total;
    json_t *withdraw_obj;

    dk = TALER_EXCHANGE_get_denomination_key_by_hash (keys,
                                                      &pd->denom_pub_hash);
    if (NULL == dk)
    {
      TALER_EXCHANGE_batch_withdraw2_cancel (wh);
      json_decref (jc);
      GNUNET_break (0);
      return NULL;
    }
    /* Compute how much we expected to charge to the reserve */
    if (0 >
        TALER_amount_add (&coin_total,
                          &dk->fees.withdraw,
                          &dk->value))
    {
      /* Overflow here? Very strange, our CPU must be fried... */
      GNUNET_break (0);
      TALER_EXCHANGE_batch_withdraw2_cancel (wh);
      json_decref (jc);
      return NULL;
    }
    if (0 >
        TALER_amount_add (&wh->requested_amount,
                          &wh->requested_amount,
                          &coin_total))
    {
      /* Overflow here? Very strange, our CPU must be fried... */
      GNUNET_break (0);
      TALER_EXCHANGE_batch_withdraw2_cancel (wh);
      json_decref (jc);
      return NULL;
    }
    TALER_coin_ev_hash (&pd->blinded_planchet,
                        &pd->denom_pub_hash,
                        &bch);
    TALER_wallet_withdraw_sign (&pd->denom_pub_hash,
                                &coin_total,
                                &bch,
                                reserve_priv,
                                &reserve_sig);
    withdraw_obj = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_data_auto ("denom_pub_hash",
                                  &pd->denom_pub_hash),
      TALER_JSON_pack_blinded_planchet ("coin_ev",
                                        &pd->blinded_planchet),
      GNUNET_JSON_pack_data_auto ("reserve_sig",
                                  &reserve_sig));
    GNUNET_assert (NULL != withdraw_obj);
    GNUNET_assert (0 ==
                   json_array_append_new (jc,
                                          withdraw_obj));
  }
  {
    CURL *eh;
    json_t *req;

    req = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_array_steal ("planchets",
                                    jc));
    eh = TALER_EXCHANGE_curl_easy_get_ (wh->url);
    if ( (NULL == eh) ||
         (GNUNET_OK !=
          TALER_curl_easy_post (&wh->post_ctx,
                                eh,
                                req)) )
    {
      GNUNET_break (0);
      if (NULL != eh)
        curl_easy_cleanup (eh);
      json_decref (req);
      TALER_EXCHANGE_batch_withdraw2_cancel (wh);
      return NULL;
    }
    json_decref (req);
    wh->job = GNUNET_CURL_job_add2 (curl_ctx,
                                    eh,
                                    wh->post_ctx.headers,
                                    &handle_reserve_batch_withdraw_finished,
                                    wh);
  }
  return wh;
}


void
TALER_EXCHANGE_batch_withdraw2_cancel (
  struct TALER_EXCHANGE_BatchWithdraw2Handle *wh)
{
  if (NULL != wh->job)
  {
    GNUNET_CURL_job_cancel (wh->job);
    wh->job = NULL;
  }
  GNUNET_free (wh->url);
  TALER_curl_easy_post_finished (&wh->post_ctx);
  GNUNET_free (wh);
}
