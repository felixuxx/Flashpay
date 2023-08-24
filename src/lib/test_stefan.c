/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/test_stefan.c
 * @brief test calculations on the STEFAN curve
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"


/**
 * Check if @a a and @a b are numerically close.
 *
 * @param a an amount
 * @param b an amount
 * @return true if both values are quite close
 */
static bool
amount_close (const struct TALER_Amount *a,
              const struct TALER_Amount *b)
{
  struct TALER_Amount delta;

  switch (TALER_amount_cmp (a,
                            b))
  {
  case -1: /* a < b */
    GNUNET_assert (0 <
                   TALER_amount_subtract (&delta,
                                          b,
                                          a));
    break;
  case 0:
    /* perfect */
    return true;
  case 1: /* a > b */
    GNUNET_assert (0 <
                   TALER_amount_subtract (&delta,
                                          a,
                                          b));
    break;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Rounding error is %s\n",
              TALER_amount2s (&delta));
  if (delta.value > 0)
  {
    GNUNET_break (0);
    return false;
  }
  if (delta.fraction > 5000)
  {
    GNUNET_break (0);
    return false;
  }
  return true; /* let's consider this a rounding error */
}


int
main (int argc,
      char **argv)
{
  struct TALER_EXCHANGE_DenomPublicKey dk;
  struct TALER_EXCHANGE_Keys keys = {
    .denom_keys = &dk,
    .num_denom_keys = 1
  };
  struct TALER_Amount brut;
  struct TALER_Amount net;

  (void) argc;
  (void) argv;
  GNUNET_log_setup ("test-stefan",
                    "INFO",
                    NULL);
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("MAGIC:0.13",
                                         &dk.value));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("MAGIC:1",
                                         &keys.stefan_abs));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("MAGIC:0.13",
                                         &keys.stefan_log));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("MAGIC:0.15",
                                         &keys.stefan_lin));

  /* stefan_lin >= unit value, not allowed, test we fail */
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("MAGIC:4",
                                         &brut));
  GNUNET_log_skip (1,
                   GNUNET_NO);
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_EXCHANGE_keys_stefan_b2n (&keys,
                                                 &brut,
                                                 &net));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("MAGIC:4",
                                         &net));
  GNUNET_log_skip (1,
                   GNUNET_NO);
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_EXCHANGE_keys_stefan_n2b (&keys,
                                                 &net,
                                                 &brut));

  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("MAGIC:0.13",
                                         &keys.stefan_lin));

  /* stefan_lin == unit value, not allowed, test we fail */
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("MAGIC:4",
                                         &brut));
  GNUNET_log_skip (1,
                   GNUNET_NO);
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_EXCHANGE_keys_stefan_b2n (&keys,
                                                 &brut,
                                                 &net));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("MAGIC:4",
                                         &net));
  GNUNET_log_skip (1,
                   GNUNET_NO);
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_EXCHANGE_keys_stefan_n2b (&keys,
                                                 &net,
                                                 &brut));
  GNUNET_assert (0 == GNUNET_get_log_skip ());
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("MAGIC:0.1",
                                         &keys.stefan_lin));

  /* try various values for lin and log STEFAN values */
  for (unsigned int li = 1; li < 13; li += 1)
  {
    keys.stefan_lin.fraction = li * TALER_AMOUNT_FRAC_BASE / 100;

    for (unsigned int lx = 1; lx < 100; lx += 1)
    {
      keys.stefan_log.fraction = lx * TALER_AMOUNT_FRAC_BASE / 100;

      /* Check brutto-to-netto is stable */
      for (unsigned int i = 0; i<10; i++)
      {
        struct TALER_Amount rval;

        brut.value = i;
        brut.fraction = i * TALER_AMOUNT_FRAC_BASE / 10;
        GNUNET_assert (GNUNET_SYSERR !=
                       TALER_EXCHANGE_keys_stefan_b2n (&keys,
                                                       &brut,
                                                       &net));
        GNUNET_assert (GNUNET_SYSERR !=
                       TALER_EXCHANGE_keys_stefan_n2b (&keys,
                                                       &net,
                                                       &rval));
        if (TALER_amount_is_zero (&net))
          GNUNET_assert (TALER_amount_is_zero (&rval));
        else
        {
          GNUNET_assert (amount_close (&brut,
                                       &rval));
          TALER_EXCHANGE_keys_stefan_round (&keys,
                                            &rval);
          GNUNET_assert (amount_close (&brut,
                                       &rval));
        }
      }

      /* Check netto-to-brutto is stable */
      for (unsigned int i = 0; i<10; i++)
      {
        struct TALER_Amount rval;

        net.value = i;
        net.fraction = i * TALER_AMOUNT_FRAC_BASE / 10;
        GNUNET_assert (GNUNET_SYSERR !=
                       TALER_EXCHANGE_keys_stefan_n2b (&keys,
                                                       &net,
                                                       &brut));
        GNUNET_assert (GNUNET_SYSERR !=
                       TALER_EXCHANGE_keys_stefan_b2n (&keys,
                                                       &brut,
                                                       &rval));
        GNUNET_assert (amount_close (&net,
                                     &rval));
        TALER_EXCHANGE_keys_stefan_round (&keys,
                                          &rval);
        GNUNET_assert (amount_close (&net,
                                     &rval));
      }
    }
  }
  return 0;
}
