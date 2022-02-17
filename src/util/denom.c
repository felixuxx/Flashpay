/*
  This file is part of TALER
  Copyright (C) 2021 Taler Systems SA

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
                         enum TALER_DenominationCipher cipher,
                         ...)
{
  memset (denom_priv,
          0,
          sizeof (*denom_priv));
  memset (denom_pub,
          0,
          sizeof (*denom_pub));

  switch (cipher)
  {
  case TALER_DENOMINATION_INVALID:
    GNUNET_break (0);
    return GNUNET_SYSERR;
  case TALER_DENOMINATION_RSA:
    {
      va_list ap;
      unsigned int bits;

      va_start (ap, cipher);
      bits = va_arg (ap, unsigned int);
      va_end (ap);
      if (bits < 512)
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      denom_priv->details.rsa_private_key
        = GNUNET_CRYPTO_rsa_private_key_create (bits);
    }
    if (NULL == denom_priv->details.rsa_private_key)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    denom_pub->details.rsa_public_key
      = GNUNET_CRYPTO_rsa_private_key_get_public (
          denom_priv->details.rsa_private_key);
    denom_priv->cipher = TALER_DENOMINATION_RSA;
    denom_pub->cipher = TALER_DENOMINATION_RSA;
    return GNUNET_OK;
  case TALER_DENOMINATION_CS:
    GNUNET_CRYPTO_cs_private_key_generate (&denom_priv->details.cs_private_key);
    GNUNET_CRYPTO_cs_private_key_get_public (
      &denom_priv->details.cs_private_key,
      &denom_pub->details.cs_public_key);
    denom_priv->cipher = TALER_DENOMINATION_CS;
    denom_pub->cipher = TALER_DENOMINATION_CS;
    return GNUNET_OK;
  default:
    GNUNET_break (0);
  }
  return GNUNET_SYSERR;
}


enum GNUNET_GenericReturnValue
TALER_denom_sign_blinded (struct TALER_BlindedDenominationSignature *denom_sig,
                          const struct TALER_DenominationPrivateKey *denom_priv,
                          const struct TALER_BlindedPlanchet *blinded_planchet)
{
  memset (denom_sig,
          0,
          sizeof (*denom_sig));
  if (blinded_planchet->cipher != denom_priv->cipher)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  switch (denom_priv->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    GNUNET_break (0);
    return GNUNET_SYSERR;
  case TALER_DENOMINATION_RSA:
    denom_sig->details.blinded_rsa_signature
      = GNUNET_CRYPTO_rsa_sign_blinded (
          denom_priv->details.rsa_private_key,
          blinded_planchet->details.rsa_blinded_planchet.blinded_msg,
          blinded_planchet->details.rsa_blinded_planchet.blinded_msg_size);
    if (NULL == denom_sig->details.blinded_rsa_signature)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    denom_sig->cipher = TALER_DENOMINATION_RSA;
    return GNUNET_OK;
  case TALER_DENOMINATION_CS:
    {
      struct GNUNET_CRYPTO_CsRSecret r[2];

      GNUNET_CRYPTO_cs_r_derive (
        &blinded_planchet->details.cs_blinded_planchet.nonce.nonce,
        &denom_priv->details.cs_private_key,
        r);
      denom_sig->details.blinded_cs_answer.b =
        GNUNET_CRYPTO_cs_sign_derive (&denom_priv->details.cs_private_key,
                                      r,
                                      blinded_planchet->details.
                                      cs_blinded_planchet.c,
                                      &blinded_planchet->details.
                                      cs_blinded_planchet.nonce.nonce,
                                      &denom_sig->details.blinded_cs_answer.
                                      s_scalar);
      denom_sig->cipher = TALER_DENOMINATION_CS;
    }
    return GNUNET_OK;
  default:
    GNUNET_break (0);
  }
  return GNUNET_SYSERR;
}


enum GNUNET_GenericReturnValue
TALER_denom_sig_unblind (
  struct TALER_DenominationSignature *denom_sig,
  const struct TALER_BlindedDenominationSignature *bdenom_sig,
  const union TALER_DenominationBlindingKeyP *bks,
  const struct TALER_CoinPubHash *c_hash,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  const struct TALER_DenominationPublicKey *denom_pub)
{
  if (bdenom_sig->cipher != denom_pub->cipher)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  switch (denom_pub->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    GNUNET_break (0);
    return GNUNET_SYSERR;
  case TALER_DENOMINATION_RSA:
    denom_sig->details.rsa_signature
      = GNUNET_CRYPTO_rsa_unblind (
          bdenom_sig->details.blinded_rsa_signature,
          &bks->rsa_bks,
          denom_pub->details.rsa_public_key);
    if (NULL == denom_sig->details.rsa_signature)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    denom_sig->cipher = TALER_DENOMINATION_RSA;
    return GNUNET_OK;
  case TALER_DENOMINATION_CS:
    {
      struct GNUNET_CRYPTO_CsBlindingSecret bs[2];
      struct GNUNET_CRYPTO_CsC c[2];
      struct TALER_DenominationCSPublicRPairP r_pub_blind;

      GNUNET_CRYPTO_cs_blinding_secrets_derive (&bks->nonce,
                                                bs);
      GNUNET_CRYPTO_cs_calc_blinded_c (
        bs,
        alg_values->details.cs_values.r_pub,
        &denom_pub->details.cs_public_key,
        &c_hash->hash,
        sizeof(struct GNUNET_HashCode),
        c,
        r_pub_blind.r_pub);
      denom_sig->details.cs_signature.r_point
        = r_pub_blind.r_pub[bdenom_sig->details.blinded_cs_answer.b];
      GNUNET_CRYPTO_cs_unblind (&bdenom_sig->details.blinded_cs_answer.s_scalar,
                                &bs[bdenom_sig->details.blinded_cs_answer.b],
                                &denom_sig->details.cs_signature.s_scalar);
      denom_sig->cipher = TALER_DENOMINATION_CS;
      return GNUNET_OK;
    }
  default:
    GNUNET_break (0);
  }
  return GNUNET_SYSERR;
}


void
TALER_rsa_pub_hash (const struct GNUNET_CRYPTO_RsaPublicKey *rsa,
                    struct TALER_RsaPubHashP *h_rsa)
{
  GNUNET_CRYPTO_rsa_public_key_hash (rsa,
                                     &h_rsa->hash);

}


void
TALER_cs_pub_hash (const struct GNUNET_CRYPTO_CsPublicKey *cs,
                   struct TALER_CsPubHashP *h_cs)
{
  GNUNET_CRYPTO_hash (cs,
                      sizeof(*cs),
                      &h_cs->hash);
}


void
TALER_denom_pub_hash (const struct TALER_DenominationPublicKey *denom_pub,
                      struct TALER_DenominationHash *denom_hash)
{
  uint32_t opt[2] = {
    htonl (denom_pub->age_mask.mask),
    htonl ((uint32_t) denom_pub->cipher)
  };
  struct GNUNET_HashContext *hc;

  hc = GNUNET_CRYPTO_hash_context_start ();
  GNUNET_CRYPTO_hash_context_read (hc,
                                   opt,
                                   sizeof (opt));
  switch (denom_pub->cipher)
  {
  case TALER_DENOMINATION_RSA:
    {
      void *buf;
      size_t blen;

      blen = GNUNET_CRYPTO_rsa_public_key_encode (
        denom_pub->details.rsa_public_key,
        &buf);
      GNUNET_CRYPTO_hash_context_read (hc,
                                       buf,
                                       blen);
      GNUNET_free (buf);
    }
    break;
  case TALER_DENOMINATION_CS:
    GNUNET_CRYPTO_hash_context_read (hc,
                                     &denom_pub->details.cs_public_key,
                                     sizeof(denom_pub->details.cs_public_key));
    break;
  default:
    GNUNET_assert (0);
  }
  GNUNET_CRYPTO_hash_context_finish (hc,
                                     &denom_hash->hash);
}


void
TALER_denom_priv_to_pub (const struct TALER_DenominationPrivateKey *denom_priv,
                         const struct TALER_AgeMask age_mask,
                         struct TALER_DenominationPublicKey *denom_pub)
{
  switch (denom_priv->cipher)
  {
  case TALER_DENOMINATION_RSA:
    denom_pub->cipher = TALER_DENOMINATION_RSA;
    denom_pub->age_mask = age_mask;
    denom_pub->details.rsa_public_key
      = GNUNET_CRYPTO_rsa_private_key_get_public (
          denom_priv->details.rsa_private_key);
    return;
  case TALER_DENOMINATION_CS:
    denom_pub->cipher = TALER_DENOMINATION_CS;
    denom_pub->age_mask = age_mask;
    GNUNET_CRYPTO_cs_private_key_get_public (
      &denom_priv->details.cs_private_key,
      &denom_pub->details.cs_public_key);
    return;
  default:
    GNUNET_assert (0);
  }
}


enum GNUNET_GenericReturnValue
TALER_denom_blind (
  const struct TALER_DenominationPublicKey *dk,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_AgeCommitmentHash *ach,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  struct TALER_CoinPubHash *c_hash,
  struct TALER_BlindedPlanchet *blinded_planchet)
{
  TALER_coin_pub_hash (coin_pub,
                       ach,
                       c_hash);
  switch (dk->cipher)
  {
  case TALER_DENOMINATION_RSA:
    blinded_planchet->cipher = dk->cipher;
    if (GNUNET_YES !=
        GNUNET_CRYPTO_rsa_blind (
          &c_hash->hash,
          &coin_bks->rsa_bks,
          dk->details.rsa_public_key,
          &blinded_planchet->details.rsa_blinded_planchet.blinded_msg,
          &blinded_planchet->details.rsa_blinded_planchet.blinded_msg_size))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    return GNUNET_OK;
  case TALER_DENOMINATION_CS:
    {
      struct TALER_DenominationCSPublicRPairP blinded_r_pub;
      struct GNUNET_CRYPTO_CsBlindingSecret bs[2];

      blinded_planchet->cipher = TALER_DENOMINATION_CS;
      GNUNET_CRYPTO_cs_blinding_secrets_derive (&coin_bks->nonce,
                                                bs);
      GNUNET_CRYPTO_cs_calc_blinded_c (
        bs,
        alg_values->details.cs_values.r_pub,
        &dk->details.cs_public_key,
        c_hash,
        sizeof(*c_hash),
        blinded_planchet->details.cs_blinded_planchet.c,
        blinded_r_pub.r_pub);
      return GNUNET_OK;
    }
  default:
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
}


enum GNUNET_GenericReturnValue
TALER_denom_pub_verify (const struct TALER_DenominationPublicKey *denom_pub,
                        const struct TALER_DenominationSignature *denom_sig,
                        const struct TALER_CoinPubHash *c_hash)
{
  if (denom_pub->cipher != denom_sig->cipher)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  switch (denom_pub->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    GNUNET_break (0);
    return GNUNET_NO;
  case TALER_DENOMINATION_RSA:
    if (GNUNET_OK !=
        GNUNET_CRYPTO_rsa_verify (&c_hash->hash,
                                  denom_sig->details.rsa_signature,
                                  denom_pub->details.rsa_public_key))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Coin signature is invalid\n");
      return GNUNET_NO;
    }
    return GNUNET_YES;
  case TALER_DENOMINATION_CS:
    if (GNUNET_OK !=
        GNUNET_CRYPTO_cs_verify (&denom_sig->details.cs_signature,
                                 &denom_pub->details.cs_public_key,
                                 &c_hash->hash,
                                 sizeof(struct GNUNET_HashCode)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Coin signature is invalid\n");
      return GNUNET_NO;
    }
    return GNUNET_YES;
  default:
    GNUNET_assert (0);
  }
}


void
TALER_denom_pub_free (struct TALER_DenominationPublicKey *denom_pub)
{
  switch (denom_pub->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    return;
  case TALER_DENOMINATION_RSA:
    if (NULL != denom_pub->details.rsa_public_key)
    {
      GNUNET_CRYPTO_rsa_public_key_free (denom_pub->details.rsa_public_key);
      denom_pub->details.rsa_public_key = NULL;
    }
    denom_pub->cipher = TALER_DENOMINATION_INVALID;
    return;
  case TALER_DENOMINATION_CS:
    return;
  default:
    GNUNET_assert (0);
  }
}


void
TALER_denom_priv_free (struct TALER_DenominationPrivateKey *denom_priv)
{
  switch (denom_priv->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    return;
  case TALER_DENOMINATION_RSA:
    if (NULL != denom_priv->details.rsa_private_key)
    {
      GNUNET_CRYPTO_rsa_private_key_free (denom_priv->details.rsa_private_key);
      denom_priv->details.rsa_private_key = NULL;
    }
    denom_priv->cipher = TALER_DENOMINATION_INVALID;
    return;
  case TALER_DENOMINATION_CS:
    return;
  default:
    GNUNET_assert (0);
  }
}


void
TALER_denom_sig_free (struct TALER_DenominationSignature *denom_sig)
{
  switch (denom_sig->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    return;
  case TALER_DENOMINATION_RSA:
    if (NULL != denom_sig->details.rsa_signature)
    {
      GNUNET_CRYPTO_rsa_signature_free (denom_sig->details.rsa_signature);
      denom_sig->details.rsa_signature = NULL;
    }
    denom_sig->cipher = TALER_DENOMINATION_INVALID;
    return;
  case TALER_DENOMINATION_CS:
    return;
  default:
    GNUNET_assert (0);
  }
}


void
TALER_blinded_denom_sig_free (
  struct TALER_BlindedDenominationSignature *denom_sig)
{
  switch (denom_sig->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    return;
  case TALER_DENOMINATION_RSA:
    if (NULL != denom_sig->details.blinded_rsa_signature)
    {
      GNUNET_CRYPTO_rsa_signature_free (
        denom_sig->details.blinded_rsa_signature);
      denom_sig->details.blinded_rsa_signature = NULL;
    }
    denom_sig->cipher = TALER_DENOMINATION_INVALID;
    return;
  case TALER_DENOMINATION_CS:
    return;
  default:
    GNUNET_assert (0);
  }
}


void
TALER_denom_pub_deep_copy (struct TALER_DenominationPublicKey *denom_dst,
                           const struct TALER_DenominationPublicKey *denom_src)
{
  *denom_dst = *denom_src; /* shallow copy */
  switch (denom_src->cipher)
  {
  case TALER_DENOMINATION_RSA:
    denom_dst->details.rsa_public_key
      = GNUNET_CRYPTO_rsa_public_key_dup (
          denom_src->details.rsa_public_key);
    return;
  case TALER_DENOMINATION_CS:
    return;
  default:
    GNUNET_assert (0);
  }
}


