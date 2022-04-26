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

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "popcount - 1: %d\n",
              __builtin_popcount (commitment->mask.bits) - 1);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "commitment num: %d\n",
              commitment->num);

  GNUNET_assert (__builtin_popcount (commitment->mask.bits) - 1 ==
                 commitment->num);

  hash_context = GNUNET_CRYPTO_hash_context_start ();

  for (size_t i = 0; i < commitment->num; i++)
  {
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &commitment->keys[i],
                                     sizeof(commitment->keys[i]));
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
uint8_t
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
  const struct GNUNET_HashCode *seed,
  struct TALER_AgeCommitmentProof *new)
{
  struct GNUNET_HashCode seed_i;
  uint8_t num_pub = __builtin_popcount (mask->bits) - 1;
  uint8_t num_priv = get_age_group (mask, age);
  size_t i;

  GNUNET_assert (NULL != seed);
  GNUNET_assert (NULL != new);
  GNUNET_assert (mask->bits & 1); /* fist bit must have been set */
  GNUNET_assert (0 <= num_priv);
  GNUNET_assert (31 > num_priv);
  GNUNET_assert (num_priv <= num_pub);

  seed_i = *seed;
  new->commitment.mask.bits = mask->bits;
  new->commitment.num = num_pub;
  new->proof.num = num_priv;
  new->proof.keys = NULL;

  new->commitment.keys = GNUNET_new_array (
    num_pub,
    struct TALER_AgeCommitmentPublicKeyP);

  if (0 < num_priv)
    new->proof.keys = GNUNET_new_array (
      num_priv,
      struct TALER_AgeCommitmentPrivateKeyP);

  /* Create as many private keys as we need and fill the rest of the
   * public keys with valid curve points.
   * We need to make sure that the public keys are proper points on the
   * elliptic curve, so we can't simply fill the struct with random values. */
  for (i = 0; i < num_pub; i++)
  {
    struct TALER_AgeCommitmentPrivateKeyP key = {0};
    struct TALER_AgeCommitmentPrivateKeyP *pkey = &key;

    /* Only save the private keys for age groups less than num_priv */
    if (i < num_priv)
      pkey = &new->proof.keys[i];

#ifndef AGE_RESTRICTION_WITH_ECDSA
    GNUNET_CRYPTO_edx25519_key_create_from_seed (&seed_i,
                                                 sizeof(seed_i),
                                                 &pkey->priv);
    GNUNET_CRYPTO_edx25519_key_get_public (&pkey->priv,
                                           &new->commitment.keys[i].pub);
    seed_i.bits[0] += 1;
  }

  return GNUNET_OK;
#else
    if  (GNUNET_OK !=
         GNUNET_CRYPTO_kdf (pkey,
                            sizeof (*pkey),
                            &salti,
                            sizeof (salti),
                            "age commitment",
                            strlen ("age commitment"),
                            NULL, 0))
      goto FAIL;

    /* See GNUNET_CRYPTO_ecdsa_key_create */
    pkey->priv.d[0] &= 248;
    pkey->priv.d[31] &= 127;
    pkey->priv.d[31] |= 64;

    GNUNET_CRYPTO_ecdsa_key_get_public (&pkey->priv,
                                        &new->commitment.keys[i].pub);

  }

  return GNUNET_OK;

FAIL:
  GNUNET_free (new->commitment.keys);
  if (NULL != new->proof.keys)
    GNUNET_free (new->proof.keys);
  return GNUNET_SYSERR;
#endif
}


enum GNUNET_GenericReturnValue
TALER_age_commitment_derive (
  const struct TALER_AgeCommitmentProof *orig,
  const uint64_t salt,
  struct TALER_AgeCommitmentProof *newacp)
{
  GNUNET_assert (NULL != newacp);
  GNUNET_assert (orig->proof.num <=
                 orig->commitment.num);
  GNUNET_assert (orig->commitment.num ==
                 __builtin_popcount (orig->commitment.mask.bits) - 1);

  newacp->commitment.mask = orig->commitment.mask;
  newacp->commitment.num = orig->commitment.num;
  newacp->commitment.keys = GNUNET_new_array (
    newacp->commitment.num,
    struct TALER_AgeCommitmentPublicKeyP);

  newacp->proof.num = orig->proof.num;
  newacp->proof.keys = NULL;
  if (0 != newacp->proof.num)
    newacp->proof.keys = GNUNET_new_array (
      newacp->proof.num,
      struct TALER_AgeCommitmentPrivateKeyP);

#ifndef AGE_RESTRICTION_WITH_ECDSA
  /* 1. Derive the public keys */
  for (size_t i = 0; i < orig->commitment.num; i++)
  {
    GNUNET_CRYPTO_edx25519_public_key_derive (
      &orig->commitment.keys[i].pub,
      &salt,
      sizeof(salt),
      &newacp->commitment.keys[i].pub);
  }

