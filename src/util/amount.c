/*
  This file is part of TALER
  Copyright (C) 2014 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file util/amount.c
 * @brief Common utility functions to deal with units of currency
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Florian Dold
 * @author Benedikt Mueller
 *
 * TODO:
 * - the way this library currently deals with underflow/overflow
 *   is insufficient; just going for UINT32_MAX on overflow
 *   will not do; similar issues for incompatible currencies;
 *   we need some more explicit logic to say 'bogus value',
 */
#include "platform.h"
#include "taler_util.h"
#include <gcrypt.h>

#define AMOUNT_FRAC_BASE 1000000

#define AMOUNT_FRAC_LEN 6


/**
 * Parse money amount description, in the format "A:B.C".
 *
 * @param str amount description
 * @param denom amount to write the result to
 * @return #GNUNET_OK if the string is a valid amount specification,
 *         #GNUNET_SYSERR if it is invalid.
 */
int
TALER_string_to_amount (const char *str,
                        struct TALER_Amount *denom)
{
  unsigned int i; // pos in str
  int n; // number tmp
  unsigned int c; // currency pos
  uint32_t b; // base for suffix

  memset (denom, 0, sizeof (struct TALER_Amount));

  i = n = c = 0;

  while (isspace(str[i]))
    i++;

  if (0 == str[i])
  {
    printf("null before currency\n");
    return GNUNET_SYSERR;
  }

  while (str[i] != ':')
  {
    if (0 == str[i])
    {
      printf("null before colon");
      return GNUNET_SYSERR;
    }
    if (c > 3)
    {
      printf("currency too long\n");
      return GNUNET_SYSERR;
    }
    denom->currency[c] = str[i];
    c++;
    i++;
  }

  // skip colon
  i++;

  if (0 == str[i])
  {
    printf("null before value\n");
    return GNUNET_SYSERR;
  }

  while (str[i] != '.')
  {
    if (0 == str[i])
    {
      return GNUNET_OK;
    }
    n = str[i] - '0';
    if (n < 0 || n > 9)
    {
      printf("invalid character '%c' before comma at %u\n", (char) n, i);
      return GNUNET_SYSERR;
    }
    denom->value = (denom->value * 10) + n;
    i++;
  }

  // skip the dot
  i++;

  if (0 == str[i])
  {
    printf("null after dot");
    return GNUNET_SYSERR;
  }

  b = 100000;

  while (0 != str[i])
  {
    n = str[i] - '0';
    if (b == 0 || n < 0 || n > 9)
    {
      printf("error after comma");
      return GNUNET_SYSERR;
    }
    denom->fraction += n * b;
    b /= 10;
    i++;
  }

  return GNUNET_OK;
}


/**
 * FIXME
 */
struct TALER_AmountNBO
TALER_amount_hton (const struct TALER_Amount d)
{
  struct TALER_AmountNBO dn;
  dn.value = htonl (d.value);
  dn.fraction = htonl (d.fraction);
  memcpy (dn.currency, d.currency, TALER_CURRENCY_LEN);

  return dn;
}


/**
 * FIXME
 */
struct TALER_Amount
TALER_amount_ntoh (const struct TALER_AmountNBO dn)
{
  struct TALER_Amount d;
  d.value = ntohl (dn.value);
  d.fraction = ntohl (dn.fraction);
  memcpy (d.currency, dn.currency, sizeof(dn.currency));

  return d;
}


/**
 * Compare the value/fraction of two amounts.  Does not compare the currency,
 * i.e. comparing amounts with the same value and fraction but different
 * currency would return 0.
 *
 * @param a1 first amount
 * @param a2 second amount
 * @return result of the comparison
 */
int
TALER_amount_cmp (struct TALER_Amount a1,
                  struct TALER_Amount a2)
{
  a1 = TALER_amount_normalize (a1);
  a2 = TALER_amount_normalize (a2);
  if (a1.value == a2.value)
  {
    if (a1.fraction < a2.fraction)
      return -1;
    if (a1.fraction > a2.fraction)
      return 1;
    return 0;
  }
  if (a1.value < a2.value)
    return -1;
  return 1;
}