void
TALER_denom_sig_deep_copy (struct TALER_DenominationSignature *denom_dst,
                           const struct TALER_DenominationSignature *denom_src)
{
  *denom_dst = *denom_src; /* shallow copy */
  switch (denom_src->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    return;
  case TALER_DENOMINATION_RSA:
    denom_dst->details.rsa_signature
      = GNUNET_CRYPTO_rsa_signature_dup (
          denom_src->details.rsa_signature);
    return;
  case TALER_DENOMINATION_CS:
    return;
  default:
    GNUNET_assert (0);
  }
}


void
TALER_blinded_denom_sig_deep_copy (
  struct TALER_BlindedDenominationSignature *denom_dst,
  const struct TALER_BlindedDenominationSignature *denom_src)
{
  *denom_dst = *denom_src; /* shallow copy */
  switch (denom_src->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    return;
  case TALER_DENOMINATION_RSA:
    denom_dst->details.blinded_rsa_signature
      = GNUNET_CRYPTO_rsa_signature_dup (
          denom_src->details.blinded_rsa_signature);
    return;
  case TALER_DENOMINATION_CS:
    return;
  default:
    GNUNET_assert (0);
  }
}


int
TALER_denom_pub_cmp (const struct TALER_DenominationPublicKey *denom1,
                     const struct TALER_DenominationPublicKey *denom2)
{
  if (denom1->cipher != denom2->cipher)
    return (denom1->cipher > denom2->cipher) ? 1 : -1;
  if (denom1->age_mask.mask != denom2->age_mask.mask)
    return (denom1->age_mask.mask > denom2->age_mask.mask) ? 1 : -1;
  switch (denom1->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    return 0;
  case TALER_DENOMINATION_RSA:
    return GNUNET_CRYPTO_rsa_public_key_cmp (denom1->details.rsa_public_key,
                                             denom2->details.rsa_public_key);
  case TALER_DENOMINATION_CS:
    return GNUNET_memcmp (&denom1->details.cs_public_key,
                          &denom2->details.cs_public_key);
  default:
    GNUNET_assert (0);
  }
  return -2;
}


