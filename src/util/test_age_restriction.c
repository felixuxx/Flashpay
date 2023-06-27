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
#include <gnunet/gnunet_common.h>

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
      uint8_t r = TALER_get_age_group (&mask, i);
      char *m = age_mask_to_string (&mask);

      printf ("TALER_get_age_group(%s, %2d) = %d vs %d (exp)\n",
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


enum GNUNET_GenericReturnValue
test_dates (void)
{
  struct TALER_AgeMask mask = {
    .bits = 1 | 1 << 5 | 1 << 9 | 1 << 13 | 1 << 17 | 1 << 21
  };

  struct
  {
    char *date;
    uint32_t expected;
    enum GNUNET_GenericReturnValue ret;
  }
  test [] = {
    {.date = "abcd-00-00", .expected = 0, .ret = GNUNET_SYSERR},
    {.date = "1900-00-01", .expected = 0, .ret = GNUNET_SYSERR},
    {.date = "19000001",   .expected = 0, .ret = GNUNET_SYSERR},
    {.date = "2001-33-05", .expected = 0, .ret = GNUNET_SYSERR},
    {.date = "2001-33-35", .expected = 0, .ret = GNUNET_SYSERR},

    {.date = "1900-00-00", .expected = 0, .ret = GNUNET_OK},
    {.date = "2001-00-00", .expected = 0, .ret = GNUNET_OK},
    {.date = "2001-03-00", .expected = 0, .ret = GNUNET_OK},
    {.date = "2001-03-05", .expected = 0, .ret = GNUNET_OK},

    /* These dates should be far enough for the near future so that
     * the expected values are correct. Will need adjustment in 2044 :) */
    {.date = "2023-06-26", .expected = 19533, .ret = GNUNET_OK },
    {.date = "2023-06-01", .expected = 19508, .ret = GNUNET_OK },
    {.date = "2023-06-00", .expected = 19508, .ret = GNUNET_OK },
    {.date = "2023-01-01", .expected = 19357, .ret = GNUNET_OK },
    {.date = "2023-00-00", .expected = 19357, .ret = GNUNET_OK },
  };

  for (uint8_t t = 0; t < sizeof(test) / sizeof(test[0]); t++)
  {
    uint32_t d;
    enum GNUNET_GenericReturnValue ret;

    ret = TALER_parse_coarse_date (test[t].date,
                                   &mask,
                                   &d);
    if (ret != test[t].ret)
    {
      printf (
        "dates[%d] for date `%s` expected parser to return: %d, got: %d\n",
        t, test[t].date, test[t].ret, ret);
      return GNUNET_SYSERR;
    }

    if (ret == GNUNET_SYSERR)
      continue;

    if (d != test[t].expected)
    {
      printf (
        "dates[%d] for date `%s` expected value %d, but got %d\n",
        t, test[t].date, test[t].expected, d);
      return GNUNET_SYSERR;
    }

    printf ("dates[%d] for date `%s` got expected value %d\n",
            t, test[t].date, d);
  }

  printf ("done with dates\n");

  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
test_lowest (void)
{
  struct TALER_AgeMask mask = {
    .bits = 1 | 1 << 5 | 1 << 9 | 1 << 13 | 1 << 17 | 1 << 21
  };

  struct { uint8_t age; uint8_t expected; }
  test [] = {
    {.age = 1, .expected = 0 },
    {.age = 2, .expected = 0 },
    {.age = 3, .expected = 0 },
    {.age = 4, .expected = 0 },
    {.age = 5, .expected = 5 },
    {.age = 6, .expected = 5 },
    {.age = 7, .expected = 5 },
    {.age = 8, .expected = 5 },
    {.age = 9, .expected = 9 },
    {.age = 10, .expected = 9 },
    {.age = 11, .expected = 9 },
    {.age = 12, .expected = 9 },
    {.age = 13, .expected = 13 },
    {.age = 14, .expected = 13 },
    {.age = 15, .expected = 13 },
    {.age = 16, .expected = 13 },
    {.age = 17, .expected = 17 },
    {.age = 18, .expected = 17 },
    {.age = 19, .expected = 17 },
    {.age = 20, .expected = 17 },
    {.age = 21, .expected = 21 },
    {.age = 22, .expected = 21 },
  };

  for (uint8_t n = 0; n < 21; n++)
  {
    uint8_t l = TALER_get_lowest_age (&mask, test[n].age);
    printf ("lowest[%d] for age %d, expected lowest: %d, got: %d\n",
            n, test[n].age, test[n].expected, l);
    if (test[n].expected != l)
      return GNUNET_SYSERR;
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
    uint8_t age_group = TALER_get_age_group (&age_mask, age);
    struct GNUNET_HashCode seed;


    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                &seed,
                                sizeof(seed));

    ret = TALER_age_restriction_commit (&age_mask,
                                        age,
                                        &seed,
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
      struct GNUNET_HashCode salt;
      GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                  &salt,
                                  sizeof (salt));
      GNUNET_assert (GNUNET_OK ==
                     TALER_age_commitment_derive (&acp[i],
                                                  &salt,
                                                  &acp[i + 1]));
    }

    for (uint8_t i = 0; i < 3; i++)
    {
      for (uint8_t min = 0; min < 22; min++)
      {
        uint8_t min_group = TALER_get_age_group (&age_mask, min);

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
        {
          GNUNET_break (0);
          ret = GNUNET_SYSERR;
        }

        if (min_group > age_group &&
            GNUNET_NO != ret)
        {
          GNUNET_break (0);
          ret = GNUNET_SYSERR;
        }

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
        {
          GNUNET_break (0);
          break;
        }
      }

      TALER_age_commitment_proof_free (&acp[i]);
    }

    if (GNUNET_SYSERR == ret)
    {
      GNUNET_break (0);
      return ret;
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
  GNUNET_log_setup ("test-age-restriction",
                    "INFO",
                    NULL);
  if (GNUNET_OK != test_groups ())
    return 1;
  if (GNUNET_OK != test_lowest ())
    return 2;
  if (GNUNET_OK != test_attestation ())
  {
    GNUNET_break (0);
    return 3;
  }
  if (GNUNET_OK != test_dates ())
    return 4;
  return 0;
}


/* end of test_age_restriction.c */
