/*
  This file is part of TALER
  Copyright (C) 2015-2022 Taler Systems SA

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
   * Exchange-contributed values to the operation.
   */
  struct TALER_ExchangeWithdrawValues *alg_values;

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
  struct MeltData md;

  /**
   * The index selected by the exchange in cut-and-choose to not be revealed.
   */
  uint16_t noreveal_index;

};


/**
 * We got a 200 OK response for the /refreshes/$RCH/reveal operation.  Extract
 * the coin signatures and return them to the caller.  The signatures we get
 * from the exchange is for the blinded value.  Thus, we first must unblind
 * them and then should verify their validity.
 *
 * If everything checks out, we return the unblinded signatures
 * to the application via the callback.
 *
 * @param rrh operation handle
 * @param json reply from the exchange
 * @param[out] rcis array of length `num_fresh_coins`, initialized to contain the coin data
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static enum GNUNET_GenericReturnValue
refresh_reveal_ok (struct TALER_EXCHANGE_RefreshesRevealHandle *rrh,
                   const json_t *json,
                   struct TALER_EXCHANGE_RevealedCoinInfo *rcis)
{
  json_t *jsona;
  struct GNUNET_JSON_Specification outer_spec[] = {
    GNUNET_JSON_spec_json ("ev_sigs",
                           &jsona),
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
  if (rrh->md.num_fresh_coins != json_array_size (jsona))
  {
    /* Number of coins generated does not match our expectation */
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (outer_spec);
    return GNUNET_SYSERR;
  }
  for (unsigned int i = 0; i<rrh->md.num_fresh_coins; i++)
  {
    struct TALER_EXCHANGE_RevealedCoinInfo *rci =
      &rcis[i];
    const struct FreshCoinData *fcd = &rrh->md.fcds[i];
    const struct TALER_DenominationPublicKey *pk;
    struct TALER_AgeCommitmentHash *ach = NULL;
    json_t *jsonai;
    struct TALER_BlindedDenominationSignature blind_sig;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_CoinPubHash coin_hash;
    struct GNUNET_JSON_Specification spec[] = {
      TALER_JSON_spec_blinded_denom_sig ("ev_sig",
                                         &blind_sig),
      GNUNET_JSON_spec_end ()
    };
    struct TALER_FreshCoin coin;
    union TALER_DenominationBlindingKeyP bks;

    rci->ps = fcd->ps[rrh->noreveal_index];
    rci->bks = fcd->bks[rrh->noreveal_index];
    pk = &fcd->fresh_pk;
    jsonai = json_array_get (jsona, i);
    GNUNET_assert (NULL != jsonai);

    if (! TALER_AgeCommitmentHash_isNullOrZero (
          &rrh->md.melted_coin.h_age_commitment))
    {
      /* FIXME-oec:  need to pull fresh_ach from somewhere */
    }

    if (GNUNET_OK !=
        GNUNET_JSON_parse (jsonai,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (outer_spec);
      return GNUNET_SYSERR;
    }

    TALER_planchet_setup_coin_priv (&rci->ps,
                                    &rrh->alg_values[i],
                                    &rci->coin_priv);
    TALER_planchet_blinding_secret_create (&rci->ps,
                                           &rrh->alg_values[i],
                                           &bks);
    /* needed to verify the signature, and we didn't store it earlier,
       hence recomputing it here... */
    GNUNET_CRYPTO_eddsa_key_get_public (&rci->coin_priv.eddsa_priv,
                                        &coin_pub.eddsa_pub);
    TALER_coin_pub_hash (&coin_pub,
                         ach,
                         &coin_hash);
    if (GNUNET_OK !=
        TALER_planchet_to_coin (pk,
                                &blind_sig,
                                &bks,
                                &rci->coin_priv,
                                ach,
                                &coin_hash,
                                &rrh->alg_values[i],
                                &coin))
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
      GNUNET_JSON_parse_free (outer_spec);
      return GNUNET_SYSERR;
    }
    GNUNET_JSON_parse_free (spec);
    rci->sig = coin.sig;
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
  struct TALER_EXCHANGE_RevealResult rr = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  rrh->job = NULL;
  switch (response_code)
  {
  case 0:
    rr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      struct TALER_EXCHANGE_RevealedCoinInfo rcis[rrh->md.num_fresh_coins];
      enum GNUNET_GenericReturnValue ret;

      memset (rcis,
              0,
              sizeof (rcis));
      ret = refresh_reveal_ok (rrh,
                               j,
                               rcis);
      if (GNUNET_OK != ret)
      {
        rr.hr.http_status = 0;
        rr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      else
      {
        GNUNET_assert (rrh->noreveal_index < TALER_CNC_KAPPA);
        rr.details.success.num_coins = rrh->md.num_fresh_coins;
        rr.details.success.coins = rcis;
        rrh->reveal_cb (rrh->reveal_cb_cls,
                        &rr);
        rrh->reveal_cb = NULL;
      }
      for (unsigned int i = 0; i<rrh->md.num_fresh_coins; i++)
        TALER_denom_sig_free (&rcis[i].sig);
      TALER_EXCHANGE_refreshes_reveal_cancel (rrh);
      return;
    }
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    rr.hr.ec = TALER_JSON_get_error_code (j);
    rr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_CONFLICT:
    /* Nothing really to verify, exchange says our reveal is inconsistent
       with our commitment, so either side is buggy; we
       should pass the JSON reply to the application */
    rr.hr.ec = TALER_JSON_get_error_code (j);
    rr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_GONE:
    /* Server claims key expired or has been revoked */
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
    GNUNET_break_op (0);
    rr.hr.ec = TALER_JSON_get_error_code (j);
    rr.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange refreshes reveal\n",
                (unsigned int) response_code,
                (int) rr.hr.ec);
    break;
  }
  if (NULL != rrh->reveal_cb)
    rrh->reveal_cb (rrh->reveal_cb_cls,
                    &rr);
  TALER_EXCHANGE_refreshes_reveal_cancel (rrh);
}


