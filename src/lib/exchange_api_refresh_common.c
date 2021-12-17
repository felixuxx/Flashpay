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
 * @file lib/exchange_api_refresh_common.c
 * @brief Serialization logic shared between melt and reveal steps during refreshing
 * @author Christian Grothoff
 */
#include "platform.h"
#include "exchange_api_refresh_common.h"


/**
 * Free all information associated with a melted coin session.
 *
 * @param mc melted coin to release, the pointer itself is NOT
 *           freed (as it is typically not allocated by itself)
 */
static void
free_melted_coin (struct MeltedCoin *mc)
{
  TALER_denom_pub_free (&mc->pub_key);
  TALER_denom_sig_free (&mc->sig);
}


void
TALER_EXCHANGE_free_melt_data_ (struct MeltData *md)
{
  free_melted_coin (&md->melted_coin);
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


/**
 * Serialize information about a coin we are melting.
 *
 * @param mc information to serialize
 * @return NULL on error
 */
static json_t *
serialize_melted_coin (const struct MeltedCoin *mc)
{
  json_t *tprivs;

  tprivs = json_array ();
  GNUNET_assert (NULL != tprivs);
  for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
    GNUNET_assert (0 ==
                   json_array_append_new (
                     tprivs,
                     GNUNET_JSON_PACK (
                       GNUNET_JSON_pack_data_auto (
                         "transfer_priv",
                         &mc->transfer_priv[i]))));
  return GNUNET_JSON_PACK (
    GNUNET_JSON_pack_data_auto ("coin_priv",
                                &mc->coin_priv),
    TALER_JSON_pack_denom_sig ("denom_sig",
                               &mc->sig),
    TALER_JSON_pack_denom_pub ("denom_pub",
                               &mc->pub_key),
    TALER_JSON_pack_amount ("melt_amount_with_fee",
                            &mc->melt_amount_with_fee),
    TALER_JSON_pack_amount ("original_value",
                            &mc->original_value),
    TALER_JSON_pack_amount ("melt_fee",
                            &mc->fee_melt),
    GNUNET_JSON_pack_timestamp ("expire_deposit",
                                mc->expire_deposit),
    GNUNET_JSON_pack_array_steal ("transfer_privs",
                                  tprivs));
}


/**
 * Deserialize information about a coin we are melting.
 *
 * @param[out] mc information to deserialize
 * @param currency expected currency
 * @param in JSON object to read data from
 * @return #GNUNET_NO to report errors
 */
static enum GNUNET_GenericReturnValue
deserialize_melted_coin (struct MeltedCoin *mc,
                         const char *currency,
                         const json_t *in)
{
  json_t *trans_privs;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("coin_priv",
                                 &mc->coin_priv),
    TALER_JSON_spec_denom_sig ("denom_sig",
                               &mc->sig),
    TALER_JSON_spec_denom_pub ("denom_pub",
                               &mc->pub_key),
    TALER_JSON_spec_amount ("melt_amount_with_fee",
                            currency,
                            &mc->melt_amount_with_fee),
    TALER_JSON_spec_amount ("original_value",
                            currency,
                            &mc->original_value),
    TALER_JSON_spec_amount ("melt_fee",
                            currency,
                            &mc->fee_melt),
    GNUNET_JSON_spec_timestamp ("expire_deposit",
                                &mc->expire_deposit),
    GNUNET_JSON_spec_json ("transfer_privs",
                           &trans_privs),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (in,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_NO;
  }
  if (TALER_CNC_KAPPA != json_array_size (trans_privs))
  {
    GNUNET_JSON_parse_free (spec);
    GNUNET_break_op (0);
    return GNUNET_NO;
  }
  for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
  {
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto ("transfer_priv",
                                   &mc->transfer_priv[i]),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (json_array_get (trans_privs,
                                           i),
                           spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
      return GNUNET_NO;
    }
  }
  json_decref (trans_privs);
  return GNUNET_OK;
}


/**
 * Serialize melt data.
 *
 * @param md data to serialize
 * @return serialized melt data
 */
static json_t *
serialize_melt_data (const struct MeltData *md)
{
  json_t *fresh_coins;

  fresh_coins = json_array ();
  GNUNET_assert (NULL != fresh_coins);
  for (int i = 0; i<md->num_fresh_coins; i++)
  {
    json_t *planchet_secrets;

    planchet_secrets = json_array ();
    GNUNET_assert (NULL != planchet_secrets);
    for (unsigned int j = 0; j<TALER_CNC_KAPPA; j++)
    {
      json_t *ps;

      ps = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_auto ("ps",
                                    &md->fresh_coins[j][i]));
      GNUNET_assert (0 ==
                     json_array_append_new (planchet_secrets,
                                            ps));
    }
    GNUNET_assert (0 ==
                   json_array_append_new (
                     fresh_coins,
                     GNUNET_JSON_PACK (
                       TALER_JSON_pack_denom_pub ("denom_pub",
                                                  &md->fresh_pks[i]),
                       GNUNET_JSON_pack_array_steal ("planchet_secrets",
                                                     planchet_secrets)))
                   );
  }
  return GNUNET_JSON_PACK (
    GNUNET_JSON_pack_array_steal ("fresh_coins",
                                  fresh_coins),
    GNUNET_JSON_pack_object_steal ("melted_coin",
                                   serialize_melted_coin (&md->melted_coin)),
    GNUNET_JSON_pack_data_auto ("rc",
                                &md->rc));
}


