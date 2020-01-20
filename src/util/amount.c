/*
  This file is part of TALER
  Copyright (C) 2014 Taler Systems SA

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
 * Maximum legal 'value' for an amount, based on IEEE double (for JavaScript compatibility).
 */
#define MAX_AMOUNT_VALUE (1LLU << 52)


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


/**
 * Parse monetary amount, in the format "T:V.F".
 *
 * @param str amount string
 * @param[out] amount amount to write the result to
 * @return #GNUNET_OK if the string is a valid monetary amount specification,
 *         #GNUNET_SYSERR if it is invalid.
 */
int
TALER_string_to_amount (const char *str,
                        struct TALER_Amount *denom)
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
    invalidate (denom);
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
    invalidate (denom);
    return GNUNET_SYSERR;
  }

  GNUNET_assert (TALER_CURRENCY_LEN > (colon - str));
  memcpy (denom->currency,
          str,
          colon - str);
  /* 0-terminate *and* normalize buffer by setting everything to '\0' */
  memset (&denom->currency [colon - str],
          0,
          TALER_CURRENCY_LEN - (colon - str));

  /* skip colon */
  value = colon + 1;
  if ('\0' == value[0])
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Actual value missing in amount `%s'\n",
                str);
    invalidate (denom);
    return GNUNET_SYSERR;
  }

  denom->value = 0;
  denom->fraction = 0;

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
      invalidate (denom);
      return GNUNET_SYSERR;
    }
    n = *value - '0';
    if ( (denom->value * 10 + n < denom->value) ||
         (denom->value > MAX_AMOUNT_VALUE) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Value specified in amount `%s' is too large\n",
                  str);
      invalidate (denom);
      return GNUNET_SYSERR;
    }
    denom->value = (denom->value * 10) + n;
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
    invalidate (denom);
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
      invalidate (denom);
      return GNUNET_SYSERR;
    }
    if ( (*value < '0') ||
         (*value > '9') )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Error after dot\n");
      invalidate (denom);
      return GNUNET_SYSERR;
    }
    n = *value - '0';
    denom->fraction += n * b;
    b /= 10;
    value++;
  }
  return GNUNET_OK;
}


/**
 * Parse monetary amount, in the format "T:V.F".
 * The result is stored in network byte order (NBO).
 *
 * @param str amount string
 * @param[out] amount_nbo amount to write the result to
 * @return #GNUNET_OK if the string is a valid amount specification,
 *         #GNUNET_SYSERR if it is invalid.
 */
int
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


/**
 * Convert amount from host to network representation.
 *
 * @param res where to store amount in network representation
 * @param[out] d amount in host representation
 */
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


/**
 * Convert amount from network to host representation.
 *
 * @param[out] res where to store amount in host representation
 * @param dn amount in network representation
 */
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


/**
 * Get the value of "zero" in a particular currency.
 *
 * @param cur currency description
 * @param[out] amount amount to write the result to
 * @return #GNUNET_OK if @a cur is a valid currency specification,
 *         #GNUNET_SYSERR if it is invalid.
 */
int
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


/**
 * Test if the given amount is valid.
 *
 * @param amount amount to check
 * @return #GNUNET_OK if @a amount is valid
 */
int
TALER_amount_is_valid (const struct TALER_Amount *amount)
{
  return ('\0' != amount->currency[0]);
}


/**
 * Test if @a a is valid, NBO variant.
 *
 * @param a amount to test
 * @return #GNUNET_YES if valid,
 *         #GNUNET_NO if invalid
 */
static int
test_valid_nbo (const struct TALER_AmountNBO *a)
{
  return ('\0' != a->currency[0]);
}


/**
 * Test if @a a1 and @a a2 are the same currency.
 *
 * @param a1 amount to test
 * @param a2 amount to test
 * @return #GNUNET_YES if @a a1 and @a a2 are the same currency
 *         #GNUNET_NO if the currencies are different,
 *         #GNUNET_SYSERR if either amount is invalid
 */
int
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


/**
 * Test if @a a1 and @a a2 are the same currency, NBO variant.
 *
 * @param a1 amount to test
 * @param a2 amount to test
 * @return #GNUNET_YES if @a a1 and @a a2 are the same currency
 *         #GNUNET_NO if the currencies are different,
 *         #GNUNET_SYSERR if either amount is invalid
 */
int
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


/**
 * Compare the value/fraction of two amounts.  Does not compare the currency.
 * Comparing amounts of different currencies will cause the program to abort().
 * If unsure, check with #TALER_amount_cmp_currency() first to be sure that
 * the currencies of the two amounts are identical.
 *
 * @param a1 first amount
 * @param a2 second amount
 * @return result of the comparison,
 *         -1 if `a1 < a2`
 *          1 if `a1 > a2`
 *          0 if `a1 == a2`.
 */
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


/**
 * Perform saturating subtraction of amounts.
 *
 * @param[out] diff where to store (@a a1 - @a a2), or invalid if @a a2 > @a a1
 * @param a1 amount to subtract from
 * @param a2 amount to subtract
 * @return #GNUNET_OK if the subtraction worked,
 *         #GNUNET_NO if @a a1 = @a a2
 *         #GNUNET_SYSERR if @a a2 > @a a1 or currencies are incompatible;
 *                        @a diff is set to invalid
 */
