/*
  This file is part of TALER
  Copyright (C) 2022-2023 Taler Systems SA

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
#include <gnunet/gnunet_json_lib.h>
#include <gcrypt.h>
#include <stdint.h>

struct
#ifndef AGE_RESTRICTION_WITH_ECDSA
GNUNET_CRYPTO_Edx25519PublicKey
#else
GNUNET_CRYPTO_EcdsaPublicKey
#endif
TALER_age_commitment_base_public_key = {
  .q_y = { 0x6f, 0xe5, 0x87, 0x9a, 0x3d, 0xa9, 0x44, 0x20,
           0x80, 0xbd, 0x6a, 0xb9, 0x44, 0x56, 0x91, 0x19,
           0xaf, 0xb4, 0xc8, 0x7b, 0x89, 0xce, 0x23, 0x17,
           0x97, 0x20, 0x5c, 0xbb, 0x9c, 0xd7, 0xcc, 0xd9},
};

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
                 (int) commitment->num);

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
TALER_get_age_group (
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


uint8_t
TALER_get_lowest_age (
  const struct TALER_AgeMask *mask,
  uint8_t age)
{
  uint32_t m = mask->bits;
  uint8_t group = TALER_get_age_group (mask, age);
  uint8_t lowest = 0;

  while (group > 0)
  {
    m = m >> 1;
    if (m & 1)
      group--;
    lowest++;
  }

  return lowest;
}


#ifdef AGE_RESTRICTION_WITH_ECDSA
/* @brief Helper function to generate a ECDSA private key
 *
 * @param seed Input seed
 * @param size Size of the seed in bytes
 * @param[out] pkey ECDSA private key
 * @return GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
ecdsa_create_from_seed (
  const void *seed,
  size_t seed_size,
  struct GNUNET_CRYPTO_EcdsaPrivateKey *key)
{
  enum GNUNET_GenericReturnValue ret;
  ret = GNUNET_CRYPTO_kdf (key,
                           sizeof (*key),
                           &seed,
                           seed_size,
                           "age commitment",
                           sizeof ("age commitment") - 1,
                           NULL, 0);
  if (GNUNET_OK != ret)
    return ret;

  /* See GNUNET_CRYPTO_ecdsa_key_create */
  key->d[0] &= 248;
  key->d[31] &= 127;
  key->d[31] |= 64;

  return GNUNET_OK;
}


#endif


enum GNUNET_GenericReturnValue
TALER_age_restriction_commit (
  const struct TALER_AgeMask *mask,
  uint8_t age,
  const struct GNUNET_HashCode *seed,
  struct TALER_AgeCommitmentProof *ncp)
{
  struct GNUNET_HashCode seed_i;
  uint8_t num_pub;
  uint8_t num_priv;
  size_t i;

  GNUNET_assert (NULL != mask);
  GNUNET_assert (NULL != seed);
  GNUNET_assert (NULL != ncp);
  GNUNET_assert (mask->bits & 1); /* first bit must have been set */

  num_pub = __builtin_popcount (mask->bits) - 1;
  num_priv = TALER_get_age_group (mask, age);

  GNUNET_assert (31 > num_priv);
  GNUNET_assert (num_priv <= num_pub);

  seed_i = *seed;
  ncp->commitment.mask.bits = mask->bits;
  ncp->commitment.num = num_pub;
  ncp->proof.num = num_priv;
  ncp->proof.keys = NULL;

  ncp->commitment.keys = GNUNET_new_array (
    num_pub,
    struct TALER_AgeCommitmentPublicKeyP);

  if (0 < num_priv)
    ncp->proof.keys = GNUNET_new_array (
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
      pkey = &ncp->proof.keys[i];

#ifndef AGE_RESTRICTION_WITH_ECDSA
    GNUNET_CRYPTO_edx25519_key_create_from_seed (&seed_i,
                                                 sizeof(seed_i),
                                                 &pkey->priv);
    GNUNET_CRYPTO_edx25519_key_get_public (&pkey->priv,
                                           &ncp->commitment.keys[i].pub);
#else
    if (GNUNET_OK !=
        ecdsa_create_from_seed (&seed_i,
                                sizeof(seed_i),
                                &pkey->priv))
    {
      GNUNET_free (ncp->commitment.keys);
      GNUNET_free (ncp->proof.keys);
      return GNUNET_SYSERR;
    }

    GNUNET_CRYPTO_ecdsa_key_get_public (&pkey->priv,
                                        &ncp->commitment.keys[i].pub);
#endif

    seed_i.bits[0] += 1;
  }

  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_age_commitment_derive (
  const struct TALER_AgeCommitmentProof *orig,
  const struct GNUNET_HashCode *salt,
  struct TALER_AgeCommitmentProof *newacp)
{
  GNUNET_assert (NULL != newacp);
  GNUNET_assert (orig->proof.num <=
                 orig->commitment.num);
  GNUNET_assert (((int) orig->commitment.num) ==
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
      salt,
      sizeof(*salt),
      &newacp->commitment.keys[i].pub);
  }

