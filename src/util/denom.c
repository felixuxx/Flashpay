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


void
TALER_denom_pub_hash (const struct TALER_DenominationPublicKey *denom_pub,
                      struct TALER_DenominationHash *denom_hash)
{
  uint32_t opt[2] = {
    htonl (denom_pub->age_mask),
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
  // TODO: add case for Clause-Schnorr
  default:
    GNUNET_assert (0);
  }
  GNUNET_CRYPTO_hash_context_finish (hc,
                                     &denom_hash->hash);
}


void
TALER_denom_priv_to_pub (const struct TALER_DenominationPrivateKey *denom_priv,
                         uint32_t age_mask,
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
  // TODO: add case for Clause-Schnorr
  default:
    GNUNET_assert (0);
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
  // TODO: add case for Clause-Schnorr
  default:
    GNUNET_assert (0);
  }
}


void
TALER_denom_pub_free (struct TALER_DenominationPublicKey *denom_pub)
{
  switch (denom_pub->cipher)
  {
  case TALER_DENOMINATION_RSA:
    if (NULL != denom_pub->details.rsa_public_key)
    {
      GNUNET_CRYPTO_rsa_public_key_free (denom_pub->details.rsa_public_key);
      denom_pub->details.rsa_public_key = NULL;
    }
    return;
  // TODO: add case for Clause-Schnorr
  default:
    GNUNET_assert (0);
  }
}


void
TALER_denom_priv_free (struct TALER_DenominationPrivateKey *denom_priv)
{
  switch (denom_priv->cipher)
  {
  case TALER_DENOMINATION_RSA:
    if (NULL != denom_priv->details.rsa_private_key)
    {
      GNUNET_CRYPTO_rsa_private_key_free (denom_priv->details.rsa_private_key);
      denom_priv->details.rsa_private_key = NULL;
    }
    return;
  // TODO: add case for Clause-Schnorr
  default:
    GNUNET_assert (0);
  }
}


void
TALER_denom_sig_free (struct TALER_DenominationSignature *denom_sig)
{
  switch (denom_sig->cipher)
  {
  case TALER_DENOMINATION_RSA:
    if (NULL != denom_sig->details.rsa_signature)
    {
      GNUNET_CRYPTO_rsa_signature_free (denom_sig->details.rsa_signature);
      denom_sig->details.rsa_signature = NULL;
    }
    return;
  // TODO: add case for Clause-Schnorr
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
  // TODO: add case for Clause-Schnorr
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
  case TALER_DENOMINATION_RSA:
    denom_dst->details.rsa_signature
      = GNUNET_CRYPTO_rsa_signature_dup (
          denom_src->details.rsa_signature);
    return;
  // TODO: add case for Clause-Schnorr
  default:
    GNUNET_assert (0);
  }
}


/**
 * Compare two denomination public keys.
 *
 * @param denom1 first key
 * @param denom2 second key
 * @return 0 if the keys are equal, otherwise -1 or 1
 */
int
TALER_denom_pub_cmp (const struct TALER_DenominationPublicKey *denom1,
                     const struct TALER_DenominationPublicKey *denom2)
{
  if (denom1->cipher != denom2->cipher)
    return (denom1->cipher > denom2->cipher) ? 1 : -1;
  if (denom1->age_mask != denom2->age_mask)
    return (denom1->age_mask > denom2->age_mask) ? 1 : -1;
  switch (denom1->cipher)
  {
  case TALER_DENOMINATION_RSA:
    return GNUNET_CRYPTO_rsa_public_key_cmp (denom1->details.rsa_public_key,
                                             denom2->details.rsa_public_key);
  // TODO: add case for Clause-Schnorr
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
  case TALER_SIGINATION_RSA:
    return GNUNET_CRYPTO_rsa_signature_cmp (sig1->details.rsa_signature,
                                            sig2->details.rsa_signature);
  // TODO: add case for Clause-Schnorr
  default:
    GNUNET_assert (0);
  }
  return -2;
}


/* end of denom.c */
