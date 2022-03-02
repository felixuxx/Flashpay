/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

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
 * @file util/age_restriction.c
 * @brief Functions that are used for age restriction
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include <gcrypt.h>

void
TALER_age_commitment_hash (
  const struct TALER_AgeCommitment *commitment,
  struct TALER_AgeCommitmentHash *ahash)
{
  struct GNUNET_HashContext *hash_context;
  struct GNUNET_HashCode hash;

  GNUNET_assert (NULL != ahash);
  if (NULL == commitment)
  {
    memset (ahash, 0, sizeof(struct TALER_AgeCommitmentHash));
    return;
  }

  GNUNET_assert (__builtin_popcount (commitment->mask.bits) - 1 ==
                 commitment->num);

  hash_context = GNUNET_CRYPTO_hash_context_start ();

  for (size_t i = 0; i < commitment->num; i++)
  {
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &commitment->pub[i],
                                     sizeof(struct
                                            GNUNET_CRYPTO_EddsaPublicKey));
  }

  GNUNET_CRYPTO_hash_context_finish (hash_context,
                                     &hash);
  GNUNET_memcpy (&ahash->shash.bits,
                 &hash.bits,
                 sizeof(ahash->shash.bits));
}


/* To a given age value between 0 and 31, returns the index of the age group
 * defined by the given mask.
 */
static uint8_t
get_age_group (
  const struct TALER_AgeMask *mask,
  uint8_t age)
{
  uint32_t m = mask->bits;
  uint8_t i = 0;

  while (m > 0)
  {
    if (0 >= age)
      break;
    m = m >> 1;
    i += m & 1;
    age--;
  }
  return i;
}


enum GNUNET_GenericReturnValue
TALER_age_restriction_commit (
  const struct TALER_AgeMask *mask,
  const uint8_t age,
  const uint64_t salt,
  struct TALER_AgeCommitmentProof *new)
{
  uint8_t num_pub = __builtin_popcount (mask->bits) - 1;
  uint8_t num_priv = get_age_group (mask, age);
  size_t i;

  GNUNET_assert (NULL != new);
  GNUNET_assert (mask->bits & 1); /* fist bit must have been set */
  GNUNET_assert (0 <= num_priv);
  GNUNET_assert (31 > num_priv);
  GNUNET_assert (num_priv <= num_pub);

  new->commitment.mask.bits = mask->bits;
  new->commitment.num = num_pub;
  new->proof.num = num_priv;
  new->proof.priv = NULL;

  new->commitment.pub = GNUNET_new_array (
    num_pub,
    struct TALER_AgeCommitmentPublicKeyP);

  if (0 < num_priv)
    new->proof.priv = GNUNET_new_array (
      num_priv,
      struct TALER_AgeCommitmentPrivateKeyP);

  /* Create as many private keys as we need and fill the rest of the
   * public keys with valid curve points.
   * We need to make sure that the public keys are proper points on the
   * elliptic curve, so we can't simply fill the struct with random values. */
  for (i = 0; i < num_pub; i++)
  {
    uint64_t saltBE = htonl (salt + i);
    struct TALER_AgeCommitmentPrivateKeyP key = {0};
    struct TALER_AgeCommitmentPrivateKeyP *priv = &key;

    /* Only save the private keys for age groups less than num_priv */
    if (i < num_priv)
      priv = &new->proof.priv[i];

    if  (GNUNET_OK !=
         GNUNET_CRYPTO_kdf (priv,
                            sizeof (*priv),
                            &saltBE,
                            sizeof (saltBE),
                            "taler-age-commitment-derivation",
                            strlen (
                              "taler-age-commitment-derivation"),
                            NULL, 0))
      goto FAIL;

    GNUNET_CRYPTO_eddsa_key_get_public (&priv->eddsa_priv,
                                        &new->commitment.pub[i].eddsa_pub);
  }

  return GNUNET_OK;

FAIL:
  GNUNET_free (new->commitment.pub);
  if (NULL != new->proof.priv)
    GNUNET_free (new->proof.priv);
  return GNUNET_SYSERR;
}


