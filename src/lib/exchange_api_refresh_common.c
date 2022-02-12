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
  TALER_denom_pub_free (&md->melted_coin.pub_key);
  TALER_denom_sig_free (&md->melted_coin.sig);
  if (NULL != md->fresh_pks)
  {
    for (unsigned int i = 0; i<md->num_fresh_coins; i++)
      TALER_denom_pub_free (&md->fresh_pks[i]);
    GNUNET_free (md->fresh_pks);
  }
  for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
    GNUNET_free (md->fresh_coins[i]);
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
  struct TALER_TransferSecretP trans_sec[TALER_CNC_KAPPA];
  struct TALER_RefreshCommitmentEntry rce[TALER_CNC_KAPPA];

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
  md->fresh_pks = GNUNET_new_array (rd->fresh_pks_len,
                                    struct TALER_DenominationPublicKey);
  for (unsigned int i = 0; i<rd->fresh_pks_len; i++)
  {
    TALER_denom_pub_deep_copy (&md->fresh_pks[i],
                               &rd->fresh_pks[i].key);
    if ( (0 >
          TALER_amount_add (&total,
                            &total,
                            &rd->fresh_pks[i].value)) ||
         (0 >
          TALER_amount_add (&total,
                            &total,
                            &rd->fresh_pks[i].fee_withdraw)) )
    {
      GNUNET_break (0);
      TALER_EXCHANGE_free_melt_data_ (md);
      memset (md,
              0,
              sizeof (*md));
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
    memset (md,
            0,
            sizeof (*md));
    return GNUNET_SYSERR;
  }

  /* build up coins */
  for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
  {
    TALER_planchet_secret_to_transfer_priv (
      rms,
      i,
      &md->melted_coin.transfer_priv[i]);
    GNUNET_CRYPTO_ecdhe_key_get_public (
      &md->melted_coin.transfer_priv[i].ecdhe_priv,
      &rce[i].transfer_pub.ecdhe_pub);
    TALER_link_derive_transfer_secret (&rd->melt_priv,
                                       &md->melted_coin.transfer_priv[i],
                                       &trans_sec[i]);
    md->fresh_coins[i] = GNUNET_new_array (rd->fresh_pks_len,
                                           struct TALER_PlanchetMasterSecretP);
    rce[i].new_coins = GNUNET_new_array (rd->fresh_pks_len,
                                         struct TALER_RefreshCoinData);
    for (unsigned int j = 0; j<rd->fresh_pks_len; j++)
    {
      struct TALER_PlanchetMasterSecretP *fc = &md->fresh_coins[i][j];
      struct TALER_RefreshCoinData *rcd = &rce[i].new_coins[j];
      struct TALER_PlanchetDetail pd;
      struct TALER_CoinPubHash c_hash;
      struct TALER_CoinSpendPrivateKeyP coin_priv;
      union TALER_DenominationBlindingKeyP bks;

      TALER_transfer_secret_to_planchet_secret (&trans_sec[i],
                                                j,
                                                fc);
      TALER_planchet_setup_coin_priv (fc,
                                      &alg_values[j],
                                      &coin_priv);
      TALER_planchet_blinding_secret_create (fc,
                                             &alg_values[j],
                                             &bks);
      /* FIXME: we already did this for the /csr request,
         so this computation is redundant, and here additionally
         repeated KAPPA times. Could be avoided with slightly
         more bookkeeping in the future */
      if (TALER_DENOMINATION_CS == alg_values[j].cipher)
        TALER_cs_refresh_nonce_derive (
          rms,
          j,
          &pd.blinded_planchet.details.cs_blinded_planchet.nonce);
      if (GNUNET_OK !=
          TALER_planchet_prepare (&md->fresh_pks[j],
                                  &alg_values[j],
                                  &bks,
                                  &coin_priv,
                                  &c_hash,
                                  &pd))
      {
        GNUNET_break_op (0);
        TALER_EXCHANGE_free_melt_data_ (md);
        memset (md,
                0,
                sizeof (*md));
        return GNUNET_SYSERR;
      }
      rcd->dk = &md->fresh_pks[j];
      rcd->blinded_planchet = pd.blinded_planchet;
    }
  }

  /* Compute refresh commitment */
  TALER_refresh_get_commitment (&md->rc,
                                TALER_CNC_KAPPA,
                                rd->fresh_pks_len,
                                rce,
                                &coin_pub,
                                &rd->melt_amount);
  for (unsigned int i = 0; i < TALER_CNC_KAPPA; i++)
  {
    for (unsigned int j = 0; j < rd->fresh_pks_len; j++)
      TALER_blinded_planchet_free (&rce[i].new_coins[j].blinded_planchet);
    GNUNET_free (rce[i].new_coins);
  }
  return GNUNET_OK;
}