/**
 * Perform saturating subtraction of amounts.
 *
 * @param a1 amount to subtract from
 * @param a2 amount to subtract
 * @return (a1-a2) or 0 if a2>=a1
 */
struct TALER_Amount
TALER_amount_subtract (struct TALER_Amount a1,
                       struct TALER_Amount a2)
{
  a1 = TALER_amount_normalize (a1);
  a2 = TALER_amount_normalize (a2);

  if (a1.value < a2.value)
  {
    a1.value = 0;
    a1.fraction = 0;
    return a1;
  }

  if (a1.fraction < a2.fraction)
  {
    if (0 == a1.value)
    {
      a1.fraction = 0;
      return a1;
    }
    a1.fraction += AMOUNT_FRAC_BASE;
    a1.value -= 1;
  }

  a1.fraction -= a2.fraction;
  a1.value -= a2.value;

  return a1;
}


/**
 * Perform saturating addition of amounts.
 *
 * @param a1 first amount to add
 * @param a2 second amount to add
 * @return sum of a1 and a2
 */
struct TALER_Amount
TALER_amount_add (struct TALER_Amount a1,
                  struct TALER_Amount a2)
{
  a1 = TALER_amount_normalize (a1);
  a2 = TALER_amount_normalize (a2);

  a1.value += a2.value;
  a1.fraction += a2.fraction;

  if (0 == a1.currency[0])
  {
    memcpy (a2.currency,
            a1.currency,
            TALER_CURRENCY_LEN);
  }

  if (0 == a2.currency[0])
  {
    memcpy (a1.currency,
            a2.currency,
            TALER_CURRENCY_LEN);
  }

  if ( (0 != a1.currency[0]) &&
       (0 != memcmp (a1.currency,
                     a2.currency,
                     TALER_CURRENCY_LEN)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "adding mismatching currencies\n");
  }

  if (a1.value < a2.value)
  {
    a1.value = UINT32_MAX;
    a2.value = UINT32_MAX;
    return a1;
  }

  return TALER_amount_normalize (a1);
}


/**
 * Normalize the given amount.
 *
 * @param amout amount to normalize
 * @return normalized amount
 */
struct TALER_Amount
TALER_amount_normalize (struct TALER_Amount amount)
{
  while (amount.value != UINT32_MAX && amount.fraction >= AMOUNT_FRAC_BASE)
  {
    amount.fraction -= AMOUNT_FRAC_BASE;
    amount.value += 1;
  }
  return amount;
}


/**
 * Convert amount to string.
 *
 * @param amount amount to convert to string
 * @return freshly allocated string representation
 */
char *
TALER_amount_to_string (struct TALER_Amount amount)
{
  char tail[AMOUNT_FRAC_LEN + 1] = { 0 };
  char curr[TALER_CURRENCY_LEN + 1] = { 0 };
  char *result = NULL;
  int len;

  memcpy (curr, amount.currency, TALER_CURRENCY_LEN);

  amount = TALER_amount_normalize (amount);
  if (0 != amount.fraction)
  {
    unsigned int i;
    uint32_t n = amount.fraction;
    for (i = 0; (i < AMOUNT_FRAC_LEN) && (n != 0); i++)
    {
      tail[i] = '0' + (n / (AMOUNT_FRAC_BASE / 10));
      n = (n * 10) % (AMOUNT_FRAC_BASE);
    }
    tail[i] = 0;
    len = GNUNET_asprintf (&result,
                           "%s:%lu.%s",
                           curr,
                           (unsigned long) amount.value,
                           tail);
  }
  else
  {
    len = GNUNET_asprintf (&result,
                           "%s:%lu",
                           curr,
                           (unsigned long) amount.value);
  }
  GNUNET_assert (len > 0);
  return result;
}


/* end of amount.c */