  /* 2. Derive the private keys */
  for (size_t i = 0; i < orig->proof.num; i++)
  {
    GNUNET_CRYPTO_edx25519_private_key_derive (
      &orig->proof.keys[i].priv,
      &salt,
      sizeof(salt),
      &newacp->proof.keys[i].priv);
  }
#else
  char label[sizeof(uint64_t) + 1] = {0};

  /* Because GNUNET_CRYPTO_ecdsa_public_key_derive expects char * (and calls
   * strlen on it), we must avoid 0's in the label.  */
  uint64_t nz_salt = salt | 0x8040201008040201;
  memcpy (label, &nz_salt, sizeof(nz_salt));

  /* 1. Derive the public keys */
  for (size_t i = 0; i < orig->commitment.num; i++)
  {
    GNUNET_CRYPTO_ecdsa_public_key_derive (
      &orig->commitment.keys[i].pub,
      label,
      "age commitment derive",
      &newacp->commitment.keys[i].pub);
  }

  /* 2. Derive the private keys */
  for (size_t i = 0; i < orig->proof.num; i++)
  {
    struct GNUNET_CRYPTO_EcdsaPrivateKey *priv;
    priv = GNUNET_CRYPTO_ecdsa_private_key_derive (
      &orig->proof.keys[i].priv,
      label,
      "age commitment derive");
    newacp->proof.keys[i].priv = *priv;
    GNUNET_free (priv);
  }
#endif

  return GNUNET_OK;
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Age group mask in network byte order.
 */
struct TALER_AgeMaskNBO
{
  uint32_t bits_nbo;
};

/**
 * Used for attestation of a particular age
 */
struct TALER_AgeAttestationPS
{
  /**
   * Purpose must be #TALER_SIGNATURE_WALLET_AGE_ATTESTATION.
   * (no GNUNET_PACKED here because the struct is already packed)
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Age mask that defines the underlying age groups
   */
  struct TALER_AgeMaskNBO mask GNUNET_PACKED;

  /**
   * The particular age that this attestation is for.
   * We use uint32_t here for alignment.
   */
  uint32_t age GNUNET_PACKED;
};

GNUNET_NETWORK_STRUCT_END


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

  if (group > cp->proof.num)
    return GNUNET_NO;

  {
    struct TALER_AgeAttestationPS at = {
      .purpose.size = htonl (sizeof(at)),
      .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_AGE_ATTESTATION),
      .mask.bits_nbo = htonl (cp->commitment.mask.bits),
      .age = htonl (age),
    };

#ifndef AGE_RESTRICTION_WITH_ECDSA
  #define sign(a,b,c)  GNUNET_CRYPTO_edx25519_sign (a,b,c)
#else
  #define sign(a,b,c)  GNUNET_CRYPTO_ecdsa_sign (a,b,c)
#endif
    sign (&cp->proof.keys[group - 1].priv,
          &at,
          &attest->signature);
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

  if (group > comm->num)
  {
    GNUNET_break_op (0);
    return GNUNET_NO;
  }

  {
    struct TALER_AgeAttestationPS at = {
      .purpose.size = htonl (sizeof(at)),
      .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_AGE_ATTESTATION),
      .mask.bits_nbo = htonl (comm->mask.bits),
      .age = htonl (age),
    };

#ifndef AGE_RESTRICTION_WITH_ECDSA
  #define verify(a,b,c,d)      GNUNET_CRYPTO_edx25519_verify ((a),(b),(c),(d))
#else
  #define verify(a,b,c,d)      GNUNET_CRYPTO_ecdsa_verify ((a),(b),(c),(d))
#endif
    return verify (TALER_SIGNATURE_WALLET_AGE_ATTESTATION,
                   &at,
                   &attest->signature,
                   &comm->keys[group - 1].pub);
  }
}


void
TALER_age_commitment_free (
  struct TALER_AgeCommitment *commitment)
{
  if (NULL == commitment)
    return;

  if (NULL != commitment->keys)
  {
    GNUNET_free (commitment->keys);
    commitment->keys = NULL;
  }
  GNUNET_free (commitment);
}


void
TALER_age_proof_free (
  struct TALER_AgeProof *proof)
{
  if (NULL != proof->keys)
  {
    GNUNET_CRYPTO_zero_keys (
      proof->keys,
      sizeof(*proof->keys) * proof->num);

    GNUNET_free (proof->keys);
    proof->keys = NULL;
  }
  GNUNET_free (proof);
}


void
TALER_age_commitment_proof_free (
  struct TALER_AgeCommitmentProof *cp)
{
  if (NULL != cp->proof.keys)
  {
    GNUNET_CRYPTO_zero_keys (
      cp->proof.keys,
      sizeof(*cp->proof.keys) * cp->proof.num);

    GNUNET_free (cp->proof.keys);
    cp->proof.keys = NULL;
  }

  if (NULL != cp->commitment.keys)
  {
    GNUNET_free (cp->commitment.keys);
    cp->commitment.keys = NULL;
  }
}
