/*
  This file is part of TALER
  Copyright (C) 2015-2021 Taler Systems SA

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
 * @file lib/exchange_api_refreshes_reveal.c
 * @brief Implementation of the /refreshes/$RCH/reveal requests
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
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"
#include "exchange_api_refresh_common.h"


/**
 * @brief A /refreshes/$RCH/reveal Handle
 */
struct TALER_EXCHANGE_RefreshesRevealHandle
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
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_RefreshesRevealCallback reveal_cb;

  /**
   * Closure for @e reveal_cb.
   */
  void *reveal_cb_cls;

  /**
   * Actual information about the melt operation.
   */
  struct MeltData *md;

  /**
   * The index selected by the exchange in cut-and-choose to not be revealed.
   */
  uint16_t noreveal_index;

};


/**
 * We got a 200 OK response for the /refreshes/$RCH/reveal operation.
 * Extract the coin signatures and return them to the caller.
 * The signatures we get from the exchange is for the blinded value.
 * Thus, we first must unblind them and then should verify their
 * validity.
 *
 * If everything checks out, we return the unblinded signatures
 * to the application via the callback.
 *
 * @param rrh operation handle
 * @param json reply from the exchange
 * @param[out] sigs array of length `num_fresh_coins`, initialized to contain RSA signatures
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static int
refresh_reveal_ok (struct TALER_EXCHANGE_RefreshesRevealHandle *rrh,
                   const json_t *json,
                   struct TALER_DenominationSignature *sigs)
{
  json_t *jsona;
  struct GNUNET_JSON_Specification outer_spec[] = {
    GNUNET_JSON_spec_json ("ev_sigs", &jsona),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         outer_spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (! json_is_array (jsona))
  {
    /* We expected an array of coins */
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (outer_spec);
    return GNUNET_SYSERR;
  }
  if (rrh->md->num_fresh_coins != json_array_size (jsona))
  {
    /* Number of coins generated does not match our expectation */
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (outer_spec);
    return GNUNET_SYSERR;
  }
  for (unsigned int i = 0; i<rrh->md->num_fresh_coins; i++)
  {
    const struct TALER_PlanchetSecretsP *fc;
    struct TALER_DenominationPublicKey *pk;
    json_t *jsonai;
    struct GNUNET_CRYPTO_RsaSignature *blind_sig;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct GNUNET_HashCode coin_hash;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_rsa_signature ("ev_sig", &blind_sig),
      GNUNET_JSON_spec_end ()
    };
    struct TALER_FreshCoin coin;

    fc = &rrh->md->fresh_coins[rrh->noreveal_index][i];
    pk = &rrh->md->fresh_pks[i];
    jsonai = json_array_get (jsona, i);
    GNUNET_assert (NULL != jsonai);

    if (GNUNET_OK !=
        GNUNET_JSON_parse (jsonai,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (outer_spec);
      return GNUNET_SYSERR;
    }

    /* needed to verify the signature, and we didn't store it earlier,
       hence recomputing it here... */
    GNUNET_CRYPTO_eddsa_key_get_public (&fc->coin_priv.eddsa_priv,
                                        &coin_pub.eddsa_pub);
    GNUNET_CRYPTO_hash (&coin_pub.eddsa_pub,
                        sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                        &coin_hash);
    if (GNUNET_OK !=
        TALER_planchet_to_coin (pk,
                                blind_sig,
                                fc,
                                &coin_hash,
                                &coin))
    {
      GNUNET_break_op (0);
      GNUNET_CRYPTO_rsa_signature_free (blind_sig);
      GNUNET_JSON_parse_free (outer_spec);
      return GNUNET_SYSERR;
    }
    GNUNET_CRYPTO_rsa_signature_free (blind_sig);
    sigs[i] = coin.sig;
  }
  GNUNET_JSON_parse_free (outer_spec);
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /refreshes/$RCH/reveal request.
 *
 * @param cls the `struct TALER_EXCHANGE_RefreshHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_refresh_reveal_finished (void *cls,
                                long response_code,
                                const void *response)
{
  struct TALER_EXCHANGE_RefreshesRevealHandle *rrh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .reply = j,
    .http_status = (unsigned int) response_code
  };

  rrh->job = NULL;
  switch (response_code)
  {
  case 0:
    hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      struct TALER_DenominationSignature sigs[rrh->md->num_fresh_coins];
      int ret;

      memset (sigs, 0, sizeof (sigs));
      ret = refresh_reveal_ok (rrh,
                               j,
                               sigs);
      if (GNUNET_OK != ret)
      {
        hr.http_status = 0;
        hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
      }
      else
      {
        rrh->reveal_cb (rrh->reveal_cb_cls,
                        &hr,
                        rrh->md->num_fresh_coins,
                        rrh->md->fresh_coins[rrh->noreveal_index],
                        sigs);
        rrh->reveal_cb = NULL;
      }
      for (unsigned int i = 0; i<rrh->md->num_fresh_coins; i++)
        if (NULL != sigs[i].rsa_signature)
          GNUNET_CRYPTO_rsa_signature_free (sigs[i].rsa_signature);
      TALER_EXCHANGE_refreshes_reveal_cancel (rrh);
      return;
    }
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_CONFLICT:
    /* Nothing really to verify, exchange says our reveal is inconsistent
       with our commitment, so either side is buggy; we
       should pass the JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_GONE:
    /* Server claims key expired or has been revoked */
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
                "Unexpected response code %u/%d for exchange refreshes reveal\n",
                (unsigned int) response_code,
                (int) hr.ec);
    break;
  }
  if (NULL != rrh->reveal_cb)
    rrh->reveal_cb (rrh->reveal_cb_cls,
                    &hr,
                    0,
                    NULL,
                    NULL);
  TALER_EXCHANGE_refreshes_reveal_cancel (rrh);
}


struct TALER_EXCHANGE_RefreshesRevealHandle *
TALER_EXCHANGE_refreshes_reveal (
  struct TALER_EXCHANGE_Handle *exchange,
  size_t refresh_data_length,
  const char *refresh_data,
  uint32_t noreveal_index,
  TALER_EXCHANGE_RefreshesRevealCallback reveal_cb,
  void *reveal_cb_cls)
{
  struct TALER_EXCHANGE_RefreshesRevealHandle *rrh;
  json_t *transfer_privs;
  json_t *new_denoms_h;
  json_t *coin_evs;
  json_t *reveal_obj;
  json_t *link_sigs;
  CURL *eh;
  struct GNUNET_CURL_Context *ctx;
  struct MeltData *md;
  struct TALER_TransferPublicKeyP transfer_pub;
  char arg_str[sizeof (struct TALER_RefreshCommitmentP) * 2 + 32];

  if (noreveal_index >= TALER_CNC_KAPPA)
  {
    /* We check this here, as it would be really bad to below just
       disclose all the transfer keys. Note that this error should
       have been caught way earlier when the exchange replied, but maybe
       we had some internal corruption that changed the value... */
    GNUNET_break (0);
    return NULL;
  }
  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  md = TALER_EXCHANGE_deserialize_melt_data_ (refresh_data,
                                              refresh_data_length);
  if (NULL == md)
  {
    GNUNET_break (0);
    return NULL;
  }

  /* now transfer_pub */
  GNUNET_CRYPTO_ecdhe_key_get_public (
    &md->melted_coin.transfer_priv[noreveal_index].ecdhe_priv,
    &transfer_pub.ecdhe_pub);

  /* now new_denoms */
  GNUNET_assert (NULL != (new_denoms_h = json_array ()));
  GNUNET_assert (NULL != (coin_evs = json_array ()));
  GNUNET_assert (NULL != (link_sigs = json_array ()));
  for (unsigned int i = 0; i<md->num_fresh_coins; i++)
  {
    struct GNUNET_HashCode denom_hash;
    struct TALER_PlanchetDetail pd;
    struct GNUNET_HashCode c_hash;

    GNUNET_CRYPTO_rsa_public_key_hash (md->fresh_pks[i].rsa_public_key,
                                       &denom_hash);
    GNUNET_assert (0 ==
                   json_array_append_new (new_denoms_h,
                                          GNUNET_JSON_from_data_auto (
                                            &denom_hash)));

    if (GNUNET_OK !=
        TALER_planchet_prepare (&md->fresh_pks[i],
                                &md->fresh_coins[noreveal_index][i],
                                &c_hash,
                                &pd))
    {
      /* This should have been noticed during the preparation stage. */
      GNUNET_break (0);
      json_decref (new_denoms_h);
      json_decref (coin_evs);
      return NULL;
    }
    GNUNET_assert (0 ==
                   json_array_append_new (coin_evs,
                                          GNUNET_JSON_from_data (pd.coin_ev,
                                                                 pd.coin_ev_size)));
    {
      struct TALER_CoinSpendSignatureP link_sig;

      TALER_wallet_link_sign (&denom_hash,
                              &transfer_pub,
                              pd.coin_ev,
                              pd.coin_ev_size,
                              &md->melted_coin.coin_priv,
                              &link_sig);
      GNUNET_assert (0 ==
                     json_array_append_new (
                       link_sigs,
                       GNUNET_JSON_from_data_auto (&link_sig)));
    }
    GNUNET_free (pd.coin_ev);
  }

  /* build array of transfer private keys */
  GNUNET_assert (NULL != (transfer_privs = json_array ()));
  for (unsigned int j = 0; j<TALER_CNC_KAPPA; j++)
  {
    if (j == noreveal_index)
    {
      /* This is crucial: exclude the transfer key for the
   noreval index! */
      continue;
    }
    GNUNET_assert (0 ==
                   json_array_append_new (transfer_privs,
                                          GNUNET_JSON_from_data_auto (
                                            &md->melted_coin.transfer_priv[j])));
  }

  /* build main JSON request */
  reveal_obj = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_data_auto ("transfer_pub",
                                &transfer_pub),
    GNUNET_JSON_pack_array_steal ("transfer_privs",
                                  transfer_privs),
    GNUNET_JSON_pack_array_steal ("link_sigs",
                                  link_sigs),
    GNUNET_JSON_pack_array_steal ("new_denoms_h",
                                  new_denoms_h),
    GNUNET_JSON_pack_array_steal ("coin_evs",
                                  coin_evs));
  {
    char pub_str[sizeof (struct TALER_RefreshCommitmentP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (&md->rc,
                                         sizeof (struct
                                                 TALER_RefreshCommitmentP),
                                         pub_str,
                                         sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/refreshes/%s/reveal",
                     pub_str);
  }
  /* finally, we can actually issue the request */
  rrh = GNUNET_new (struct TALER_EXCHANGE_RefreshesRevealHandle);
  rrh->exchange = exchange;
  rrh->noreveal_index = noreveal_index;
  rrh->reveal_cb = reveal_cb;
  rrh->reveal_cb_cls = reveal_cb_cls;
  rrh->md = md;
  rrh->url = TEAH_path_to_url (rrh->exchange,
                               arg_str);
  if (NULL == rrh->url)
  {
    json_decref (reveal_obj);
    GNUNET_free (rrh);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (rrh->url);
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&rrh->ctx,
                              eh,
                              reveal_obj)) )
  {
    GNUNET_break (0);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (reveal_obj);
    GNUNET_free (rrh->url);
    GNUNET_free (rrh);
    return NULL;
  }
  json_decref (reveal_obj);
  ctx = TEAH_handle_to_context (rrh->exchange);
  rrh->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   rrh->ctx.headers,
                                   &handle_refresh_reveal_finished,
                                   rrh);
  return rrh;
}


void
TALER_EXCHANGE_refreshes_reveal_cancel (
  struct TALER_EXCHANGE_RefreshesRevealHandle *rrh)
{
  if (NULL != rrh->job)
  {
    GNUNET_CURL_job_cancel (rrh->job);
    rrh->job = NULL;
  }
  GNUNET_free (rrh->url);
  TALER_curl_easy_post_finished (&rrh->ctx);
  TALER_EXCHANGE_free_melt_data_ (rrh->md); /* does not free 'md' itself */
  GNUNET_free (rrh->md);
  GNUNET_free (rrh);
}


/* exchange_api_refreshes_reveal.c */