enum GNUNET_GenericReturnValue
TALER_age_commitment_derive (
  const struct TALER_AgeCommitmentProof *orig,
  const uint64_t salt,
  struct TALER_AgeCommitmentProof *new)
{
  struct GNUNET_CRYPTO_EccScalar scalar;
  uint64_t saltBT = htonl (salt);
  int64_t factor;

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_kdf (
                   &factor,
                   sizeof (factor),
                   &saltBT,
                   sizeof (saltBT),
                   "taler-age-restriction-derivation",
                   strlen ("taler-age-restriction-derivation"),
                   NULL, 0));

  GNUNET_CRYPTO_ecc_scalar_from_int (factor, &scalar);

  /*
  * age commitment consists of GNUNET_CRYPTO_Eddsa{Private,Public}Key
  *
  * GNUNET_CRYPTO_EddsaPrivateKey is a
  *   unsigned char d[256 / 8];
  *
  * GNUNET_CRYPTO_EddsaPublicKey is a
  *   unsigned char q_y[256 / 8];
  *
  * We want to multiply, both, the Private Key by an integer factor and the
  * public key (point on curve) with the equivalent scalar.
  *
  * From the salt we will derive
  *   1. a scalar to multiply the public keys with
  *   2. a factor to multiply the private key with
  *
  * Invariants:
  *   point*scalar == public(private*factor)
  *
  * A point on a curve is GNUNET_CRYPTO_EccPoint which is
  *   unsigned char v[256 / 8];
  *
  * A ECC scalar for use in point multiplications is a
  * GNUNET_CRYPTO_EccScalar which is a
  *   unsigned char v[256 / 8];
  * */

  GNUNET_assert (NULL != new);
  GNUNET_assert (orig->commitment.num== __builtin_popcount (
                   orig->commitment.mask.bits) - 1);
  GNUNET_assert (orig->proof.num <= orig->commitment.num);

  new->commitment.mask = orig->commitment.mask;
  new->commitment.num = orig->commitment.num;
  new->proof.num = orig->proof.num;
  new->commitment.pub = GNUNET_new_array (
    new->commitment.num,
    struct TALER_AgeCommitmentPublicKeyP);
  new->proof.priv = GNUNET_new_array (
    new->proof.num,
    struct TALER_AgeCommitmentPrivateKeyP);

  /* scalar multiply the public keys on the curve */
  for (size_t i = 0; i < orig->commitment.num; i++)
  {
    /* We shift all keys by the same scalar */
    struct GNUNET_CRYPTO_EccPoint *p = (struct
                                        GNUNET_CRYPTO_EccPoint *) &orig->
                                       commitment.pub[i];
    struct GNUNET_CRYPTO_EccPoint *np = (struct
                                         GNUNET_CRYPTO_EccPoint *) &new->
                                        commitment.pub[i];
    if (GNUNET_OK !=
        GNUNET_CRYPTO_ecc_pmul_mpi (
          p,
          &scalar,
          np))
      goto FAIL;

  }

  /* multiply the private keys */
  /* we borough ideas from GNUNET_CRYPTO_ecdsa_private_key_derive */
  {
    for (size_t i = 0; i < orig->proof.num; i++)
    {
      uint8_t dc[32];
      gcry_mpi_t f, x, d, n;
      gcry_ctx_t ctx;

      GNUNET_assert (0==gcry_mpi_ec_new (&ctx, NULL, "Ed25519"));
      n = gcry_mpi_ec_get_mpi ("n", ctx, 1);

      GNUNET_CRYPTO_mpi_scan_unsigned (&f, (unsigned char*) &factor,
                                       sizeof(factor));

      for (size_t j = 0; j < 32; j++)
        dc[i] = orig->proof.priv[i].eddsa_priv.d[31 - j];
      GNUNET_CRYPTO_mpi_scan_unsigned (&x, dc, sizeof(dc));

      d = gcry_mpi_new (256);
      gcry_mpi_mulm (d, f, x, n);
      GNUNET_CRYPTO_mpi_print_unsigned (dc, sizeof(dc), d);

      for (size_t j = 0; j <32; j++)
        new->proof.priv[i].eddsa_priv.d[j] = dc[31 - 1];

      sodium_memzero (dc, sizeof(dc));
      gcry_mpi_release (d);
      gcry_mpi_release (x);
      gcry_mpi_release (n);
      gcry_mpi_release (f);
      gcry_ctx_release (ctx);

      /* TODO: add test to make sure that the calculated private key generate
       * the same public keys */
    }

  }

  return GNUNET_OK;

