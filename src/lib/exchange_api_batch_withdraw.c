/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file lib/exchange_api_batch_withdraw.c
 * @brief Implementation of /reserves/$RESERVE_PUB/batch-withdraw requests with blinding/unblinding
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
 * Data we keep per coin in the batch.
 */
struct CoinData
{

  /**
   * Denomination key we are withdrawing.
   */
  struct TALER_EXCHANGE_DenomPublicKey pk;

  /**
   * Master key material for the coin.
   */
  struct TALER_PlanchetMasterSecretP ps;

  /**
   * Age commitment for the coin.
   */
  const struct TALER_AgeCommitmentHash *ach;

  /**
   * blinding secret
   */
  union GNUNET_CRYPTO_BlindingSecretP bks;

  /**
   * Session nonce.
   */
  union GNUNET_CRYPTO_BlindSessionNonce nonce;

  /**
   * Private key of the coin we are withdrawing.
   */
  struct TALER_CoinSpendPrivateKeyP priv;

  /**
   * Details of the planchet.
   */
  struct TALER_PlanchetDetail pd;

  /**
   * Values of the cipher selected
   */
  struct TALER_ExchangeWithdrawValues alg_values;

  /**
   * Hash of the public key of the coin we are signing.
   */
  struct TALER_CoinPubHashP c_hash;

  /**
   * Handler for the CS R request (only used for GNUNET_CRYPTO_BSA_CS denominations)
   */
  struct TALER_EXCHANGE_CsRWithdrawHandle *csrh;

  /**
   * Batch withdraw this coin is part of.
   */
  struct TALER_EXCHANGE_BatchWithdrawHandle *wh;
};


/**
 * @brief A batch withdraw handle
 */
struct TALER_EXCHANGE_BatchWithdrawHandle
{

  /**
   * The curl context to use
   */
  struct GNUNET_CURL_Context *curl_ctx;

  /**
   * The base URL to the exchange
   */
  const char *exchange_url;

  /**
   * The /keys information from the exchange
   */
  const struct TALER_EXCHANGE_Keys *keys;

  /**
   * Handle for the actual (internal) batch withdraw operation.
   */
  struct TALER_EXCHANGE_BatchWithdraw2Handle *wh2;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_BatchWithdrawCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Reserve private key.
   */
  const struct TALER_ReservePrivateKeyP *reserve_priv;

  /**
   * Array of per-coin data.
   */
  struct CoinData *coins;

  /**
   * Length of the @e coins array.
   */
  unsigned int num_coins;

  /**
   * Number of CS requests still pending.
   */
  unsigned int cs_pending;

};


/**
 * Function called when we're done processing the
 * HTTP /reserves/$RESERVE_PUB/batch-withdraw request.
 *
 * @param cls the `struct TALER_EXCHANGE_BatchWithdrawHandle`
 * @param bw2r response data
 */