  /* 2. Derive the private keys */
  for (size_t i = 0; i < orig->proof.num; i++)
  {
    GNUNET_CRYPTO_edx25519_private_key_derive (
      &orig->proof.keys[i].priv,
      salt,
      sizeof(*salt),
      &newacp->proof.keys[i].priv);
  }
#else
  {
    const char *label = GNUNET_h2s (salt);

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

  group = TALER_get_age_group (&cp->commitment.mask,
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

  group = TALER_get_age_group (&comm->mask,
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
  if (NULL == proof)
    return;

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
  struct TALER_AgeCommitmentProof *acp)
{
  if (NULL == acp)
    return;

  if (NULL != acp->proof.keys)
  {
    GNUNET_CRYPTO_zero_keys (
      acp->proof.keys,
      sizeof(*acp->proof.keys) * acp->proof.num);

    GNUNET_free (acp->proof.keys);
    acp->proof.keys = NULL;
  }

  if (NULL != acp->commitment.keys)
  {
    GNUNET_free (acp->commitment.keys);
    acp->commitment.keys = NULL;
  }
}


struct TALER_AgeCommitmentProof *
TALER_age_commitment_proof_duplicate (
  const struct TALER_AgeCommitmentProof *acp)
{
  struct TALER_AgeCommitmentProof *nacp;

  GNUNET_assert (NULL != acp);
  GNUNET_assert (__builtin_popcount (acp->commitment.mask.bits) - 1 ==
                 (int) acp->commitment.num);

  nacp = GNUNET_new (struct TALER_AgeCommitmentProof);

  TALER_age_commitment_proof_deep_copy (acp,nacp);
  return nacp;
}


void
TALER_age_commitment_proof_deep_copy (
  const struct TALER_AgeCommitmentProof *acp,
  struct TALER_AgeCommitmentProof *nacp)
{
  GNUNET_assert (NULL != acp);
  GNUNET_assert (__builtin_popcount (acp->commitment.mask.bits) - 1 ==
                 (int) acp->commitment.num);

  *nacp = *acp;
  nacp->commitment.keys =
    GNUNET_new_array (acp->commitment.num,
                      struct TALER_AgeCommitmentPublicKeyP);
  nacp->proof.keys =
    GNUNET_new_array (acp->proof.num,
                      struct TALER_AgeCommitmentPrivateKeyP);

  for (size_t i = 0; i < acp->commitment.num; i++)
    nacp->commitment.keys[i] = acp->commitment.keys[i];

  for (size_t i = 0; i < acp->proof.num; i++)
    nacp->proof.keys[i] = acp->proof.keys[i];
}


enum GNUNET_GenericReturnValue
TALER_JSON_parse_age_groups (const json_t *root,
                             struct TALER_AgeMask *mask)
{
  enum GNUNET_GenericReturnValue ret;
  const char *str;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("age_groups",
                             &str),
    GNUNET_JSON_spec_end ()
  };

  ret = GNUNET_JSON_parse (root,
                           spec,
                           NULL,
                           NULL);
  if (GNUNET_OK == ret)
    TALER_parse_age_group_string (str, mask);

  GNUNET_JSON_parse_free (spec);

  return ret;
}


enum GNUNET_GenericReturnValue
TALER_parse_age_group_string (
  const char *groups,
  struct TALER_AgeMask *mask)
{

  const char *pos = groups;
  unsigned int prev = 0;
  unsigned int val = 0;
  char c;

  /* reset mask */
  mask->bits = 0;

  while (*pos)
  {
    c = *pos++;
    if (':' == c)
    {
      if (prev >= val)
        return GNUNET_SYSERR;

      mask->bits |= 1 << val;
      prev = val;
      val = 0;
      continue;
    }

    if ('0'>c || '9'<c)
      return GNUNET_SYSERR;

    val = 10 * val + c - '0';

    if (0>=val || 32<=val)
      return GNUNET_SYSERR;
  }

  if (32<=val || prev>=val)
    return GNUNET_SYSERR;

  mask->bits |= (1 << val);
  mask->bits |= 1; // mark zeroth group, too

  return GNUNET_OK;
}


const char *
TALER_age_mask_to_string (
  const struct TALER_AgeMask *mask)
{
  static char buf[256] = {0};
  uint32_t bits = mask->bits;
  unsigned int n = 0;
  char *pos = buf;

  memset (buf, 0, sizeof(buf));

  while (bits != 0)
  {
    bits >>= 1;
    n++;
    if (0 == (bits & 1))
    {
      continue;
    }

    if (n > 9)
    {
      *(pos++) = '0' + n / 10;
    }
    *(pos++) = '0' + n % 10;

    if (0 != (bits >> 1))
    {
      *(pos++) = ':';
    }
  }
  return buf;
}


enum GNUNET_GenericReturnValue
TALER_age_restriction_from_secret (
  const struct TALER_PlanchetMasterSecretP *secret,
  const struct TALER_AgeMask *mask,
  const uint8_t max_age,
  struct TALER_AgeCommitmentProof *ncp)
{
  struct GNUNET_HashCode seed_i = {0};
  uint8_t num_pub;
  uint8_t num_priv;

  GNUNET_assert (NULL != mask);
  GNUNET_assert (NULL != secret);
  GNUNET_assert (NULL != ncp);
  GNUNET_assert (mask->bits & 1); /* fist bit must have been set */

  num_pub = __builtin_popcount (mask->bits) - 1;
  num_priv = TALER_get_age_group (mask, max_age);

  GNUNET_assert (31 > num_priv);
  GNUNET_assert (num_priv <= num_pub);

  ncp->commitment.mask.bits = mask->bits;
  ncp->commitment.num = num_pub;
  ncp->proof.num = num_priv;
  ncp->proof.keys = NULL;

  ncp->commitment.keys = GNUNET_new_array (
    num_pub,
    struct TALER_AgeCommitmentPublicKeyP);

  if (0 < num_priv)
    ncp->proof.keys = GNUNET_new_array (
      num_priv,
      struct TALER_AgeCommitmentPrivateKeyP);

  /* Create as many private keys as allow with max_age and derive the
   * corresponding public keys.  The rest of the needed public keys are created
   * by scalar mulitplication with the TALER_age_commitment_base_public_key. */
  for (size_t i = 0; i < num_pub; i++)
  {
    enum GNUNET_GenericReturnValue ret;
    const char *label = i < num_priv ? "age-commitment" : "age-factor";

    ret = GNUNET_CRYPTO_kdf (&seed_i, sizeof(seed_i),
                             secret, sizeof(*secret),
                             label, strlen (label),
                             &i, sizeof(i),
                             NULL, 0);
    GNUNET_assert (GNUNET_OK == ret);

    /* Only generate and save the private keys and public keys for age groups
     * less than num_priv */
    if (i < num_priv)
    {
      struct TALER_AgeCommitmentPrivateKeyP *pkey = &ncp->proof.keys[i];

#ifndef AGE_RESTRICTION_WITH_ECDSA
      GNUNET_CRYPTO_edx25519_key_create_from_seed (&seed_i,
                                                   sizeof(seed_i),
                                                   &pkey->priv);
      GNUNET_CRYPTO_edx25519_key_get_public (&pkey->priv,
                                             &ncp->commitment.keys[i].pub);
#else
      if (GNUNET_OK != ecdsa_create_from_seed (&seed_i,
                                               sizeof(seed_i),
                                               &pkey->priv))
      {
        GNUNET_free (ncp->commitment.keys);
        GNUNET_free (ncp->proof.keys);
        return GNUNET_SYSERR;
      }
      GNUNET_CRYPTO_ecdsa_key_get_public (&pkey->priv,
                                          &ncp->commitment.keys[i].pub);
#endif
    }
    else
    {
      /* For all indices larger than num_priv, derive a public key from
       * TALER_age_commitment_base_public_key by scalar multiplication */
#ifndef AGE_RESTRICTION_WITH_ECDSA
      GNUNET_CRYPTO_edx25519_public_key_derive (
        &TALER_age_commitment_base_public_key,
        &seed_i,
        sizeof(seed_i),
        &ncp->commitment.keys[i].pub);
#else

      GNUNET_CRYPTO_ecdsa_public_key_derive (
        &TALER_age_commitment_base_public_key,
        GNUNET_h2s (&seed_i),
        "age withdraw",
        &ncp->commitment.keys[i].pub);
#endif
    }
  }

  return GNUNET_OK;

}


enum GNUNET_GenericReturnValue
TALER_parse_coarse_date (
  const char *in,
  const struct TALER_AgeMask *mask,
  uint32_t *out)
{
  struct tm date = {0};
  struct tm limit = {0};
  time_t seconds;

  if (NULL == in)
  {
    /* FIXME[oec]: correct behaviour? */
    *out = 0;
    return GNUNET_OK;
  }

  GNUNET_assert (NULL !=mask);
  GNUNET_assert (NULL !=out);

  if (NULL == strptime (in, "%Y-%0m-%0d", &date))
  {
    if (NULL == strptime (in, "%Y-%0m-00", &date))
      if (NULL == strptime (in, "%Y-00-00", &date))
        return GNUNET_SYSERR;

    /* turns out that the day is off by one in the last two cases */
    date.tm_mday += 1;
  }

  seconds = mktime (&date);
  if (-1 == seconds)
    return GNUNET_SYSERR;

  /* calculate the limit date for the largest age group */
  localtime_r (&(time_t){time (NULL)}, &limit);
  limit.tm_year -= TALER_adult_age (mask);
  GNUNET_assert (-1 != mktime (&limit));

  if ((limit.tm_year < date.tm_year)
      || ((limit.tm_year == date.tm_year)
          && (limit.tm_mon < date.tm_mon))
      || ((limit.tm_year == date.tm_year)
          && (limit.tm_mon == date.tm_mon)
          && (limit.tm_mday < date.tm_mday)))
    *out = seconds / 60 / 60 / 24;
  else
    *out = 0;

  return GNUNET_OK;
}


/* end util/age_restriction.c */
