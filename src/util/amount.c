/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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
 * @file util/amount.c
 * @brief Common utility functions to deal with units of currency
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"


/**
 * Set @a a to "invalid".
 *
 * @param[out] a amount to set to invalid
 */
static void
invalidate (struct TALER_Amount *a)
{
  memset (a,
          0,
          sizeof (struct TALER_Amount));
}


enum GNUNET_GenericReturnValue
TALER_string_to_amount (const char *str,
                        struct TALER_Amount *amount)
{
  int n;
  uint32_t b;
  const char *colon;
  const char *value;

  /* skip leading whitespace */
  while (isspace ( (unsigned char) str[0]))
    str++;
  if ('\0' == str[0])
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Null before currency\n");
    invalidate (amount);
    return GNUNET_SYSERR;
  }

  /* parse currency */
  colon = strchr (str, (int) ':');
  if ( (NULL == colon) ||
       ((colon - str) >= TALER_CURRENCY_LEN) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Invalid currency specified before colon: `%s'\n",
                str);
    invalidate (amount);
    return GNUNET_SYSERR;
  }

  GNUNET_assert (TALER_CURRENCY_LEN > (colon - str));
  memcpy (amount->currency,
          str,
          colon - str);
  /* 0-terminate *and* normalize buffer by setting everything to '\0' */
  memset (&amount->currency [colon - str],
          0,
          TALER_CURRENCY_LEN - (colon - str));

  /* skip colon */
  value = colon + 1;
  if ('\0' == value[0])
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Actual value missing in amount `%s'\n",
                str);
    invalidate (amount);
    return GNUNET_SYSERR;
  }

  amount->value = 0;
  amount->fraction = 0;

  /* parse value */
  while ('.' != *value)
  {
    if ('\0' == *value)
    {
      /* we are done */
      return GNUNET_OK;
    }
    if ( (*value < '0') ||
         (*value > '9') )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Invalid character `%c' in amount `%s'\n",
                  (int) *value,
                  str);
      invalidate (amount);
      return GNUNET_SYSERR;
    }
    n = *value - '0';
    if ( (amount->value * 10 < amount->value) ||
         (amount->value * 10 + n < amount->value) ||
         (amount->value > TALER_AMOUNT_MAX_VALUE) ||
         (amount->value * 10 + n > TALER_AMOUNT_MAX_VALUE) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Value specified in amount `%s' is too large\n",
                  str);
      invalidate (amount);
      return GNUNET_SYSERR;
    }
    amount->value = (amount->value * 10) + n;
    value++;
  }

  /* skip the dot */
  value++;

  /* parse fraction */
  if ('\0' == *value)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Amount `%s' ends abruptly after `.'\n",
                str);
    invalidate (amount);
    return GNUNET_SYSERR;
  }
  b = TALER_AMOUNT_FRAC_BASE / 10;
  while ('\0' != *value)
  {
    if (0 == b)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Fractional value too small (only %u digits supported) in amount `%s'\n",
                  (unsigned int) TALER_AMOUNT_FRAC_LEN,
                  str);
      invalidate (amount);
      return GNUNET_SYSERR;
    }
    if ( (*value < '0') ||
         (*value > '9') )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Error after dot\n");
      invalidate (amount);
      return GNUNET_SYSERR;
    }
    n = *value - '0';
    amount->fraction += n * b;
    b /= 10;
    value++;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_string_to_amount_nbo (const char *str,
                            struct TALER_AmountNBO *amount_nbo)
{
  struct TALER_Amount amount;

  if (GNUNET_OK !=
      TALER_string_to_amount (str,
                              &amount))
    return GNUNET_SYSERR;
  TALER_amount_hton (amount_nbo,
                     &amount);
  return GNUNET_OK;
}


void
TALER_amount_hton (struct TALER_AmountNBO *res,
                   const struct TALER_Amount *d)
{
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_is_valid (d));
  res->value = GNUNET_htonll (d->value);
  res->fraction = htonl (d->fraction);
  memcpy (res->currency,
          d->currency,
          TALER_CURRENCY_LEN);
}


void
TALER_amount_ntoh (struct TALER_Amount *res,
                   const struct TALER_AmountNBO *dn)
{
  res->value = GNUNET_ntohll (dn->value);
  res->fraction = ntohl (dn->fraction);
  memcpy (res->currency,
          dn->currency,
          TALER_CURRENCY_LEN);
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_is_valid (res));
}


enum GNUNET_GenericReturnValue
TALER_amount_get_zero (const char *cur,
                       struct TALER_Amount *amount)
{
  size_t slen;

  slen = strlen (cur);
  if (slen >= TALER_CURRENCY_LEN)
    return GNUNET_SYSERR;
  memset (amount,
          0,
          sizeof (struct TALER_Amount));
  memcpy (amount->currency,
          cur,
          slen);
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_amount_is_valid (const struct TALER_Amount *amount)
{
  if (amount->value > TALER_AMOUNT_MAX_VALUE)
    return GNUNET_SYSERR;
  return ('\0' != amount->currency[0]) ? GNUNET_OK : GNUNET_NO;
}


/**
 * Test if @a a is valid, NBO variant.
 *
 * @param a amount to test
 * @return #GNUNET_YES if valid,
 *         #GNUNET_NO if invalid
 */
static enum GNUNET_GenericReturnValue
test_valid_nbo (const struct TALER_AmountNBO *a)
{
  return ('\0' != a->currency[0]) ? GNUNET_YES : GNUNET_NO;
}


enum GNUNET_GenericReturnValue
TALER_amount_cmp_currency (const struct TALER_Amount *a1,
                           const struct TALER_Amount *a2)
{
  if ( (GNUNET_NO == TALER_amount_is_valid (a1)) ||
       (GNUNET_NO == TALER_amount_is_valid (a2)) )
    return GNUNET_SYSERR;
  if (0 == strcasecmp (a1->currency,
                       a2->currency))
    return GNUNET_YES;
  return GNUNET_NO;
}


enum GNUNET_GenericReturnValue
TALER_amount_cmp_currency_nbo (const struct TALER_AmountNBO *a1,
                               const struct TALER_AmountNBO *a2)
{
  if ( (GNUNET_NO == test_valid_nbo (a1)) ||
       (GNUNET_NO == test_valid_nbo (a2)) )
    return GNUNET_SYSERR;
  if (0 == strcasecmp (a1->currency,
                       a2->currency))
    return GNUNET_YES;
  return GNUNET_NO;
}


int
TALER_amount_cmp (const struct TALER_Amount *a1,
                  const struct TALER_Amount *a2)
{
  struct TALER_Amount n1;
  struct TALER_Amount n2;

  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (a1,
                                            a2));
  n1 = *a1;
  n2 = *a2;
  GNUNET_assert (GNUNET_SYSERR !=
                 TALER_amount_normalize (&n1));
  GNUNET_assert (GNUNET_SYSERR !=
                 TALER_amount_normalize (&n2));
  if (n1.value == n2.value)
  {
    if (n1.fraction < n2.fraction)
      return -1;
    if (n1.fraction > n2.fraction)
      return 1;
    return 0;
  }
  if (n1.value < n2.value)
    return -1;
  return 1;
}


int
TALER_amount_cmp_nbo (const struct TALER_AmountNBO *a1,
                      const struct TALER_AmountNBO *a2)
{
  struct TALER_Amount h1;
  struct TALER_Amount h2;

  TALER_amount_ntoh (&h1,
                     a1);
  TALER_amount_ntoh (&h2,
                     a2);
  return TALER_amount_cmp (&h1,
                           &h2);
}


enum TALER_AmountArithmeticResult
TALER_amount_subtract (struct TALER_Amount *diff,
                       const struct TALER_Amount *a1,
                       const struct TALER_Amount *a2)
{
  struct TALER_Amount n1;
  struct TALER_Amount n2;

  if (GNUNET_YES !=
      TALER_amount_cmp_currency (a1,
                                 a2))
  {
    invalidate (diff);
    return TALER_AAR_INVALID_CURRENCIES_INCOMPATIBLE;
  }
  /* make local copies to avoid aliasing problems between
     diff and a1/a2 */
  n1 = *a1;
  n2 = *a2;
  if ( (GNUNET_SYSERR == TALER_amount_normalize (&n1)) ||
       (GNUNET_SYSERR == TALER_amount_normalize (&n2)) )
  {
    invalidate (diff);
    return TALER_AAR_INVALID_NORMALIZATION_FAILED;
  }

  if (n1.fraction < n2.fraction)
  {
    if (0 == n1.value)
    {
      invalidate (diff);
      return TALER_AAR_INVALID_NEGATIVE_RESULT;
    }
    n1.fraction += TALER_AMOUNT_FRAC_BASE;
    n1.value--;
  }
  if (n1.value < n2.value)
  {
    invalidate (diff);
    return TALER_AAR_INVALID_NEGATIVE_RESULT;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (n1.currency,
                                        diff));
  GNUNET_assert (n1.fraction >= n2.fraction);
  diff->fraction = n1.fraction - n2.fraction;
  GNUNET_assert (n1.value >= n2.value);
  diff->value = n1.value - n2.value;
  if ( (0 == diff->fraction) &&
       (0 == diff->value) )
    return TALER_AAR_RESULT_ZERO;
  return TALER_AAR_RESULT_POSITIVE;
}


enum TALER_AmountArithmeticResult
TALER_amount_add (struct TALER_Amount *sum,
                  const struct TALER_Amount *a1,
                  const struct TALER_Amount *a2)
{
  struct TALER_Amount n1;
  struct TALER_Amount n2;
  struct TALER_Amount res;

  if (GNUNET_YES !=
      TALER_amount_cmp_currency (a1,
                                 a2))
  {
    invalidate (sum);
    return TALER_AAR_INVALID_CURRENCIES_INCOMPATIBLE;
  }
  /* make local copies to avoid aliasing problems between
     diff and a1/a2 */
  n1 = *a1;
  n2 = *a2;
  if ( (GNUNET_SYSERR ==
        TALER_amount_normalize (&n1)) ||
       (GNUNET_SYSERR ==
        TALER_amount_normalize (&n2)) )
  {
    invalidate (sum);
    return TALER_AAR_INVALID_NORMALIZATION_FAILED;
  }

  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (a1->currency,
                                        &res));
  res.value = n1.value + n2.value;
  if (res.value < n1.value)
  {
    /* integer overflow */
    invalidate (sum);
    return TALER_AAR_INVALID_RESULT_OVERFLOW;
  }
  if (res.value > TALER_AMOUNT_MAX_VALUE)
  {
    /* too large to be legal */
    invalidate (sum);
    return TALER_AAR_INVALID_RESULT_OVERFLOW;
  }
  res.fraction = n1.fraction + n2.fraction;
  if (GNUNET_SYSERR ==
      TALER_amount_normalize (&res))
  {
    /* integer overflow via carry from fraction */
    invalidate (sum);
    return TALER_AAR_INVALID_RESULT_OVERFLOW;
  }
  *sum = res;
  if ( (0 == sum->fraction) &&
       (0 == sum->value) )
    return TALER_AAR_RESULT_ZERO;
  return TALER_AAR_RESULT_POSITIVE;
}


enum GNUNET_GenericReturnValue
TALER_amount_normalize (struct TALER_Amount *amount)
{
  uint32_t overflow;

  if (GNUNET_YES != TALER_amount_is_valid (amount))
    return GNUNET_SYSERR;
  if (amount->fraction < TALER_AMOUNT_FRAC_BASE)
    return GNUNET_NO;
  overflow = amount->fraction / TALER_AMOUNT_FRAC_BASE;
  amount->fraction %= TALER_AMOUNT_FRAC_BASE;
  amount->value += overflow;
  if ( (amount->value < overflow) ||
       (amount->value > TALER_AMOUNT_MAX_VALUE) )
  {
    invalidate (amount);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Convert the fraction of @a amount to a string in decimals.
 *
 * @param amount value to convert
 * @param[out] tail where to write the result
 */
static void
amount_to_tail (const struct TALER_Amount *amount,
                char tail[TALER_AMOUNT_FRAC_LEN + 1])
{
  uint32_t n = amount->fraction;
  unsigned int i;

  for (i = 0; (i < TALER_AMOUNT_FRAC_LEN) && (0 != n); i++)
  {
    tail[i] = '0' + (n / (TALER_AMOUNT_FRAC_BASE / 10));
    n = (n * 10) % (TALER_AMOUNT_FRAC_BASE);
  }
  tail[i] = '\0';
}


char *
TALER_amount_to_string (const struct TALER_Amount *amount)
{
  char *result;
  struct TALER_Amount norm;

  if (GNUNET_YES != TALER_amount_is_valid (amount))
    return NULL;
  norm = *amount;
  GNUNET_break (GNUNET_SYSERR !=
                TALER_amount_normalize (&norm));
  if (0 != norm.fraction)
  {
    char tail[TALER_AMOUNT_FRAC_LEN + 1];

    amount_to_tail (&norm,
                    tail);
    GNUNET_asprintf (&result,
                     "%s:%llu.%s",
                     norm.currency,
                     (unsigned long long) norm.value,
                     tail);
  }
  else
  {
    GNUNET_asprintf (&result,
                     "%s:%llu",
                     norm.currency,
                     (unsigned long long) norm.value);
  }
  return result;
}


const char *
TALER_amount2s (const struct TALER_Amount *amount)
{
  /* 24 is sufficient for a uint64_t value in decimal; 3 is for ":.\0" */
  static GNUNET_THREAD_LOCAL char result[TALER_AMOUNT_FRAC_LEN
                                         + TALER_CURRENCY_LEN + 3 + 24];
  struct TALER_Amount norm;

  if (GNUNET_YES != TALER_amount_is_valid (amount))
    return NULL;
  norm = *amount;
  GNUNET_break (GNUNET_SYSERR !=
                TALER_amount_normalize (&norm));
  if (0 != norm.fraction)
  {
    char tail[TALER_AMOUNT_FRAC_LEN + 1];

    amount_to_tail (&norm,
                    tail);
    GNUNET_snprintf (result,
                     sizeof (result),
                     "%s:%llu.%s",
                     norm.currency,
                     (unsigned long long) norm.value,
                     tail);
  }
  else
  {
    GNUNET_snprintf (result,
                     sizeof (result),
                     "%s:%llu",
                     norm.currency,
                     (unsigned long long) norm.value);
  }
  return result;
}


void
TALER_amount_divide (struct TALER_Amount *result,
                     const struct TALER_Amount *dividend,
                     uint32_t divisor)
{
  uint64_t modr;

  GNUNET_assert (0 != divisor); /* division by zero is discouraged */
  *result = *dividend;
  /* in case @a dividend was not yet normalized */
  GNUNET_assert (GNUNET_SYSERR !=
                 TALER_amount_normalize (result));
  if (1 == divisor)
    return;
  modr = result->value % divisor;
  result->value /= divisor;
  /* modr fits into 32 bits, so we can safely multiply by (<32-bit) base and add fraction! */
  modr = (modr * TALER_AMOUNT_FRAC_BASE) + result->fraction;
  result->fraction = (uint32_t) (modr / divisor);
  /* 'fraction' could now be larger than #TALER_AMOUNT_FRAC_BASE, so we must normalize */
  GNUNET_assert (GNUNET_SYSERR !=
                 TALER_amount_normalize (result));
}


int
TALER_amount_divide2 (const struct TALER_Amount *dividend,
                      const struct TALER_Amount *divisor)
{
  double approx;
  double d;
  double r;
  int ret;
  struct TALER_Amount tmp;
  struct TALER_Amount nxt;

  if (GNUNET_YES !=
      TALER_amount_cmp_currency (dividend,
                                 divisor))
  {
    GNUNET_break (0);
    return -1;
  }
  if ( (0 == divisor->fraction) &&
       (0 == divisor->value) )
    return INT_MAX;
  /* first, get rounded approximation */
  d = ((double) dividend->value) * ((double) TALER_AMOUNT_FRAC_BASE)
      + ( (double) dividend->fraction);
  r = ((double) divisor->value) * ((double) TALER_AMOUNT_FRAC_BASE)
      + ( (double) divisor->fraction);
  approx = d / r;
  if (approx > ((double) INT_MAX))
    return INT_MAX; /* 'infinity' */
  /* round down */
  if (approx < 2)
    ret = 0;
  else
    ret = (int) approx - 2;
  /* Now do *exact* calculation, using well rounded-down factor as starting
     point to avoid having to do too many steps. */
  GNUNET_assert (0 <=
                 TALER_amount_multiply (&tmp,
                                        divisor,
                                        ret));
  /* in practice, this loop will only run for one or two iterations */
  while (1)
  {
    GNUNET_assert (0 <=
                   TALER_amount_add (&nxt,
                                     &tmp,
                                     divisor));
    if (1 ==
        TALER_amount_cmp (&nxt,
                          dividend))
      break; /* nxt > dividend */
    ret++;
    tmp = nxt;
  }
  return ret;
}


enum TALER_AmountArithmeticResult
TALER_amount_multiply (struct TALER_Amount *result,
                       const struct TALER_Amount *amount,
                       uint32_t factor)
{
  struct TALER_Amount in = *amount;

  if (GNUNET_SYSERR ==
      TALER_amount_normalize (&in))
    return TALER_AAR_INVALID_NORMALIZATION_FAILED;
  memcpy (result->currency,
          amount->currency,
          TALER_CURRENCY_LEN);
  if ( (0 == factor) ||
       ( (0 == in.value) &&
         (0 == in.fraction) ) )
  {
    result->value = 0;
    result->fraction = 0;
    return TALER_AAR_RESULT_ZERO;
  }
  result->value = in.value * ((uint64_t) factor);
  if (in.value != result->value / factor)
    return TALER_AAR_INVALID_RESULT_OVERFLOW;
  {
    /* This multiplication cannot overflow since both inputs are 32-bit values */
    uint64_t tmp = ((uint64_t) factor) * ((uint64_t) in.fraction);
    uint64_t res;

    res = tmp / TALER_AMOUNT_FRAC_BASE;
    /* check for overflow */
    if (result->value + res < result->value)
      return TALER_AAR_INVALID_RESULT_OVERFLOW;
    result->value += res;
    result->fraction = tmp % TALER_AMOUNT_FRAC_BASE;
  }
  if (result->value > TALER_AMOUNT_MAX_VALUE)
    return TALER_AAR_INVALID_RESULT_OVERFLOW;
  /* This check should be redundant... */
  GNUNET_assert (GNUNET_SYSERR !=
                 TALER_amount_normalize (result));
  return TALER_AAR_RESULT_POSITIVE;
}


enum GNUNET_GenericReturnValue
TALER_amount_round_down (struct TALER_Amount *amount,
                         const struct TALER_Amount *round_unit)
{
  if (GNUNET_OK !=
      TALER_amount_cmp_currency (amount,
                                 round_unit))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if ( (0 != round_unit->fraction) &&
       (0 != round_unit->value) )
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if ( (0 == round_unit->fraction) &&
       (0 == round_unit->value) )
    return GNUNET_NO; /* no rounding requested */
  if (0 != round_unit->fraction)
  {
    uint32_t delta;

    delta = amount->fraction % round_unit->fraction;
    if (0 == delta)
      return GNUNET_NO;
    amount->fraction -= delta;
  }
  if (0 != round_unit->value)
  {
    uint64_t delta;

    delta = amount->value % round_unit->value;
    if (0 == delta)
      return GNUNET_NO;
    amount->value -= delta;
    amount->fraction = 0;
  }
  return GNUNET_OK;
}


/* end of amount.c */
