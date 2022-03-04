/*
  This file is part of TALER
  (C) 2022 Taler Systems SA

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
 * @file util/test_age_restriction.c
 * @brief Tests for age restriction specific logic
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_crypto_lib.h"

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


enum GNUNET_GenericReturnValue
test_groups (void)
{
  struct
  {
    uint32_t bits;
    uint8_t group[33];
  } test[] = {
    {
      .bits =
        1 | 1 << 5 | 1 << 13 | 1 << 23,

        .group = { 0, 0, 0, 0, 0,
                   1, 1, 1, 1, 1, 1, 1, 1,
                   2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
                   3, 3, 3, 3, 3, 3, 3, 3, 3, 3 }


    },
    {
      .bits =
        1 | 1 << 8 | 1 << 10 | 1 << 12 | 1 << 14 | 1 << 16 | 1 << 18 | 1 << 21,
        .group = { 0, 0, 0, 0, 0, 0, 0, 0,
                   1, 1,
                   2, 2,
                   3, 3,
                   4, 4,
                   5, 5,
                   6, 6, 6,
                   7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7}


    }
  };

  for (uint8_t t = 0; t < sizeof(test) / sizeof(test[0]); t++)
  {
    struct TALER_AgeMask mask = {.bits = test[t].bits};

    for (uint8_t i = 0; i < 32; i++)
    {
      uint8_t r = get_age_group (&mask, i);
      char *m = age_mask_to_string (&mask);

      printf ("get_age_group(%s, %2d) = %d vs %d (exp)\n",
              m,
              i,
              r,
              test[t].group[i]);

      if (test[t].group[i] != r)
        return GNUNET_SYSERR;

      GNUNET_free (m);
    }
  }

  return GNUNET_OK;
}


static struct TALER_AgeMask age_mask = {
  .bits = 1 | 1 << 8 | 1 << 10 | 1 << 12 | 1 << 14 | 1 << 16 | 1 << 18 | 1 << 21
};

enum GNUNET_GenericReturnValue
test_attestation (void)
{
  uint8_t age;
  for (age = 0; age < 33; age++)
  {
    enum GNUNET_GenericReturnValue ret;
    struct TALER_AgeCommitmentProof acp[3] = {0};
    struct TALER_AgeAttestation at = {0};
    uint8_t age_group = get_age_group (&age_mask, age);
    uint64_t salt = GNUNET_CRYPTO_random_u64 (GNUNET_CRYPTO_QUALITY_WEAK,
                                              UINT64_MAX);

    ret = TALER_age_restriction_commit (&age_mask,
                                        age,
                                        salt,
                                        &acp[0]);

    printf (
      "commit(age:%d) == %d; proof.num: %ld; age_group: %d\n",
      age,
      ret,
      acp[0].proof.num,
      age_group);

    /* Also derive two more commitments right away */
    for (uint8_t i = 0; i<2; i++)
    {
      salt = GNUNET_CRYPTO_random_u64 (GNUNET_CRYPTO_QUALITY_WEAK,
                                       UINT64_MAX);
      GNUNET_assert (GNUNET_OK ==
                     TALER_age_commitment_derive (&acp[i],
                                                  salt,
                                                  &acp[i + 1]));
    }

    for (uint8_t i = 0; i < 3; i++)
    {
      for (uint8_t min = 0; min < 22; min++)
      {
        uint8_t min_group = get_age_group (&age_mask, min);

        ret = TALER_age_commitment_attest (&acp[i],
                                           min,
                                           &at);

        printf (
          "[%s]: attest(min:%d, age:%d) == %d; age_group: %d, min_group: %d\n",
          i == 0 ? "commit" : "derive",
          min,
          age,
          ret,
          age_group,
          min_group);

        if (min_group <= age_group &&
            GNUNET_OK != ret)
          return GNUNET_SYSERR;

        if (min_group > age_group &&
            GNUNET_NO != ret)
          return GNUNET_SYSERR;

        if (min_group > age_group)
          continue;

        ret = TALER_age_commitment_verify (&acp[i].commitment,
                                           min,
                                           &at);

        printf (
          "[%s]: verify(min:%d, age:%d) == %d; age_group:%d, min_group: %d\n",
          i == 0 ? "commit" : "derive",
          min,
          age,
          ret,
          age_group,
          min_group);

        if (GNUNET_OK != ret)
          return ret;
      }
    }
  }
  return GNUNET_OK;
}


int
main (int argc,
      const char *const argv[])
{
  (void) argc;
  (void) argv;
  if (GNUNET_OK != test_groups ())
    return 1;
  if (GNUNET_OK != test_attestation ())
    return 2;
  return 0;
}


/* end of test_age_restriction.c */