struct MeltData *
TALER_EXCHANGE_deserialize_melt_data_ (const json_t *melt_data,
                                       const char *currency)
{
  struct MeltData *md = GNUNET_new (struct MeltData);
  json_t *fresh_coins;
  json_t *melted_coin;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("rc",
                                 &md->rc),
    GNUNET_JSON_spec_json ("melted_coin",
                           &melted_coin),
    GNUNET_JSON_spec_json ("fresh_coins",
                           &fresh_coins),
    GNUNET_JSON_spec_end ()
  };
  bool ok;

  if (GNUNET_OK !=
      GNUNET_JSON_parse (melt_data,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break (0);
    GNUNET_JSON_parse_free (spec);
    GNUNET_free (md);
    return NULL;
  }
  if (! (json_is_array (fresh_coins) &&
         json_is_object (melted_coin)) )
  {
    GNUNET_break (0);
    GNUNET_JSON_parse_free (spec);
    return NULL;
  }
  if (GNUNET_OK !=
      deserialize_melted_coin (&md->melted_coin,
                               currency,
                               melted_coin))
  {
    GNUNET_break (0);
    GNUNET_JSON_parse_free (spec);
    return NULL;
  }
  md->num_fresh_coins = json_array_size (fresh_coins);
  md->fresh_pks = GNUNET_new_array (md->num_fresh_coins,
                                    struct TALER_DenominationPublicKey);
  for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
    md->fresh_coins[i] = GNUNET_new_array (md->num_fresh_coins,
                                           struct TALER_PlanchetSecretsP);
  ok = true;
  for (unsigned int i = 0; i<md->num_fresh_coins; i++)
  {
    const json_t *ji = json_array_get (fresh_coins,
                                       i);
    json_t *planchet_secrets;
    struct GNUNET_JSON_Specification ispec[] = {
      GNUNET_JSON_spec_json ("planchet_secrets",
                             &planchet_secrets),
      TALER_JSON_spec_denom_pub ("denom_pub",
                                 &md->fresh_pks[i]),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (ji,
                           ispec,
                           NULL, NULL))
    {
      GNUNET_break (0);
      ok = false;
      break;
    }
    if ( (! json_is_array (planchet_secrets)) ||
         (TALER_CNC_KAPPA != json_array_size (planchet_secrets)) )
    {
      GNUNET_break (0);
      ok = false;
      GNUNET_JSON_parse_free (ispec);
      break;
    }
    for (unsigned int j = 0; j<TALER_CNC_KAPPA; j++)
    {
      struct GNUNET_JSON_Specification jspec[] = {
        GNUNET_JSON_spec_fixed_auto ("ps",
                                     &md->fresh_coins[j][i]),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (json_array_get (planchet_secrets,
                                             j),
                             jspec,
                             NULL, NULL))
      {
        GNUNET_break (0);
        ok = false;
        break;
      }
    }
    json_decref (planchet_secrets);
    if (! ok)
      break;
  }

  GNUNET_JSON_parse_free (spec);
  if (! ok)
  {
    TALER_EXCHANGE_free_melt_data_ (md);
    GNUNET_free (md);
    return NULL;
  }
  return md;
}