int
TALER_denom_sig_cmp (const struct TALER_DenominationSignature *sig1,
                     const struct TALER_DenominationSignature *sig2)
{
  if (sig1->cipher != sig2->cipher)
    return (sig1->cipher > sig2->cipher) ? 1 : -1;
  switch (sig1->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    return 0;
  case TALER_DENOMINATION_RSA:
    return GNUNET_CRYPTO_rsa_signature_cmp (sig1->details.rsa_signature,
                                            sig2->details.rsa_signature);
  case TALER_DENOMINATION_CS:
    return GNUNET_memcmp (&sig1->details.cs_signature,
                          &sig2->details.cs_signature);
  default:
    GNUNET_assert (0);
  }
  return -2;
}


int
TALER_blinded_planchet_cmp (
  const struct TALER_BlindedPlanchet *bp1,
  const struct TALER_BlindedPlanchet *bp2)
{
  if (bp1->cipher != bp2->cipher)
    return (bp1->cipher > bp2->cipher) ? 1 : -1;
  switch (bp1->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    return 0;
  case TALER_DENOMINATION_RSA:
    if (bp1->details.rsa_blinded_planchet.blinded_msg_size !=
        bp2->details.rsa_blinded_planchet.blinded_msg_size)
      return (bp1->details.rsa_blinded_planchet.blinded_msg_size >
              bp2->details.rsa_blinded_planchet.blinded_msg_size) ? 1 : -1;
    return memcmp (bp1->details.rsa_blinded_planchet.blinded_msg,
                   bp2->details.rsa_blinded_planchet.blinded_msg,
                   bp1->details.rsa_blinded_planchet.blinded_msg_size);
  case TALER_DENOMINATION_CS:
    return GNUNET_memcmp (&bp1->details.cs_blinded_planchet,
                          &bp2->details.cs_blinded_planchet);
  default:
    GNUNET_assert (0);
  }
  return -2;
}


