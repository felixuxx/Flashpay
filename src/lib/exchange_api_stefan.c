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
 * @file lib/exchange_api_stefan.c
 * @brief calculations on the STEFAN curve
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include <math.h>


/**
 * Determine smallest denomination in @a keys.
 *
 * @param keys exchange response to evaluate
 * @return NULL on error (no denominations)
 */
static const struct TALER_Amount *
get_unit (const struct TALER_EXCHANGE_Keys *keys)
{
  const struct TALER_Amount *min = NULL;

  for (unsigned int i = 0; i<keys->num_denom_keys; i++)
  {
    const struct TALER_EXCHANGE_DenomPublicKey *dk
      = &keys->denom_keys[i];

    if ( (NULL == min) ||
         (1 == TALER_amount_cmp (min,
                                 /* > */
                                 &dk->value)) )
      min = &dk->value;
  }
  GNUNET_break (NULL != min);
  return min;
}


/**
 * Convert amount to double for STEFAN curve evaluation.
 *
 * @param a input amount
 * @return (rounded) amount as a double
 */
static double
amount_to_double (const struct TALER_Amount *a)
{
  double d = (double) a->value;

  d += a->fraction / ((double) TALER_AMOUNT_FRAC_BASE);
  return d;
}


/**
 * Convert double to amount for STEFAN curve evaluation.
 *
 * @param dv input amount
 * @param currency deisred currency
 * @param[out] rval (rounded) amount as a double
 */
static void
double_to_amount (double dv,
                  const char *currency,
                  struct TALER_Amount *rval)
{
  double rem;

  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (currency,
                                        rval));
  rval->value = floorl (dv);
  rem = dv - ((double) rval->value);
  if (rem < 0.0)
    rem = 0.0;
  rem *= TALER_AMOUNT_FRAC_BASE;
  rval->fraction = floorl (rem);
  if (rval->fraction >= TALER_AMOUNT_FRAC_BASE)
  {
    /* Strange, multiplication overflowed our range,
       round up value instead */
    rval->fraction = 0;
    rval->value += 1;
  }
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_keys_stefan_b2n (
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_Amount *brut,
  struct TALER_Amount *net)
{
  const struct TALER_Amount *min;
  double log_d = amount_to_double (&keys->stefan_log);
  double lin_d = keys->stefan_lin;
  double abs_d = amount_to_double (&keys->stefan_abs);
  double bru_d = amount_to_double (brut);
  double min_d;
  double fee_d;
  double net_d;

  if (TALER_amount_is_zero (brut))
  {
    *net = *brut;
    return GNUNET_NO;
  }
  min = get_unit (keys);
  if (NULL == min)
    return GNUNET_SYSERR;
  if (1.0f <= keys->stefan_lin)
  {
    /* This cannot work, linear STEFAN fee estimate always
       exceed any gross amount. */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  min_d = amount_to_double (min);
  fee_d = abs_d
          + log_d * log2 (bru_d / min_d)
          + lin_d * bru_d;
  if (fee_d > bru_d)
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (brut->currency,
                                          net));
    return GNUNET_NO;
  }
  net_d = bru_d - fee_d;
  double_to_amount (net_d,
                    brut->currency,
                    net);
  return GNUNET_OK;
}


/**
 * Our function
 * f(x) := ne + ab + lo * log2(x/mi) + li * x - x
 * for #newton().
 */
static double
eval_f (double mi,
        double ab,
        double lo,
        double li,
        double ne,
        double x)
{
  return ne + ab + lo * log2 (x / mi) + li * x - x;
}


/**
 * Our function
 * f'(x) := lo / log(2) / x + li - 1
 * for #newton().
 */
static double
eval_fp (double mi,
         double lo,
         double li,
         double ne,
         double x)
{
  return lo / log (2) / x + li - 1;
}


/**
 * Use Newton's method to find x where f(x)=0.
 *
 * @return x where "eval_f(x)==0".
 */
static double
newton (double mi,
        double ab,
        double lo,
        double li,
        double ne)
{
  const double eps = 0.00000001; /* max error allowed */
  double min_ab = ne + ab; /* result cannot be smaller than this! */
  /* compute lower bounds by various heuristics */
  double min_ab_li = min_ab + min_ab * li;
  double min_ab_li_lo = min_ab_li + log2 (min_ab_li / mi) * lo;
  double min_ab_lo = min_ab + log2 (min_ab / mi) * lo;
  double min_ab_lo_li = min_ab_lo + min_ab_lo * li;
  /* take global lower bound */
  double x_min = GNUNET_MAX (min_ab_lo_li,
                             min_ab_li_lo);
  double x = x_min; /* use lower bound as starting point */

  /* Objective: invert
     ne := br - ab - lo * log2 (br/mi) - li * br
     to find 'br'.
     Method: use Newton's method to find root of:
     f(x) := ne + ab + lo * log2 (x/mi) + li * x - x
     using also
     f'(x) := lo / log(2) / x  + li - 1
  */
  /* Loop to abort in case of divergence;
     100 is already very high, 2-4 is normal! */
  for (unsigned int i = 0; i<100; i++)
  {
    double fx = eval_f (mi, ab, lo, li, ne, x);
    double fxp = eval_fp (mi, lo, li, ne, x);
    double x_new = x - fx / fxp;

    if (fabs (x - x_new) <= eps)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Needed %u rounds from %f to result BRUT %f => NET: %f\n",
                  i,
                  x_min,
                  x_new,
                  x_new - ab - li * x_new - lo * log2 (x / mi));
      return x_new;
    }
    if (x_new < x_min)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Divergence, obtained very bad estimate %f after %u rounds!\n",
                  x_new,
                  i);
      return x_min;
    }
    x = x_new;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "Slow convergence, returning bad estimate %f!\n",
              x);
  return x;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_keys_stefan_n2b (
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_Amount *net,
  struct TALER_Amount *brut)
{
  const struct TALER_Amount *min;
  double lin_d = keys->stefan_lin;
  double log_d = amount_to_double (&keys->stefan_log);
  double abs_d = amount_to_double (&keys->stefan_abs);
  double net_d = amount_to_double (net);
  double min_d;
  double brut_d;

  if (TALER_amount_is_zero (net))
  {
    *brut = *net;
    return GNUNET_NO;
  }
  min = get_unit (keys);
  if (NULL == min)
    return GNUNET_SYSERR;
  if (1.0f <= keys->stefan_lin)
  {
    /* This cannot work, linear STEFAN fee estimate always
       exceed any gross amount. */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  min_d = amount_to_double (min);
  brut_d = newton (min_d,
                   abs_d,
                   log_d,
                   lin_d,
                   net_d);
  double_to_amount (brut_d,
                    net->currency,
                    brut);
  return GNUNET_OK;
}


void
TALER_EXCHANGE_keys_stefan_round (
  const struct TALER_EXCHANGE_Keys *keys,
  struct TALER_Amount *val)
{
  const struct TALER_Amount *min;
  uint32_t mod = 1;
  uint32_t frac;
  uint32_t rst;

  min = get_unit (keys);
  if (NULL == min)
    return;
  frac = min->fraction;
  while (0 != frac % 10)
  {
    mod *= 10;
    frac /= 10;
  }
  rst = val->fraction % mod;
  if (rst < mod / 2)
    val->fraction -= rst;
  else
    val->fraction += mod - rst;
}
