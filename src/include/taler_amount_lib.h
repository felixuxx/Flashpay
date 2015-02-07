/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

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
 * @file include/taler_amount_lib.h
 * @brief amount-representation utility functions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#ifndef TALER_AMOUNT_LIB_H
#define TALER_AMOUNT_LIB_H


/**
 * Number of characters (plus 1 for 0-termination) we use to
 * represent currency names (i.e. EUR, USD, etc.).  We use
 * 8 for alignment (!).
 */
#define TALER_CURRENCY_LEN 8


GNUNET_NETWORK_STRUCT_BEGIN


/**
 * Amount, encoded for network transmission.
 */
struct TALER_AmountNBO
{
  /**
   * Value in the main currency, in NBO.
   */
  uint32_t value;

  /**
   * Additinal fractional value, in NBO.
   */
  uint32_t fraction;

  /**
   * Type of the currency being represented.
   */
  char currency[TALER_CURRENCY_LEN];
};

GNUNET_NETWORK_STRUCT_END


/**
 * Representation of monetary value in a given currency.
 */
struct TALER_Amount
{
  /**
   * Value (numerator of fraction)
   */
  uint32_t value;

  /**
   * Fraction (denominator of fraction)
   */
  uint32_t fraction;

  /**
   * Currency string, left adjusted and padded with zeros.
   */
  char currency[TALER_CURRENCY_LEN];
};


/**
 * Parse denomination description, in the format "T : V : F".
 *
 * @param str denomination description
 * @param denom denomination to write the result to
 * @return #GNUNET_OK if the string is a valid denomination specification,
 *         #GNUNET_SYSERR if it is invalid.
 */
int
TALER_string_to_amount (const char *str,
                        struct TALER_Amount *denom);


/**
 * Convert amount from host to network representation.
 *
 * @param d amount in host representation
 * @return amount in network representation
 */
struct TALER_AmountNBO
TALER_amount_hton (struct TALER_Amount d);


/**
 * Convert amount from network to host representation.
 *
 * @param d amount in network representation
 * @return amount in host representation
 */
struct TALER_Amount
TALER_amount_ntoh (struct TALER_AmountNBO dn);


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
                  struct TALER_Amount a2);


/**
 * Perform saturating subtraction of amounts.
 *
 * @param a1 amount to subtract from
 * @param a2 amount to subtract
 * @return (a1-a2) or 0 if a2>=a1
 */
struct TALER_Amount
TALER_amount_subtract (struct TALER_Amount a1,
                       struct TALER_Amount a2);


/**
 * Perform saturating addition of amounts
 *
 * @param a1 first amount to add
 * @param a2 second amount to add
 * @return sum of a1 and a2
 */
struct TALER_Amount
TALER_amount_add (struct TALER_Amount a1,
                  struct TALER_Amount a2);


/**
 * Normalize the given amount.
 *
 * @param amout amount to normalize
 * @return normalized amount
 */
struct TALER_Amount
TALER_amount_normalize (struct TALER_Amount amount);


/**
 * Convert amount to string.
 *
 * @param amount amount to convert to string
 * @return freshly allocated string representation
 */
char *
TALER_amount_to_string (struct TALER_Amount amount);


#endif
