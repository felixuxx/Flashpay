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
TALER_denom_cs_derive_r_public (const struct TALER_WithdrawNonce *nonce,
                                const struct
                                TALER_DenominationPrivateKey *denom_priv,
                                struct TALER_DenominationCsPublicR *r_pub)
{
  if (denom_priv->cipher != TALER_DENOMINATION_CS)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  struct GNUNET_CRYPTO_CsRSecret r[2];
  GNUNET_CRYPTO_cs_r_derive (&nonce->nonce,
                             &denom_priv->details.cs_private_key,
                             r);
  GNUNET_CRYPTO_cs_r_get_public (&r[0], &r_pub->r_pub[0]);
  GNUNET_CRYPTO_cs_r_get_public (&r[1], &r_pub->r_pub[1]);
  return GNUNET_OK;
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
  const struct TALER_DenominationPublicKey *denom_pub,
  ...)
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
      va_list ap;
      va_start (ap, denom_pub);
      struct TALER_DenominationCsPublicR *r_pub_blind;
      r_pub_blind = va_arg (ap, struct TALER_DenominationCsPublicR *);

      struct GNUNET_CRYPTO_CsBlindingSecret bs[2];
      GNUNET_CRYPTO_cs_blinding_secrets_derive (&bks->nonce, bs);

      GNUNET_CRYPTO_cs_unblind (&bdenom_sig->details.blinded_cs_answer.s_scalar,
                                &bs[bdenom_sig->details.blinded_cs_answer.b],
                                &denom_sig->details.cs_signature.s_scalar);

      GNUNET_memcpy (&denom_sig->details.cs_signature.r_point,
                     &r_pub_blind->r_pub[bdenom_sig->details.blinded_cs_answer.b
                     ],
                     sizeof(struct GNUNET_CRYPTO_CsRPublic));

      denom_sig->cipher = TALER_DENOMINATION_CS;
      va_end (ap);
      return GNUNET_OK;
    }
  default:
    GNUNET_break (0);
  }
  return GNUNET_SYSERR;
}


/**
 * Hash @a rsa.
 *
 * @param rsa key to hash
 * @param[out] h_rsa where to write the result
 */
void
TALER_rsa_pub_hash (const struct GNUNET_CRYPTO_RsaPublicKey *rsa,
                    struct TALER_RsaPubHashP *h_rsa)
{
  GNUNET_CRYPTO_rsa_public_key_hash (rsa,
                                     &h_rsa->hash);

}


/**
 * Hash @a cs. key
 *
 * @param cs key to hash
 * @param[out] h_cs where to write the result
 */
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
TALER_denom_blind (const struct TALER_DenominationPublicKey *dk,
                   const union TALER_DenominationBlindingKeyP *coin_bks,
                   const struct TALER_AgeHash *age_commitment_hash,
                   const struct TALER_CoinSpendPublicKeyP *coin_pub,
                   struct TALER_CoinPubHash *c_hash,
                   struct TALER_BlindedPlanchet *blinded_planchet,
                   ...)
{
  TALER_coin_pub_hash (coin_pub,
                       age_commitment_hash,
                       c_hash);
  switch (dk->cipher)
  {
  case TALER_DENOMINATION_RSA:
    blinded_planchet->cipher = dk->cipher;

    if (GNUNET_YES !=
        GNUNET_CRYPTO_rsa_blind (&c_hash->hash,
                                 &coin_bks->rsa_bks,
                                 dk->details.rsa_public_key,
                                 &blinded_planchet->details.rsa_blinded_planchet
                                 .blinded_msg,
                                 &blinded_planchet->details.rsa_blinded_planchet
                                 .blinded_msg_size))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    return GNUNET_OK;
  case TALER_DENOMINATION_CS:
    {
      blinded_planchet->cipher = dk->cipher;
      va_list ap;
      va_start (ap, blinded_planchet);
      struct TALER_DenominationCsPublicR *r_pub;
      struct TALER_DenominationCsPublicR *blinded_r_pub;

      r_pub = va_arg (ap, struct TALER_DenominationCsPublicR *);
      blinded_r_pub = va_arg (ap, struct TALER_DenominationCsPublicR *);

      struct GNUNET_CRYPTO_CsBlindingSecret bs[2];
      GNUNET_CRYPTO_cs_blinding_secrets_derive (&coin_bks->nonce, bs);

      GNUNET_CRYPTO_cs_calc_blinded_c (bs,
                                       r_pub->r_pub,
                                       &dk->details.cs_public_key,
                                       &c_hash->hash,
                                       sizeof(struct GNUNET_HashCode),
                                       blinded_planchet->details.
                                       cs_blinded_planchet.c,
                                       blinded_r_pub->r_pub);

      va_end (ap);
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
    // ATM nothing needs to be freed, but check again after implementation.
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
    // ATM nothing needs to be freed, but check again after implementation.
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
    // ATM nothing needs to be freed, but check again after implementation.
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
    // ATM nothing needs to be freed, but check again after implementation.
    return;
  default:
    GNUNET_assert (0);
  }
}


/**
 * Make a (deep) copy of the given @a denom_src to
 * @a denom_dst.
 *
 * @param[out] denom_dst target to copy to
 * @param denom_str public key to copy
 */
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
    // In Case of CS, the above is already a deep copy *denom_dst = *denom_src;
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
    // In Case of CS, the above is already a deep copy *denom_dst = *denom_src;
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
    // In Case of CS, the above is already a deep copy *denom_dst = *denom_src;
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


/* end of denom.c */