int
TALER_blinded_denom_sig_cmp (
  const struct TALER_BlindedDenominationSignature *sig1,
  const struct TALER_BlindedDenominationSignature *sig2)
{
  if (sig1->cipher != sig2->cipher)
    return (sig1->cipher > sig2->cipher) ? 1 : -1;
  switch (sig1->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    return 0;
  case TALER_DENOMINATION_RSA:
    return GNUNET_CRYPTO_rsa_signature_cmp (sig1->details.blinded_rsa_signature,
                                            sig2->details.blinded_rsa_signature);
  case TALER_DENOMINATION_CS:
    return GNUNET_memcmp (&sig1->details.blinded_cs_answer,
                          &sig2->details.blinded_cs_answer);
  default:
    GNUNET_assert (0);
  }
  return -2;
}


void
TALER_blinded_planchet_hash_ (const struct TALER_BlindedPlanchet *bp,
                              struct GNUNET_HashContext *hash_context)
{
  uint32_t cipher = htonl (bp->cipher);

  GNUNET_CRYPTO_hash_context_read (hash_context,
                                   &cipher,
                                   sizeof (cipher));
  switch (bp->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    break;
  case TALER_DENOMINATION_RSA:
    GNUNET_CRYPTO_hash_context_read (
      hash_context,
      bp->details.rsa_blinded_planchet.blinded_msg,
      bp->details.rsa_blinded_planchet.blinded_msg_size);
    break;
  case TALER_DENOMINATION_CS:
    GNUNET_CRYPTO_hash_context_read (
      hash_context,
      &bp->details.cs_blinded_planchet,
      sizeof (bp->details.cs_blinded_planchet));
    break;
  default:
    GNUNET_assert (0);
    break;
  }
}


