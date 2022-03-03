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

static struct TALER_AgeMask age_mask = {
  .bits = 1 | 1 << 8 | 1 << 10 | 1 << 12 | 1 << 14 | 1 << 16 | 1 << 18 | 1 << 21
};

extern uint8_t
get_age_group (
  const struct TALER_AgeMask *mask,
  uint8_t age);

enum GNUNET_GenericReturnValue
test_attestation (void)
{
  uint8_t age;
  for (age = 0; age < 35; age++)
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

    for (uint8_t i = 0; i<2; i++)
    {
      /* Also derive another commitment right away */
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
  if (GNUNET_OK != test_attestation ())
    return 1;
  return 0;
}


/* end of test_age_restriction.c */