static void
handle_reserve_batch_withdraw_finished (
  void *cls,
  const struct TALER_EXCHANGE_BatchWithdraw2Response *bw2r)
{
  struct TALER_EXCHANGE_BatchWithdrawHandle *wh = cls;
  struct TALER_EXCHANGE_BatchWithdrawResponse wr = {
    .hr = bw2r->hr
  };
  struct TALER_EXCHANGE_PrivateCoinDetails coins[GNUNET_NZL (wh->num_coins)];

  wh->wh2 = NULL;
  memset (coins,
          0,
          sizeof (coins));
  switch (bw2r->hr.http_status)
  {
  case MHD_HTTP_OK:
    {
      if (bw2r->details.ok.blind_sigs_length != wh->num_coins)
      {
        GNUNET_break_op (0);
        wr.hr.http_status = 0;
        wr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      for (unsigned int i = 0; i<wh->num_coins; i++)
      {
        struct CoinData *cd = &wh->coins[i];
        struct TALER_EXCHANGE_PrivateCoinDetails *coin = &coins[i];
        struct TALER_FreshCoin fc;

        if (GNUNET_OK !=
            TALER_planchet_to_coin (&cd->pk.key,
                                    &bw2r->details.ok.blind_sigs[i],
                                    &cd->bks,
                                    &cd->priv,
                                    cd->ach,
                                    &cd->c_hash,
                                    &cd->alg_values,
                                    &fc))
        {
          wr.hr.http_status = 0;
          wr.hr.ec = TALER_EC_EXCHANGE_WITHDRAW_UNBLIND_FAILURE;
          break;
        }
        coin->coin_priv = cd->priv;
        coin->bks = cd->bks;
        coin->sig = fc.sig;
        coin->exchange_vals = cd->alg_values;
      }
      wr.details.ok.coins = coins;
      wr.details.ok.num_coins = wh->num_coins;
      break;
    }
  case MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS:
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto (
          "h_payto",
          &wr.details.unavailable_for_legal_reasons.h_payto),
        GNUNET_JSON_spec_uint64 (
          "requirement_row",
          &wr.details.unavailable_for_legal_reasons.requirement_row),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (bw2r->hr.reply,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        wr.hr.http_status = 0;
        wr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
    }
    break;
  default:
    break;
  }
  wh->cb (wh->cb_cls,
          &wr);
  for (unsigned int i = 0; i<wh->num_coins; i++)
    TALER_denom_sig_free (&coins[i].sig);
  TALER_EXCHANGE_batch_withdraw_cancel (wh);
}


/**
 * Runs phase two, the actual withdraw operation.
 * Started once the preparation for CS-denominations is
 * done.
 *
 * @param[in,out] wh batch withdraw to start phase 2 for
 */
static void
phase_two (struct TALER_EXCHANGE_BatchWithdrawHandle *wh)
{
  struct TALER_PlanchetDetail pds[wh->num_coins];

  for (unsigned int i = 0; i<wh->num_coins; i++)
  {
    struct CoinData *cd = &wh->coins[i];

    pds[i] = cd->pd;
  }
  wh->wh2 = TALER_EXCHANGE_batch_withdraw2 (
    wh->curl_ctx,
    wh->exchange_url,
    wh->keys,
    wh->reserve_priv,
    wh->num_coins,
    pds,
    &handle_reserve_batch_withdraw_finished,
    wh);
}


/**
 * Function called when stage 1 of CS withdraw is finished (request r_pub's)
 *
 * @param cls the `struct CoinData *`
 * @param csrr replies from the /csr-withdraw request
 */
static void
withdraw_cs_stage_two_callback (
  void *cls,
  const struct TALER_EXCHANGE_CsRWithdrawResponse *csrr)
{
  struct CoinData *cd = cls;
  struct TALER_EXCHANGE_BatchWithdrawHandle *wh = cd->wh;
  struct TALER_EXCHANGE_BatchWithdrawResponse wr = {
    .hr = csrr->hr
  };

  cd->csrh = NULL;
  GNUNET_assert (GNUNET_CRYPTO_BSA_CS ==
                 cd->pk.key.bsign_pub_key->cipher);
  switch (csrr->hr.http_status)
  {
  case MHD_HTTP_OK:
    GNUNET_assert (NULL ==
                   cd->alg_values.blinding_inputs);
    TALER_denom_ewv_deep_copy (&cd->alg_values,
                               &csrr->details.ok.alg_values);
    TALER_planchet_setup_coin_priv (&cd->ps,
                                    &cd->alg_values,
                                    &cd->priv);
    TALER_planchet_blinding_secret_create (&cd->ps,
                                           &cd->alg_values,
                                           &cd->bks);
    if (GNUNET_OK !=
        TALER_planchet_prepare (&cd->pk.key,
                                &cd->alg_values,
                                &cd->bks,
                                &cd->nonce,
                                &cd->priv,
                                cd->ach,
                                &cd->c_hash,
                                &cd->pd))
    {
      GNUNET_break (0);
      wr.hr.http_status = 0;
      wr.hr.ec = TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR;
      wh->cb (wh->cb_cls,
              &wr);
      TALER_EXCHANGE_batch_withdraw_cancel (wh);
      return;
    }
    wh->cs_pending--;
    if (0 == wh->cs_pending)
      phase_two (wh);
    return;
  default:
    break;
  }
  wh->cb (wh->cb_cls,
          &wr);
  TALER_EXCHANGE_batch_withdraw_cancel (wh);
}


struct TALER_EXCHANGE_BatchWithdrawHandle *
TALER_EXCHANGE_batch_withdraw (
  struct GNUNET_CURL_Context *curl_ctx,
  const char *exchange_url,
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  unsigned int wci_length,
  const struct TALER_EXCHANGE_WithdrawCoinInput wcis[static wci_length],
  TALER_EXCHANGE_BatchWithdrawCallback res_cb,
  void *res_cb_cls)
{
  struct TALER_EXCHANGE_BatchWithdrawHandle *wh;

  wh = GNUNET_new (struct TALER_EXCHANGE_BatchWithdrawHandle);
  wh->curl_ctx = curl_ctx;
  wh->exchange_url = exchange_url;
  wh->keys = keys;
  wh->cb = res_cb;
  wh->cb_cls = res_cb_cls;
  wh->reserve_priv = reserve_priv;
  wh->num_coins = wci_length;
  wh->coins = GNUNET_new_array (wh->num_coins,
                                struct CoinData);
  for (unsigned int i = 0; i<wci_length; i++)
  {
    struct CoinData *cd = &wh->coins[i];
    const struct TALER_EXCHANGE_WithdrawCoinInput *wci = &wcis[i];

    cd->wh = wh;
    cd->ps = *wci->ps;
    cd->ach = wci->ach;
    cd->pk = *wci->pk;
    TALER_denom_pub_deep_copy (&cd->pk.key,
                               &wci->pk->key);
    switch (wci->pk->key.bsign_pub_key->cipher)
    {
    case GNUNET_CRYPTO_BSA_RSA:
      TALER_denom_ewv_deep_copy (&cd->alg_values,
                                 TALER_denom_ewv_rsa_singleton ());
      TALER_planchet_setup_coin_priv (&cd->ps,
                                      &cd->alg_values,
                                      &cd->priv);
      TALER_planchet_blinding_secret_create (&cd->ps,
                                             &cd->alg_values,
                                             &cd->bks);
      if (GNUNET_OK !=
          TALER_planchet_prepare (&cd->pk.key,
                                  &cd->alg_values,
                                  &cd->bks,
                                  NULL,
                                  &cd->priv,
                                  cd->ach,
                                  &cd->c_hash,
                                  &cd->pd))
      {
        GNUNET_break (0);
        TALER_EXCHANGE_batch_withdraw_cancel (wh);
        return NULL;
      }
      break;
    case GNUNET_CRYPTO_BSA_CS:
      TALER_cs_withdraw_nonce_derive (
        &cd->ps,
        &cd->nonce.cs_nonce);
      cd->csrh = TALER_EXCHANGE_csr_withdraw (
        curl_ctx,
        exchange_url,
        &cd->pk,
        &cd->nonce.cs_nonce,
        &withdraw_cs_stage_two_callback,
        cd);
      if (NULL == cd->csrh)
      {
        GNUNET_break (0);
        TALER_EXCHANGE_batch_withdraw_cancel (wh);
        return NULL;
      }
      wh->cs_pending++;
      break;
    default:
      GNUNET_break (0);
      TALER_EXCHANGE_batch_withdraw_cancel (wh);
      return NULL;
    }
  }
  if (0 == wh->cs_pending)
    phase_two (wh);
  return wh;
}


void
TALER_EXCHANGE_batch_withdraw_cancel (
  struct TALER_EXCHANGE_BatchWithdrawHandle *wh)
{
  for (unsigned int i = 0; i<wh->num_coins; i++)
  {
    struct CoinData *cd = &wh->coins[i];

    if (NULL != cd->csrh)
    {
      TALER_EXCHANGE_csr_withdraw_cancel (cd->csrh);
      cd->csrh = NULL;
    }
    TALER_denom_ewv_free (&cd->alg_values);
    TALER_blinded_planchet_free (&cd->pd.blinded_planchet);
    TALER_denom_pub_free (&cd->pk.key);
  }
  GNUNET_free (wh->coins);
  if (NULL != wh->wh2)
  {
    TALER_EXCHANGE_batch_withdraw2_cancel (wh->wh2);
    wh->wh2 = NULL;
  }
  GNUNET_free (wh);
}