int
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
    return GNUNET_SYSERR;
  }
  /* make local copies to avoid aliasing problems between
     diff and a1/a2 */
  n1 = *a1;
  n2 = *a2;
  if ( (GNUNET_SYSERR == TALER_amount_normalize (&n1)) ||
       (GNUNET_SYSERR == TALER_amount_normalize (&n2)) )
  {
    invalidate (diff);
    return GNUNET_SYSERR;
  }

  if (n1.fraction < n2.fraction)
  {
    if (0 == n1.value)
    {
      invalidate (diff);
      return GNUNET_SYSERR;
    }
    n1.fraction += TALER_AMOUNT_FRAC_BASE;
    n1.value--;
  }
  if (n1.value < n2.value)
  {
    invalidate (diff);
    return GNUNET_SYSERR;
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
    return GNUNET_NO;
  return GNUNET_OK;
}


/**
 * Perform addition of amounts.
 *
 * @param[out] sum where to store @a a1 + @a a2, set to "invalid" on overflow
 * @param a1 first amount to add
 * @param a2 second amount to add
 * @return #GNUNET_OK if the addition worked,
 *         #GNUNET_SYSERR on overflow
 */
int
TALER_amount_add (struct TALER_Amount *sum,
                  const struct TALER_Amount *a1,
                  const struct TALER_Amount *a2)
{
  struct TALER_Amount n1;
  struct TALER_Amount n2;
  struct TALER_Amount res;

  if (GNUNET_YES !=
      TALER_amount_cmp_currency (a1, a2))
  {
    invalidate (sum);
    return GNUNET_SYSERR;
  }
  /* make local copies to avoid aliasing problems between
     diff and a1/a2 */
  n1 = *a1;
  n2 = *a2;
  if ( (GNUNET_SYSERR == TALER_amount_normalize (&n1)) ||
       (GNUNET_SYSERR == TALER_amount_normalize (&n2)) )
  {
    invalidate (sum);
    return GNUNET_SYSERR;
  }

  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (a1->currency,
                                        &res));
  res.value = n1.value + n2.value;
  if (res.value < n1.value)
  {
    /* integer overflow */
    invalidate (sum);
    return GNUNET_SYSERR;
  }
  if (res.value > MAX_AMOUNT_VALUE)
  {
    /* too large to be legal */
    invalidate (sum);
    return GNUNET_SYSERR;
  }
  res.fraction = n1.fraction + n2.fraction;
  if (GNUNET_SYSERR ==
      TALER_amount_normalize (&res))
  {
    /* integer overflow via carry from fraction */
    invalidate (sum);
    return GNUNET_SYSERR;
  }
  *sum = res;
  return GNUNET_OK;
}


/**
 * Normalize the given amount.
 *
 * @param[in,out] amount amount to normalize
 * @return #GNUNET_OK if normalization worked
 *         #GNUNET_NO if value was already normalized
 *         #GNUNET_SYSERR if value was invalid or could not be normalized
 */
int
TALER_amount_normalize (struct TALER_Amount *amount)
{
  int ret;

  if (GNUNET_YES != TALER_amount_is_valid (amount))
    return GNUNET_SYSERR;
  ret = GNUNET_NO;
  while ( (amount->value != UINT64_MAX) &&
          (amount->fraction >= TALER_AMOUNT_FRAC_BASE) )
  {
    amount->fraction -= TALER_AMOUNT_FRAC_BASE;
    amount->value++;
    ret = GNUNET_OK;
  }
  if (amount->fraction >= TALER_AMOUNT_FRAC_BASE)
  {
    /* failed to normalize, adding up fractions caused
       main value to overflow! */
    invalidate (amount);
    return GNUNET_SYSERR;
  }
  return ret;
}


/**
 * Convert the fraction of @a amount to a string in decimals.
 *
 * @param amount value to convert
 * @param[out] tail where to write the reesult
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


/**
 * Convert amount to string.
 *
 * @param amount amount to convert to string
 * @return freshly allocated string representation
 */
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


/**
 * Convert amount to string.
 *
 * @param amount amount to convert to string
 * @return statically allocated buffer with string representation,
 *         NULL if the @a amount was invalid
 */
const char *
TALER_amount2s (const struct TALER_Amount *amount)
{
  /* 12 is sufficient for a uint32_t value in decimal; 3 is for ":.\0" */
  static char result[TALER_AMOUNT_FRAC_LEN + TALER_CURRENCY_LEN + 3 + 12];
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


/**
 * Divide an amount by a @a divisor.  Note that this function
 * may introduce a rounding error!
 *
 * @param[out] result where to store @a dividend / @a divisor
 * @param dividend amount to divide
 * @param divisor by what to divide, must be positive
 */
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


/**
 * Round the amount to something that can be transferred on the wire.
 * The rounding mode is specified via the smallest transferable unit,
 * which must only have a fractional part *or* only a value (either
 * of the two must be zero!).
 *
 * If the @a round_unit given is zero, we do nothing and return #GNUNET_NO.
 *
 * @param[in,out] amount amount to round down
 * @param[in] round_unit unit that should be rounded down to, and
 *            either value part or the faction must be zero
 * @return #GNUNET_OK on success, #GNUNET_NO if rounding was unnecessary,
 *         #GNUNET_SYSERR if the amount or currency or @a round_unit was invalid
 */
int
TALER_amount_round_down (struct TALER_Amount *amount,
                         const struct TALER_Amount *round_unit)
{
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
