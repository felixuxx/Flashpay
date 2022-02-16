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
 * @file lib/exchange_api_refresh_common.c
 * @brief Serialization logic shared between melt and reveal steps during refreshing
 * @author Christian Grothoff
 */
#include "platform.h"
#include "exchange_api_refresh_common.h"


void
TALER_EXCHANGE_free_melt_data_ (struct MeltData *md)
{
  for (unsigned int i = 0; i < TALER_CNC_KAPPA; i++)
  {
    struct TALER_RefreshCoinData *rcds = md->rcd[i];

    if (NULL == rcds)
      continue;
    for (unsigned int j = 0; j < md->num_fresh_coins; j++)
      TALER_blinded_planchet_free (&rcds[j].blinded_planchet);
    GNUNET_free (rcds);
  }
  TALER_denom_pub_free (&md->melted_coin.pub_key);
  TALER_denom_sig_free (&md->melted_coin.sig);
  if (NULL != md->fcds)
  {
    for (unsigned int j = 0; j<md->num_fresh_coins; j++)
    {
      struct FreshCoinData *fcd = &md->fcds[j];

      TALER_denom_pub_free (&fcd->fresh_pk);
    }
    GNUNET_free (md->fcds);
  }
  /* Finally, clean up a bit... */
  GNUNET_CRYPTO_zero_keys (md,
                           sizeof (struct MeltData));
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_get_melt_data_ (
  const struct TALER_RefreshMasterSecretP *rms,
  const struct TALER_EXCHANGE_RefreshData *rd,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  struct MeltData *md)
{
  struct TALER_Amount total;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  struct TALER_CsNonce nonces[rd->fresh_pks_len];

  GNUNET_CRYPTO_eddsa_key_get_public (&rd->melt_priv.eddsa_priv,
                                      &coin_pub.eddsa_pub);
  /* build up melt data structure */
  memset (md,
          0,
          sizeof (*md));
  md->num_fresh_coins = rd->fresh_pks_len;
  md->melted_coin.coin_priv = rd->melt_priv;
  md->melted_coin.melt_amount_with_fee = rd->melt_amount;
  md->melted_coin.fee_melt = rd->melt_pk.fee_refresh;
  md->melted_coin.original_value = rd->melt_pk.value;
  md->melted_coin.expire_deposit = rd->melt_pk.expire_deposit;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (rd->melt_amount.currency,
                                        &total));
  TALER_denom_pub_deep_copy (&md->melted_coin.pub_key,
                             &rd->melt_pk.key);
  TALER_denom_sig_deep_copy (&md->melted_coin.sig,
                             &rd->melt_sig);
  md->fcds = GNUNET_new_array (md->num_fresh_coins,
                               struct FreshCoinData);
  for (unsigned int j = 0; j<rd->fresh_pks_len; j++)
  {
    struct FreshCoinData *fcd = &md->fcds[j];

    if (alg_values[j].cipher != rd->fresh_pks[j].key.cipher)
    {
      GNUNET_break (0);
      TALER_EXCHANGE_free_melt_data_ (md);
      return GNUNET_SYSERR;
    }
    if (TALER_DENOMINATION_CS == alg_values[j].cipher)
    {
      TALER_cs_refresh_nonce_derive (
        rms,
        j,
        &nonces[j]);
    }
    TALER_denom_pub_deep_copy (&fcd->fresh_pk,
                               &rd->fresh_pks[j].key);
    if ( (0 >
          TALER_amount_add (&total,
                            &total,
                            &rd->fresh_pks[j].value)) ||
         (0 >
          TALER_amount_add (&total,
                            &total,
                            &rd->fresh_pks[j].fee_withdraw)) )
    {
      GNUNET_break (0);
      TALER_EXCHANGE_free_melt_data_ (md);
      return GNUNET_SYSERR;
    }
  }

  /* verify that melt_amount is above total cost */
  if (1 ==
      TALER_amount_cmp (&total,
                        &rd->melt_amount) )
  {
    /* Eh, this operation is more expensive than the
       @a melt_amount. This is not OK. */
    GNUNET_break (0);
    TALER_EXCHANGE_free_melt_data_ (md);
    return GNUNET_SYSERR;
  }

  /* build up coins */
  for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
  {
    struct TALER_TransferSecretP trans_sec;

    TALER_planchet_secret_to_transfer_priv (
      rms,
      i,
      &md->transfer_priv[i]);
    GNUNET_CRYPTO_ecdhe_key_get_public (
      &md->transfer_priv[i].ecdhe_priv,
      &md->transfer_pub[i].ecdhe_pub);
    TALER_link_derive_transfer_secret (&rd->melt_priv,
                                       &md->transfer_priv[i],
                                       &trans_sec);
    md->rcd[i] = GNUNET_new_array (rd->fresh_pks_len,
                                   struct TALER_RefreshCoinData);
    for (unsigned int j = 0; j<rd->fresh_pks_len; j++)
    {
      struct FreshCoinData *fcd = &md->fcds[j];
      struct TALER_CoinSpendPrivateKeyP *coin_priv = &fcd->coin_priv;
      struct TALER_PlanchetMasterSecretP *ps = &fcd->ps[i];
      struct TALER_RefreshCoinData *rcd = &md->rcd[i][j];
      union TALER_DenominationBlindingKeyP *bks = &fcd->bks[i];
      struct TALER_PlanchetDetail pd;
      struct TALER_CoinPubHash c_hash;

      TALER_transfer_secret_to_planchet_secret (&trans_sec,
                                                j,
                                                ps);
      TALER_planchet_setup_coin_priv (ps,
                                      &alg_values[j],
                                      coin_priv);
      TALER_planchet_blinding_secret_create (ps,
                                             &alg_values[j],
                                             bks);
      if (TALER_DENOMINATION_CS == alg_values[j].cipher)
        pd.blinded_planchet.details.cs_blinded_planchet.nonce = nonces[j];
      if (GNUNET_OK !=
          TALER_planchet_prepare (&fcd->fresh_pk,
                                  &alg_values[j],
                                  bks,
                                  coin_priv,
                                  NULL, /* FIXME-oec: This needs to be setup !*/
                                  &c_hash,
                                  &pd))
      {
        GNUNET_break_op (0);
        TALER_EXCHANGE_free_melt_data_ (md);
        return GNUNET_SYSERR;
      }
      rcd->blinded_planchet = pd.blinded_planchet;
      rcd->dk = &fcd->fresh_pk;
    }
  }

  /* Finally, compute refresh commitment */
  {
    struct TALER_RefreshCommitmentEntry rce[TALER_CNC_KAPPA];

    for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
    {
      rce[i].transfer_pub = md->transfer_pub[i];
      rce[i].new_coins = md->rcd[i];
    }
    TALER_refresh_get_commitment (&md->rc,
                                  TALER_CNC_KAPPA,
                                  rd->fresh_pks_len,
                                  rce,
                                  &coin_pub,
                                  &rd->melt_amount);
  }
  return GNUNET_OK;
}