FAIL:
  GNUNET_free (new->commitment.pub);
  GNUNET_free (new->proof.priv);
  return GNUNET_SYSERR;
}


enum GNUNET_GenericReturnValue
TALER_age_commitment_attest (
  const struct TALER_AgeCommitmentProof *cp,
  uint8_t age,
  struct TALER_AgeAttestation *attest)
{
  uint8_t group;

  GNUNET_assert (NULL != attest);
  GNUNET_assert (NULL != cp);

  group = get_age_group (&cp->commitment.mask,
                         age);

  GNUNET_assert (group < 32);

  if (0 == group)
  {
    /* Age group 0 means: no attestation necessary.
     * We set the signature to zero and communicate success. */
    memset (attest,
            0,
            sizeof(struct TALER_AgeAttestation));
    return GNUNET_OK;
  }

  if (group >= cp->proof.num)
    return GNUNET_NO;

  {
    struct TALER_AgeAttestationPS at = {
      .purpose.size = htonl (sizeof(at)),
      .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_AGE_ATTESTATION),
      .mask = cp->commitment.mask,
      .age = age
    };

    GNUNET_CRYPTO_eddsa_sign (&cp->proof.priv[group - 1].eddsa_priv,
                              &at,
                              &attest->eddsa_signature);
  }

  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_age_commitment_verify (
  const struct TALER_AgeCommitment *comm,
  uint8_t age,
  const struct TALER_AgeAttestation *attest)
{
  uint8_t group;

  GNUNET_assert (NULL != attest);
  GNUNET_assert (NULL != comm);

  group = get_age_group (&comm->mask,
                         age);

  GNUNET_assert (group < 32);

  /* Age group 0 means: no attestation necessary. */
  if (0 == group)
    return GNUNET_OK;

  if (group >= comm->num)
    return GNUNET_NO;

  {
    struct TALER_AgeAttestationPS at = {
      .purpose.size = htonl (sizeof(at)),
      .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_AGE_ATTESTATION),
      .mask = comm->mask,
      .age = age,
    };

    return
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_AGE_ATTESTATION,
                                  &at,
                                  &attest->eddsa_signature,
                                  &comm->pub[group - 1].eddsa_pub);
  }
}


void
TALER_age_commitment_free (
  struct TALER_AgeCommitment *commitment)
{
  if (NULL == commitment)
    return;

  if (NULL != commitment->pub)
  {
    GNUNET_free (commitment->pub);
    commitment->pub = NULL;
  }
  GNUNET_free (commitment);
}


void
TALER_age_proof_free (
  struct TALER_AgeProof *proof)
{
  if (NULL != proof->priv)
  {
    GNUNET_CRYPTO_zero_keys (
      proof->priv,
      sizeof(*proof->priv) * proof->num);

    GNUNET_free (proof->priv);
    proof->priv = NULL;
  }
  GNUNET_free (proof);
}


void
TALER_age_commitment_proof_free (
  struct TALER_AgeCommitmentProof *cp)
{
  if (NULL != cp->proof.priv)
  {
    GNUNET_CRYPTO_zero_keys (
      cp->proof.priv,
      sizeof(*cp->proof.priv) * cp->proof.num);

    GNUNET_free (cp->proof.priv);
    cp->proof.priv = NULL;
  }

  if (NULL != cp->commitment.pub)
  {
    GNUNET_free (cp->commitment.pub);
    cp->commitment.pub = NULL;
  }
}
