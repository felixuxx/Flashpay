/*
  This file is part of TALER
  (C) 2015 Taler Systems SA

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
 * @file util/test_amount.c
 * @brief Tests for amount logic
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_amount_lib.h"


int
main (int argc,
      const char *const argv[])
{
  struct TALER_Amount a1;
  struct TALER_Amount a2;
  struct TALER_Amount a3;
  struct TALER_Amount r;
  char *c;

  GNUNET_log_setup ("test-amout",
                    "WARNING",
                    NULL);
  /* test invalid conversions */
  GNUNET_log_skip (6, GNUNET_NO);
  /* non-numeric */
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_string_to_amount ("EUR:4a",
                                         &a1));
  /* non-numeric */
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_string_to_amount ("EUR:4.4a",
                                         &a1));
  /* non-numeric */
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_string_to_amount ("EUR:4.a4",
                                         &a1));
  /* no currency */
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_string_to_amount (":4.a4",
                                         &a1));
  /* precision too high */
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_string_to_amount ("EUR:4.123456789",
                                         &a1));
  /* value too big */
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_string_to_amount (
                   "EUR:1234567890123456789012345678901234567890123456789012345678901234567890",
                   &a1));
  GNUNET_log_skip (0, GNUNET_YES);

  /* test conversion without fraction */
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:4",
                                         &a1));
  GNUNET_assert (0 == strcasecmp ("EUR",
                                  a1.currency));
  GNUNET_assert (4 == a1.value);
  GNUNET_assert (0 == a1.fraction);

  /* test conversion with leading zero in fraction */
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("eur:0.02",
                                         &a2));
  GNUNET_assert (0 == strcasecmp ("eur",
                                  a2.currency));
  GNUNET_assert (0 == a2.value);
  GNUNET_assert (TALER_AMOUNT_FRAC_BASE / 100 * 2 == a2.fraction);
  c = TALER_amount_to_string (&a2);
  GNUNET_assert (0 == strcmp ("eur:0.02",
                              c));
  GNUNET_free (c);

  /* test conversion with leading space and with fraction */
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (" eur:4.12",
                                         &a2));
  GNUNET_assert (0 == strcasecmp ("eur",
                                  a2.currency));
  GNUNET_assert (4 == a2.value);
  GNUNET_assert (TALER_AMOUNT_FRAC_BASE / 100 * 12 == a2.fraction);

  /* test use of local currency */
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (" *LOCAL:4444.1000",
                                         &a3));
  GNUNET_assert (0 == strcasecmp ("*LOCAL",
                                  a3.currency));
  GNUNET_assert (4444 == a3.value);
  GNUNET_assert (TALER_AMOUNT_FRAC_BASE / 10 == a3.fraction);

  /* test CMP with equal and unequal currencies */
  GNUNET_assert (GNUNET_NO ==
                 TALER_amount_cmp_currency (&a1,
                                            &a3));
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (&a1,
                                            &a2));

  /* test subtraction failure (currency missmatch) */
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_amount_subtract (&a3,
                                        &a3,
                                        &a2));
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_amount_normalize (&a3));

  /* test subtraction failure (negative result) */
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_amount_subtract (&a3,
                                        &a1,
                                        &a2));
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_amount_normalize (&a3));

  /* test subtraction success cases */
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_subtract (&a3,
                                        &a2,
                                        &a1));
  GNUNET_assert (GNUNET_NO ==
                 TALER_amount_subtract (&a3,
                                        &a1,
                                        &a1));
  GNUNET_assert (0 == a3.value);
  GNUNET_assert (0 == a3.fraction);
  GNUNET_assert (GNUNET_NO ==
                 TALER_amount_normalize (&a3));

  /* test addition success */
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_add (&a3,
                                   &a3,
                                   &a2));
  GNUNET_assert (GNUNET_NO ==
                 TALER_amount_normalize (&a3));

  /* test normalization */
  a3.fraction = 2 * TALER_AMOUNT_FRAC_BASE;
  a3.value = 4;
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_normalize (&a3));

  /* test conversion to string */
  c = TALER_amount_to_string (&a3);
  GNUNET_assert (0 == strcmp ("EUR:6",
                              c));
  GNUNET_free (c);

  /* test normalization with fraction overflow */
  a3.fraction = 2 * TALER_AMOUNT_FRAC_BASE + 1;
  a3.value = 4;
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_normalize (&a3));
  c = TALER_amount_to_string (&a3);
  GNUNET_assert (0 == strcmp ("EUR:6.00000001",
                              c));
  GNUNET_free (c);

  /* test normalization with overflow */
  a3.fraction = 2 * TALER_AMOUNT_FRAC_BASE + 1;
  a3.value = UINT64_MAX - 1;
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_amount_normalize (&a3));
  c = TALER_amount_to_string (&a3);
  GNUNET_assert (NULL == c);

  /* test addition with overflow */
  a1.fraction = TALER_AMOUNT_FRAC_BASE - 1;
  a1.value = UINT64_MAX - 5;
  a2.fraction = 2;
  a2.value = 5;
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_amount_add (&a3, &a1, &a2));

  /* test addition with underflow on fraction */
  a1.fraction = 1;
  a1.value = UINT64_MAX;
  a2.fraction = 2;
  a2.value = 0;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_subtract (&a3, &a1, &a2));
  GNUNET_assert (UINT64_MAX - 1 == a3.value);
  GNUNET_assert (TALER_AMOUNT_FRAC_BASE - 1 == a3.fraction);

  /* test division */
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:3.33",
                                         &a1));
  TALER_amount_divide (&a2,
                       &a1,
                       1);
  GNUNET_assert (0 == strcasecmp ("EUR",
                                  a2.currency));
  GNUNET_assert (3 == a2.value);
  GNUNET_assert (TALER_AMOUNT_FRAC_BASE / 100 * 33 == a2.fraction);

  TALER_amount_divide (&a2,
                       &a1,
                       3);
  GNUNET_assert (0 == strcasecmp ("EUR",
                                  a2.currency));
  GNUNET_assert (1 == a2.value);
  GNUNET_assert (TALER_AMOUNT_FRAC_BASE / 100 * 11 == a2.fraction);

  TALER_amount_divide (&a2,
                       &a1,
                       2);
  GNUNET_assert (0 == strcasecmp ("EUR",
                                  a2.currency));
  GNUNET_assert (1 == a2.value);
  GNUNET_assert (TALER_AMOUNT_FRAC_BASE / 1000 * 665 == a2.fraction);
  TALER_amount_divide (&a2,
                       &a1,
                       TALER_AMOUNT_FRAC_BASE * 2);
  GNUNET_assert (0 == strcasecmp ("EUR",
                                  a2.currency));
  GNUNET_assert (0 == a2.value);
  GNUNET_assert (1 == a2.fraction);

  /* test rounding #1 */

  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:0.01",
                                         &r));

  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:4.001",
                                         &a1));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:4",
                                         &a2));

  GNUNET_assert (GNUNET_OK == TALER_amount_round_down (&a1, &r));
  GNUNET_assert (GNUNET_NO == TALER_amount_round_down (&a1, &r));
  GNUNET_assert (0 == TALER_amount_cmp (&a1, &a2));

  /* test rounding #2 */

  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:0.001",
                                         &r));

  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:4.001",
                                         &a1));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:4.001",
                                         &a2));
  GNUNET_assert (GNUNET_NO == TALER_amount_round_down (&a1, &r));
  GNUNET_assert (0 == TALER_amount_cmp (&a1, &a2));

  return 0;
}


/* end of test_amount.c */
