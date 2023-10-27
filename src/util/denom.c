/*
  This file is part of TALER
  Copyright (C) 2021, 2022, 2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file denom.c
 * @brief denomination utility functions
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"


enum GNUNET_GenericReturnValue
TALER_denom_priv_create (struct TALER_DenominationPrivateKey *denom_priv,
                         struct TALER_DenominationPublicKey *denom_pub,
                         enum GNUNET_CRYPTO_BlindSignatureAlgorithm cipher,
                         ...)
{
  enum GNUNET_GenericReturnValue ret;
  va_list ap;

  va_start (ap,
            cipher);
  ret = GNUNET_CRYPTO_blind_sign_keys_create_va (
    &denom_priv->bsign_priv_key,
    &denom_pub->bsign_pub_key,
    cipher,
    ap);
  va_end (ap);
  return ret;
}


enum GNUNET_GenericReturnValue
TALER_denom_sign_blinded (struct TALER_BlindedDenominationSignature *denom_sig,
                          const struct TALER_DenominationPrivateKey *denom_priv,
                          bool for_melt,
                          const struct TALER_BlindedPlanchet *blinded_planchet)
{
  denom_sig->blinded_sig
    = GNUNET_CRYPTO_blind_sign (denom_priv->bsign_priv_key,
                                for_melt ? "rm" : "rw",
                                blinded_planchet->blinded_message);
  if (NULL == denom_sig->blinded_sig)
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_denom_sig_unblind (
  struct TALER_DenominationSignature *denom_sig,
  const struct TALER_BlindedDenominationSignature *bdenom_sig,
  const union GNUNET_CRYPTO_BlindingSecretP *bks,
  const struct TALER_CoinPubHashP *c_hash,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  const struct TALER_DenominationPublicKey *denom_pub)
{
  denom_sig->unblinded_sig
    = GNUNET_CRYPTO_blind_sig_unblind (bdenom_sig->blinded_sig,
                                       bks,
                                       c_hash,
                                       sizeof (*c_hash),
                                       alg_values->blinding_inputs,
                                       denom_pub->bsign_pub_key);
  if (NULL == denom_sig->unblinded_sig)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


void
TALER_denom_pub_hash (const struct TALER_DenominationPublicKey *denom_pub,
                      struct TALER_DenominationHashP *denom_hash)
{
  struct GNUNET_CRYPTO_BlindSignPublicKey *bsp
    = denom_pub->bsign_pub_key;
  uint32_t opt[2] = {
    htonl (denom_pub->age_mask.bits),
    htonl ((uint32_t) bsp->cipher)
  };
  struct GNUNET_HashContext *hc;

  hc = GNUNET_CRYPTO_hash_context_start ();
  GNUNET_CRYPTO_hash_context_read (hc,
                                   opt,
                                   sizeof (opt));
  switch (bsp->cipher)
  {
  case GNUNET_CRYPTO_BSA_RSA:
    {
      void *buf;
      size_t blen;

      blen = GNUNET_CRYPTO_rsa_public_key_encode (
        bsp->details.rsa_public_key,
        &buf);
      GNUNET_CRYPTO_hash_context_read (hc,
                                       buf,
                                       blen);
      GNUNET_free (buf);
    }
    break;
  case GNUNET_CRYPTO_BSA_CS:
    GNUNET_CRYPTO_hash_context_read (hc,
                                     &bsp->details.cs_public_key,
                                     sizeof(bsp->details.cs_public_key));
    break;
  default:
    GNUNET_assert (0);
  }
  GNUNET_CRYPTO_hash_context_finish (hc,
                                     &denom_hash->hash);
}


const struct TALER_ExchangeWithdrawValues *
TALER_denom_ewv_rsa_singleton ()
{
  static struct GNUNET_CRYPTO_BlindingInputValues bi = {
    .cipher = GNUNET_CRYPTO_BSA_RSA
  };
  static struct TALER_ExchangeWithdrawValues alg_values = {
    .blinding_inputs = &bi
  };
  return &alg_values;
}


enum GNUNET_GenericReturnValue
TALER_denom_blind (
  const struct TALER_DenominationPublicKey *dk,
  const union GNUNET_CRYPTO_BlindingSecretP *coin_bks,
  const union GNUNET_CRYPTO_BlindSessionNonce *nonce,
  const struct TALER_AgeCommitmentHash *ach,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  struct TALER_CoinPubHashP *c_hash,
  struct TALER_BlindedPlanchet *blinded_planchet)
{
  TALER_coin_pub_hash (coin_pub,
                       ach,
                       c_hash);
  blinded_planchet->blinded_message
    = GNUNET_CRYPTO_message_blind_to_sign (dk->bsign_pub_key,
                                           coin_bks,
                                           nonce,
                                           c_hash,
                                           sizeof (*c_hash),
                                           alg_values->blinding_inputs);
  if (NULL == blinded_planchet->blinded_message)
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_denom_pub_verify (const struct TALER_DenominationPublicKey *denom_pub,
                        const struct TALER_DenominationSignature *denom_sig,
                        const struct TALER_CoinPubHashP *c_hash)
{
  return GNUNET_CRYPTO_blind_sig_verify (denom_pub->bsign_pub_key,
                                         denom_sig->unblinded_sig,
                                         c_hash,
                                         sizeof (*c_hash));
}


void
TALER_denom_pub_free (struct TALER_DenominationPublicKey *denom_pub)
{
  if (NULL != denom_pub->bsign_pub_key)
  {
    GNUNET_CRYPTO_blind_sign_pub_decref (denom_pub->bsign_pub_key);
    denom_pub->bsign_pub_key = NULL;
  }
}


void
TALER_denom_priv_free (struct TALER_DenominationPrivateKey *denom_priv)
{
  if (NULL != denom_priv->bsign_priv_key)
  {
    GNUNET_CRYPTO_blind_sign_priv_decref (denom_priv->bsign_priv_key);
    denom_priv->bsign_priv_key = NULL;
  }
}


void
TALER_denom_sig_free (struct TALER_DenominationSignature *denom_sig)
{
  if (NULL != denom_sig->unblinded_sig)
  {
    GNUNET_CRYPTO_unblinded_sig_decref (denom_sig->unblinded_sig);
    denom_sig->unblinded_sig = NULL;
  }
}


void
TALER_blinded_denom_sig_free (
  struct TALER_BlindedDenominationSignature *denom_sig)
{
  if (NULL != denom_sig->blinded_sig)
  {
    GNUNET_CRYPTO_blinded_sig_decref (denom_sig->blinded_sig);
    denom_sig->blinded_sig = NULL;
  }
}


void
TALER_denom_pub_deep_copy (struct TALER_DenominationPublicKey *denom_dst,
                           const struct TALER_DenominationPublicKey *denom_src)
{
  denom_dst->bsign_pub_key
    = GNUNET_CRYPTO_bsign_pub_incref (denom_src->bsign_pub_key);
}


void
TALER_denom_sig_deep_copy (struct TALER_DenominationSignature *denom_dst,
                           const struct TALER_DenominationSignature *denom_src)
{
  denom_dst->unblinded_sig
    = GNUNET_CRYPTO_ub_sig_incref (denom_src->unblinded_sig);
}


void
TALER_blinded_denom_sig_deep_copy (
  struct TALER_BlindedDenominationSignature *denom_dst,
  const struct TALER_BlindedDenominationSignature *denom_src)
{
  denom_dst->blinded_sig
    = GNUNET_CRYPTO_blind_sig_incref (denom_src->blinded_sig);
}


int
TALER_denom_pub_cmp (const struct TALER_DenominationPublicKey *denom1,
                     const struct TALER_DenominationPublicKey *denom2)
{
  if (denom1->bsign_pub_key->cipher !=
      denom2->bsign_pub_key->cipher)
    return (denom1->bsign_pub_key->cipher >
            denom2->bsign_pub_key->cipher) ? 1 : -1;
  if (denom1->age_mask.bits != denom2->age_mask.bits)
    return (denom1->age_mask.bits > denom2->age_mask.bits) ? 1 : -1;
  return GNUNET_CRYPTO_bsign_pub_cmp (denom1->bsign_pub_key,
                                      denom2->bsign_pub_key);
}


int
TALER_denom_sig_cmp (const struct TALER_DenominationSignature *sig1,
                     const struct TALER_DenominationSignature *sig2)
{
  return GNUNET_CRYPTO_ub_sig_cmp (sig1->unblinded_sig,
                                   sig1->unblinded_sig);
}


int
TALER_blinded_planchet_cmp (
  const struct TALER_BlindedPlanchet *bp1,
  const struct TALER_BlindedPlanchet *bp2)
{
  return GNUNET_CRYPTO_blinded_message_cmp (bp1->blinded_message,
                                            bp2->blinded_message);
}


int
TALER_blinded_denom_sig_cmp (
  const struct TALER_BlindedDenominationSignature *sig1,
  const struct TALER_BlindedDenominationSignature *sig2)
{
  return GNUNET_CRYPTO_blind_sig_cmp (sig1->blinded_sig,
                                      sig1->blinded_sig);
}


void
TALER_blinded_planchet_hash_ (const struct TALER_BlindedPlanchet *bp,
                              struct GNUNET_HashContext *hash_context)
{
  const struct GNUNET_CRYPTO_BlindedMessage *bm = bp->blinded_message;
  uint32_t cipher = htonl (bm->cipher);

  GNUNET_CRYPTO_hash_context_read (hash_context,
                                   &cipher,
                                   sizeof (cipher));
  switch (bm->cipher)
  {
  case GNUNET_CRYPTO_BSA_INVALID:
    GNUNET_break (0);
    return;
  case GNUNET_CRYPTO_BSA_RSA:
    GNUNET_CRYPTO_hash_context_read (
      hash_context,
      bm->details.rsa_blinded_message.blinded_msg,
      bm->details.rsa_blinded_message.blinded_msg_size);
    return;
  case GNUNET_CRYPTO_BSA_CS:
    GNUNET_CRYPTO_hash_context_read (
      hash_context,
      &bm->details.cs_blinded_message,
      sizeof (bm->details.cs_blinded_message));
    return;
  }
  GNUNET_assert (0);
}


void
TALER_planchet_blinding_secret_create (
  const struct TALER_PlanchetMasterSecretP *ps,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  union GNUNET_CRYPTO_BlindingSecretP *bks)
{
  const struct GNUNET_CRYPTO_BlindingInputValues *bi =
    alg_values->blinding_inputs;

  switch (bi->cipher)
  {
  case GNUNET_CRYPTO_BSA_INVALID:
    GNUNET_break (0);
    return;
  case GNUNET_CRYPTO_BSA_RSA:
    GNUNET_assert (GNUNET_YES ==
                   GNUNET_CRYPTO_kdf (&bks->rsa_bks,
                                      sizeof (bks->rsa_bks),
                                      "bks",
                                      strlen ("bks"),
                                      ps,
                                      sizeof(*ps),
                                      NULL,
                                      0));
    return;
  case GNUNET_CRYPTO_BSA_CS:
    GNUNET_assert (GNUNET_YES ==
                   GNUNET_CRYPTO_kdf (&bks->nonce,
                                      sizeof (bks->nonce),
                                      "bseed",
                                      strlen ("bseed"),
                                      ps,
                                      sizeof(*ps),
                                      &bi->details.cs_values,
                                      sizeof(bi->details.cs_values),
                                      NULL,
                                      0));
    return;
  }
  GNUNET_assert (0);
}


void
TALER_planchet_setup_coin_priv (
  const struct TALER_PlanchetMasterSecretP *ps,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  struct TALER_CoinSpendPrivateKeyP *coin_priv)
{
  const struct GNUNET_CRYPTO_BlindingInputValues *bi
    = alg_values->blinding_inputs;

  switch (bi->cipher)
  {
  case GNUNET_CRYPTO_BSA_INVALID:
    GNUNET_break (0);
    memset (coin_priv,
            0,
            sizeof (*coin_priv));
    return;
  case GNUNET_CRYPTO_BSA_RSA:
    GNUNET_assert (GNUNET_YES ==
                   GNUNET_CRYPTO_kdf (coin_priv,
                                      sizeof (*coin_priv),
                                      "coin",
                                      strlen ("coin"),
                                      ps,
                                      sizeof(*ps),
                                      NULL,
                                      0));
    return;
  case GNUNET_CRYPTO_BSA_CS:
    GNUNET_assert (GNUNET_YES ==
                   GNUNET_CRYPTO_kdf (coin_priv,
                                      sizeof (*coin_priv),
                                      "coin",
                                      strlen ("coin"),
                                      ps,
                                      sizeof(*ps),
                                      &bi->details.cs_values,
                                      sizeof(bi->details.cs_values),
                                      NULL,
                                      0));
    return;
  }
  GNUNET_assert (0);
}


void
TALER_blinded_planchet_free (struct TALER_BlindedPlanchet *blinded_planchet)
{
  GNUNET_CRYPTO_blinded_message_decref (blinded_planchet->blinded_message);
  blinded_planchet->blinded_message = NULL;
}


/* end of denom.c */