json_t *
TALER_EXCHANGE_refresh_prepare (
  const struct TALER_CoinSpendPrivateKeyP *melt_priv,
  const struct TALER_Amount *melt_amount,
  const struct TALER_DenominationSignature *melt_sig,
  const struct TALER_EXCHANGE_DenomPublicKey *melt_pk,
  unsigned int fresh_pks_len,
  const struct TALER_EXCHANGE_DenomPublicKey *fresh_pks)
{
  struct MeltData md;
  json_t *ret;
  struct TALER_Amount total;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  struct TALER_TransferSecretP trans_sec[TALER_CNC_KAPPA];
  struct TALER_RefreshCommitmentEntry rce[TALER_CNC_KAPPA];

  GNUNET_CRYPTO_eddsa_key_get_public (&melt_priv->eddsa_priv,
                                      &coin_pub.eddsa_pub);
  /* build up melt data structure */
  memset (&md,
          0,
          sizeof (md));
  md.num_fresh_coins = fresh_pks_len;
  md.melted_coin.coin_priv = *melt_priv;
  md.melted_coin.melt_amount_with_fee = *melt_amount;
  md.melted_coin.fee_melt = melt_pk->fee_refresh;
  md.melted_coin.original_value = melt_pk->value;
  md.melted_coin.expire_deposit
    = melt_pk->expire_deposit;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (melt_amount->currency,
                                        &total));
  TALER_denom_pub_deep_copy (&md.melted_coin.pub_key,
                             &melt_pk->key);
  TALER_denom_sig_deep_copy (&md.melted_coin.sig,
                             melt_sig);
  md.fresh_pks = GNUNET_new_array (fresh_pks_len,
                                   struct TALER_DenominationPublicKey);
  for (unsigned int i = 0; i<fresh_pks_len; i++)
  {
    TALER_denom_pub_deep_copy (&md.fresh_pks[i],
                               &fresh_pks[i].key);
    if ( (0 >
          TALER_amount_add (&total,
                            &total,
                            &fresh_pks[i].value)) ||
         (0 >
          TALER_amount_add (&total,
                            &total,
                            &fresh_pks[i].fee_withdraw)) )
    {
      GNUNET_break (0);
      TALER_EXCHANGE_free_melt_data_ (&md);
      return NULL;
    }
  }
  /* verify that melt_amount is above total cost */
  if (1 ==
      TALER_amount_cmp (&total,
                        melt_amount) )
  {
    /* Eh, this operation is more expensive than the
       @a melt_amount. This is not OK. */
    GNUNET_break (0);
    TALER_EXCHANGE_free_melt_data_ (&md);
    return NULL;
  }

  /* build up coins */
  for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
  {
    GNUNET_CRYPTO_ecdhe_key_create (
      &md.melted_coin.transfer_priv[i].ecdhe_priv);
    GNUNET_CRYPTO_ecdhe_key_get_public (
      &md.melted_coin.transfer_priv[i].ecdhe_priv,
      &rce[i].transfer_pub.ecdhe_pub);
    TALER_link_derive_transfer_secret  (melt_priv,
                                        &md.melted_coin.transfer_priv[i],
                                        &trans_sec[i]);
    md.fresh_coins[i] = GNUNET_new_array (fresh_pks_len,
                                          struct TALER_PlanchetSecretsP);
    rce[i].new_coins = GNUNET_new_array (fresh_pks_len,
                                         struct TALER_RefreshCoinData);
    for (unsigned int j = 0; j<fresh_pks_len; j++)
    {
      struct TALER_PlanchetSecretsP *fc = &md.fresh_coins[i][j];
      struct TALER_RefreshCoinData *rcd = &rce[i].new_coins[j];
      struct TALER_PlanchetDetail pd;
      struct TALER_CoinPubHash c_hash;

      TALER_planchet_setup_refresh (&trans_sec[i],
                                    j,
                                    fc);
      if (GNUNET_OK !=
          TALER_planchet_prepare (&md.fresh_pks[j],
                                  fc,
                                  &c_hash,
                                  &pd))
      {
        GNUNET_break_op (0);
        TALER_EXCHANGE_free_melt_data_ (&md);
        return NULL;
      }
      rcd->dk = &md.fresh_pks[j];
      rcd->coin_ev =
        pd.blinded_planchet.details.rsa_blinded_planchet.blinded_msg;
      rcd->coin_ev_size =
        pd.blinded_planchet.details.rsa_blinded_planchet.blinded_msg_size;
    }
  }

  /* Compute refresh commitment */
  TALER_refresh_get_commitment (&md.rc,
                                TALER_CNC_KAPPA,
                                fresh_pks_len,
                                rce,
                                &coin_pub,
                                melt_amount);
  /* finally, serialize everything */
  ret = serialize_melt_data (&md);
  for (unsigned int i = 0; i < TALER_CNC_KAPPA; i++)
  {
    for (unsigned int j = 0; j < fresh_pks_len; j++)
      GNUNET_free (rce[i].new_coins[j].coin_ev);
    GNUNET_free (rce[i].new_coins);
  }
  TALER_EXCHANGE_free_melt_data_ (&md);
  return ret;
}
