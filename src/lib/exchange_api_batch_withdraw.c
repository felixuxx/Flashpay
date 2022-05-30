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
   *  blinding secret
   */
  union TALER_DenominationBlindingKeyP bks;

  /**
   * Private key of the coin we are withdrawing.
   */
  struct TALER_CoinSpendPrivateKeyP priv;

  /**
   * Details of the planchet.
   */
  struct TALER_PlanchetDetail pd;

  /**
   * Values of the @cipher selected
   */
  struct TALER_ExchangeWithdrawValues alg_values;

  /**
   * Hash of the public key of the coin we are signing.
   */
  struct TALER_CoinPubHashP c_hash;

  /**
   * Handler for the CS R request (only used for TALER_DENOMINATION_CS denominations)
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
   * The connection to exchange this request handle will use
   */
  struct TALER_EXCHANGE_Handle *exchange;

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
 * @param hr HTTP response data
 * @param blind_sig blind signature over the coin, NULL on error
 */
static void
handle_reserve_batch_withdraw_finished (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr,
  const struct TALER_BlindedDenominationSignature *blind_sigs,
  unsigned int blind_sigs_length)
{
  struct TALER_EXCHANGE_BatchWithdrawHandle *wh = cls;
  struct TALER_EXCHANGE_BatchWithdrawResponse wr = {
    .hr = *hr
  };
  struct TALER_EXCHANGE_PrivateCoinDetails coins[wh->num_coins];

  wh->wh2 = NULL;
  memset (coins,
          0,
          sizeof (coins));
  if (blind_sigs_length != wh->num_coins)
  {
    GNUNET_break_op (0);
    wr.hr.http_status = 0;
    wr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
  }
  switch (hr->http_status)
  {
  case MHD_HTTP_OK:
    {
      for (unsigned int i = 0; i<wh->num_coins; i++)
      {
        struct CoinData *cd = &wh->coins[i];
        struct TALER_EXCHANGE_PrivateCoinDetails *coin = &coins[i];
        struct TALER_FreshCoin fc;

        if (GNUNET_OK !=
            TALER_planchet_to_coin (&cd->pk.key,
                                    &blind_sigs[i],
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
      wr.details.success.coins = coins;
      wr.details.success.num_coins = wh->num_coins;
      break;
    }
  case MHD_HTTP_ACCEPTED:
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_uint64 ("payment_target_uuid",
                                 &wr.details.accepted.payment_target_uuid),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (hr->reply,
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
    wh->exchange,
    wh->reserve_priv,
    pds,
    wh->num_coins,
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
  GNUNET_assert (TALER_DENOMINATION_CS == cd->pk.key.cipher);
  switch (csrr->hr.http_status)
  {
  case MHD_HTTP_OK:
    cd->alg_values = csrr->details.success.alg_values;
    TALER_planchet_setup_coin_priv (&cd->ps,
                                    &cd->alg_values,
                                    &cd->priv);
    TALER_planchet_blinding_secret_create (&cd->ps,
                                           &cd->alg_values,
                                           &cd->bks);
    /* This initializes the 2nd half of the
       wh->pd.blinded_planchet! */
    if (GNUNET_OK !=
        TALER_planchet_prepare (&cd->pk.key,
                                &cd->alg_values,
                                &cd->bks,
                                &cd->priv,
                                cd->ach,
                                &cd->c_hash,
                                &cd->pd))
    {
      GNUNET_break (0);
      TALER_EXCHANGE_batch_withdraw_cancel (wh);
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
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  const struct TALER_EXCHANGE_WithdrawCoinInput *wcis,
  unsigned int wci_length,
  TALER_EXCHANGE_BatchWithdrawCallback res_cb,
  void *res_cb_cls)
{
  struct TALER_EXCHANGE_BatchWithdrawHandle *wh;

  wh = GNUNET_new (struct TALER_EXCHANGE_BatchWithdrawHandle);
  wh->exchange = exchange;
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
    switch (wci->pk->key.cipher)
    {
    case TALER_DENOMINATION_RSA:
      {
        cd->alg_values.cipher = TALER_DENOMINATION_RSA;
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
      }
    case TALER_DENOMINATION_CS:
      {
        TALER_cs_withdraw_nonce_derive (
          &cd->ps,
          &cd->pd.blinded_planchet.details.cs_blinded_planchet.nonce);
        /* Note that we only initialize the first half
           of the blinded_planchet here; the other part
           will be done after the /csr-withdraw request! */
        cd->pd.blinded_planchet.cipher = TALER_DENOMINATION_CS;
        cd->csrh = TALER_EXCHANGE_csr_withdraw (
          exchange,
          &cd->pk,
          &cd->pd.blinded_planchet.details.cs_blinded_planchet.nonce,
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
      }
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