struct TALER_EXCHANGE_RefreshesRevealHandle *
TALER_EXCHANGE_refreshes_reveal (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_RefreshMasterSecretP *rms,
  const struct TALER_EXCHANGE_RefreshData *rd,
  unsigned int num_coins,
  const struct TALER_ExchangeWithdrawValues *alg_values,
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
  struct MeltData md;
  char arg_str[sizeof (struct TALER_RefreshCommitmentP) * 2 + 32];
  bool send_rms = false;

  GNUNET_assert (num_coins == rd->fresh_pks_len);
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
  if (GNUNET_OK !=
      TALER_EXCHANGE_get_melt_data_ (rms,
                                     rd,
                                     alg_values,
                                     &md))
  {
    GNUNET_break (0);
    return NULL;
  }

  /* now new_denoms */
  GNUNET_assert (NULL != (new_denoms_h = json_array ()));
  GNUNET_assert (NULL != (coin_evs = json_array ()));
  GNUNET_assert (NULL != (link_sigs = json_array ()));
  for (unsigned int i = 0; i<md.num_fresh_coins; i++)
  {
    const struct TALER_RefreshCoinData *rcd = &md.rcd[noreveal_index][i];
    struct TALER_DenominationHash denom_hash;

    if (TALER_DENOMINATION_CS == md.fcds[i].fresh_pk.cipher)
      send_rms = true;
    TALER_denom_pub_hash (&md.fcds[i].fresh_pk,
                          &denom_hash);
    GNUNET_assert (0 ==
                   json_array_append_new (new_denoms_h,
                                          GNUNET_JSON_from_data_auto (
                                            &denom_hash)));
    GNUNET_assert (0 ==
                   json_array_append_new (
                     coin_evs,
                     GNUNET_JSON_PACK (
                       TALER_JSON_pack_blinded_planchet (
                         NULL,
                         &rcd->blinded_planchet))));
    {
      struct TALER_CoinSpendSignatureP link_sig;
      struct TALER_BlindedCoinHash bch;

      TALER_coin_ev_hash (&rcd->blinded_planchet,
                          &denom_hash,
                          &bch);
      TALER_wallet_link_sign (
        &denom_hash,
        &md.transfer_pub[noreveal_index],
        &bch,
        &md.melted_coin.coin_priv,
        &link_sig);
      GNUNET_assert (0 ==
                     json_array_append_new (
                       link_sigs,
                       GNUNET_JSON_from_data_auto (&link_sig)));
    }
  }

  /* build array of transfer private keys */
  GNUNET_assert (NULL != (transfer_privs = json_array ()));
  for (unsigned int j = 0; j<TALER_CNC_KAPPA; j++)
  {
    if (j == noreveal_index)
    {
      /* This is crucial: exclude the transfer key for the noreval index! */
      continue;
    }
    GNUNET_assert (0 ==
                   json_array_append_new (transfer_privs,
                                          GNUNET_JSON_from_data_auto (
                                            &md.transfer_priv[j])));
  }

  /* build main JSON request */
  reveal_obj = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_data_auto ("transfer_pub",
                                &md.transfer_pub[noreveal_index]),
    GNUNET_JSON_pack_allow_null (
      send_rms
      ? GNUNET_JSON_pack_data_auto ("rms",
                                    rms)
      : GNUNET_JSON_pack_string ("rms",
                                 NULL)),
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

    end = GNUNET_STRINGS_data_to_string (&md.rc,
                                         sizeof (md.rc),
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
  rrh->alg_values = GNUNET_memdup (alg_values,
                                   md.num_fresh_coins
                                   * sizeof (struct
                                             TALER_ExchangeWithdrawValues));
  rrh->url = TEAH_path_to_url (rrh->exchange,
                               arg_str);
  if (NULL == rrh->url)
  {
    json_decref (reveal_obj);
    TALER_EXCHANGE_free_melt_data_ (&md);
    GNUNET_free (rrh->alg_values);
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
    TALER_EXCHANGE_free_melt_data_ (&md);
    GNUNET_free (rrh->alg_values);
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
  GNUNET_free (rrh->alg_values);
  GNUNET_free (rrh->url);
  TALER_curl_easy_post_finished (&rrh->ctx);
  TALER_EXCHANGE_free_melt_data_ (&rrh->md);
  GNUNET_free (rrh);
}


/* exchange_api_refreshes_reveal.c */
