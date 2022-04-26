/**
 * @file util/tv_age_restriction.c
 * @brief Generate test vectors for age restriction
 * @author Özgür Kesim
 *
 * compile in exchange/src/util with
 *
 * gcc tv_age_restriction.c \
 *    -lgnunetutil -lgnunetjson -lsodium -ljansson \
 *    -L/usr/lib/x86_64-linux-gnu -lmicrohttpd -ltalerutil \
 *    -I../include \
 *    -o tv_age_restriction
 *
 */
#include "platform.h"
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <taler/taler_util.h>
#include <taler/taler_crypto_lib.h>

static struct TALER_AgeMask age_masks[] = {
  { .bits = 1
            | 1 << 8 | 1 << 14 | 1 << 18 },
  { .bits = 1
            | 1 << 8 | 1 << 10 | 1 << 12
            | 1 << 14 | 1 << 16 | 1 << 18 | 1 << 21 },
};

extern uint8_t
get_age_group (
  const struct TALER_AgeMask *mask,
  uint8_t age);

/**
 * Encodes the age mask into a string, like "8:10:12:14:16:18:21"
 *
 * @param mask Age mask
 * @return String representation of the age mask, allocated by GNUNET_malloc.
 *         Can be used as value in the TALER config.
 */
char *
age_mask_to_string (
  const struct TALER_AgeMask *m)
{
  uint32_t bits = m->bits;
  unsigned int n = 0;
  char *buf = GNUNET_malloc (32 * 3); // max characters possible
  char *pos = buf;

  if (NULL == buf)
  {
    return buf;
  }

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


static json_t *
cp_to_j (
  const struct GNUNET_HashCode *seed,
  struct TALER_AgeCommitmentProof *acp,
  uint8_t seq)
{
  json_t *j_commitment;
  json_t *j_proof;
  json_t *j_pubs;
  json_t *j_privs;
  struct TALER_AgeCommitmentHash hac = {0};
  char buf[256] = {0};

  TALER_age_commitment_hash (&acp->commitment, &hac);

  j_pubs = json_array ();
  GNUNET_assert (NULL != j_pubs);
  for (unsigned int i = 0; i < acp->commitment.num; i++)
  {
    json_t *j_pub = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_data_auto (NULL,
                                  &acp->commitment.keys[i]));
    json_array_append_new (j_pubs, j_pub);
  }

  j_commitment = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_uint64 ("num", acp->commitment.num),
    GNUNET_JSON_pack_array_steal ("edx25519_pubs", j_pubs),
    GNUNET_JSON_pack_data_auto ("h_age_commitment", &hac));


  j_privs = json_array ();
  GNUNET_assert (NULL != j_privs);
  for (unsigned int i = 0; i < acp->proof.num; i++)
  {
    json_t *j_priv = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_data_auto (NULL,
                                  &acp->proof.keys[i]));
    json_array_append_new (j_privs, j_priv);
  }
  j_proof = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_uint64 ("num", acp->proof.num),
    GNUNET_JSON_pack_array_steal ("edx25519_privs", j_privs));

  if (0 == seq)
  {
    strcpy (buf, "commit()");
  }
  else
  {
    sprintf (buf,
             "derive_from(%d)",
             seq);
  }

  return GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("generated_by", buf),
    GNUNET_JSON_pack_data_auto ("seed", seed),
    GNUNET_JSON_pack_object_steal ("proof", j_proof),
    GNUNET_JSON_pack_object_steal ("commitment", j_commitment));

};

static json_t *
generate (
  struct TALER_AgeMask *mask)
{
  uint8_t age;
  json_t *j_commitproofs;
  j_commitproofs = json_array ();

  for (age = 0; age < 24; age += 2)
  {
    json_t *j_top = json_object ();
    json_t *j_seq = json_array ();
    enum GNUNET_GenericReturnValue ret;
    struct TALER_AgeCommitmentProof acp[3] = {0};
    uint8_t age_group = get_age_group (mask, age);
    struct GNUNET_HashCode seed;

    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                &seed,
                                sizeof(seed));

    json_object_set (j_top,
                     "commited_age",
                     json_integer (age));

    ret = TALER_age_restriction_commit (mask,
                                        age,
                                        &seed,
                                        &acp[0]);

    GNUNET_assert (GNUNET_OK == ret);

    /* Also derive two more commitments right away */
    for (uint8_t i = 0; i<2; i++)
    {
      struct GNUNET_HashCode salt;
      GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                  &salt,
                                  sizeof (salt));
      uint64_t salt = GNUNET_CRYPTO_random_u64 (GNUNET_CRYPTO_QUALITY_WEAK,
                                                UINT64_MAX / 2);
      GNUNET_assert (GNUNET_OK ==
                     TALER_age_commitment_derive (&acp[i],
                                                  &salt,
                                                  &acp[i + 1]));
    }

    for (uint8_t i = 0; i < 3; i++)
    {
      json_t *j_cp = cp_to_j (&seed, &acp[i], i);
      json_t *j_attestations = json_array ();

      for (uint8_t min = 0; min < 22; min++)
      {
        json_t *j_attest = json_object ();
        json_t *j_reason;
        uint8_t min_group = get_age_group (mask, min);
        struct TALER_AgeAttestation at = {0};

        json_object_set (j_attest,
                         "required_minimum_age",
                         json_integer (min));
        json_object_set (j_attest,
                         "calculated_age_group",
                         json_integer (min_group));

        ret = TALER_age_commitment_attest (&acp[i],
                                           min,
                                           &at);


        if (0 == min_group)
          j_reason =  json_string (
            "not required: age group is 0");
        else if (min_group > age_group)
          j_reason = json_string (
            "not applicable: commited age too small");
        else
          j_reason = GNUNET_JSON_PACK (
            GNUNET_JSON_pack_data_auto (NULL, &at));

        json_object_set (j_attest,
                         "attestation",
                         j_reason);

        json_array_append_new (j_attestations,
                               j_attest);

      }

      json_object_set (j_cp, "attestations", j_attestations);
      json_array_append (j_seq,  j_cp);

      TALER_age_commitment_proof_free (&acp[i]);
    }

    json_object_set (j_top, "commitment_proof_attestation_seq", j_seq);
    json_array_append_new (j_commitproofs, j_top);
  }

  return j_commitproofs;
}


int
main (int argc,
      const char *const argv[])
{
  (void) argc;
  (void) argv;
  json_t *j_data = json_array ();
  for (unsigned int i = 0; i < 2; i++)
  {
    struct TALER_AgeMask mask = age_masks[i];
    json_t *j_test = json_object ();
    json_object_set (j_test,
                     "age_groups",
                     json_string (age_mask_to_string (&mask)));
    json_object_set (j_test,
                     "age_mask",
                     json_integer (mask.bits));
    json_object_set (j_test,
                     "test_data",
                     generate (&mask));
    json_array_append_new (j_data, j_test);
  }
  printf ("%s\n", json_dumps (j_data, JSON_INDENT (2)
                              | JSON_COMPACT));

  json_decref (j_data);
  return 0;
}


/* end of tv_age_restriction.c */