void
TALER_planchet_blinding_secret_create (
  const struct TALER_PlanchetMasterSecretP *ps,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  union TALER_DenominationBlindingKeyP *bks)
{
  switch (alg_values->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    GNUNET_break (0);
    return;
  case TALER_DENOMINATION_RSA:
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
  case TALER_DENOMINATION_CS:
    GNUNET_assert (GNUNET_YES ==
                   GNUNET_CRYPTO_kdf (&bks->nonce,
                                      sizeof (bks->nonce),
                                      "bseed",
                                      strlen ("bseed"),
                                      ps,
                                      sizeof(*ps),
                                      &alg_values->details.cs_values,
                                      sizeof(alg_values->details.cs_values),
                                      NULL,
                                      0));
    return;
  default:
    GNUNET_break (0);
  }
}


void
TALER_planchet_setup_coin_priv (
  const struct TALER_PlanchetMasterSecretP *ps,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  struct TALER_CoinSpendPrivateKeyP *coin_priv)
{
  switch (alg_values->cipher)
  {
  case TALER_DENOMINATION_RSA:
    GNUNET_assert (GNUNET_YES ==
                   GNUNET_CRYPTO_kdf (coin_priv,
                                      sizeof (*coin_priv),
                                      "coin",
                                      strlen ("coin"),
                                      ps,
                                      sizeof(*ps),
                                      NULL,
                                      0));
    break;
  case TALER_DENOMINATION_CS:
    GNUNET_assert (GNUNET_YES ==
                   GNUNET_CRYPTO_kdf (coin_priv,
                                      sizeof (*coin_priv),
                                      "coin",
                                      strlen ("coin"),
                                      ps,
                                      sizeof(*ps),
                                      &alg_values->details.cs_values,
                                      sizeof(alg_values->details.cs_values),
                                      NULL,
                                      0));
    break;
  default:
    GNUNET_break (0);
    return;
  }
  coin_priv->eddsa_priv.d[0] &= 248;
  coin_priv->eddsa_priv.d[31] &= 127;
  coin_priv->eddsa_priv.d[31] |= 64;
}


void
TALER_blinded_planchet_free (struct TALER_BlindedPlanchet *blinded_planchet)
{
  switch (blinded_planchet->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    GNUNET_break (0);
    return;
  case TALER_DENOMINATION_RSA:
    GNUNET_free (blinded_planchet->details.rsa_blinded_planchet.blinded_msg);
    return;
  case TALER_DENOMINATION_CS:
    memset (blinded_planchet,
            0,
            sizeof (*blinded_planchet));
    /* nothing to do for CS */
    return;
  }
  GNUNET_assert (0);
}


/* end of denom.c */
