/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2020 Taler Systems SA

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
 * @file include/taler_amount_lib.h
 * @brief amount-representation utility functions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#if ! defined (__TALER_UTIL_LIB_H_INSIDE__)
#error "Only <taler_util.h> can be included directly."
#endif

#ifndef TALER_AMOUNT_LIB_H
#define TALER_AMOUNT_LIB_H

#include <stdint.h>
#include "gnunet/gnunet_common.h"

#ifdef __cplusplus
extern "C"
{
#if 0                           /* keep Emacsens' auto-indent happy */
}
#endif
#endif


/**
 * @brief Number of characters (plus 1 for 0-termination) we use to
 * represent currency names (i.e. EUR, USD, etc.).  We use 8+4 for
 * alignment in the `struct TALER_Amount`.  The amount is typically an
 * ISO 4217 currency code when an alphanumeric 3-digit code is used.
 * For regional currencies, the first character should be a "*" followed
 * by a region-specific name (i.e. "*BRETAGNEFR").
 */
#define TALER_CURRENCY_LEN 12

/**
 * Taler currency length as a string.
 */
#define TALER_CURRENCY_LEN_STR "12"

/**
 * @brief The "fraction" value in a `struct TALER_Amount` represents which
 * fraction of the "main" value?
 *
 * Note that we need sub-cent precision here as transaction fees might
 * be that low, and as we want to support microdonations.
 *
 * An actual `struct Amount a` thus represents
 * "a.value + (a.fraction / #TALER_AMOUNT_FRAC_BASE)" units of "a.currency".
 */
#define TALER_AMOUNT_FRAC_BASE 100000000

/**
 * @brief How many digits behind the comma are required to represent the
 * fractional value in human readable decimal format?  Must match
 * lg(#TALER_AMOUNT_FRAC_BASE).
 */
#define TALER_AMOUNT_FRAC_LEN 8

/**
 * Maximum legal 'value' for an amount, based on IEEE double (for JavaScript compatibility).
 */
#define TALER_AMOUNT_MAX_VALUE (1LLU << 52)


GNUNET_NETWORK_STRUCT_BEGIN


/**
 * @brief Amount, encoded for network transmission.
 */
struct TALER_AmountNBO
{
  /**
   * Value in the main currency, in NBO.
   */
  uint64_t value GNUNET_PACKED;

  /**
   * Fraction (integer multiples of #TALER_AMOUNT_FRAC_BASE), in NBO.
   */
  uint32_t fraction GNUNET_PACKED;

  /**
   * Type of the currency being represented.
   */
  char currency[TALER_CURRENCY_LEN];
};

GNUNET_NETWORK_STRUCT_END


/**
 * @brief Representation of monetary value in a given currency.
 */
struct TALER_Amount
{
  /**
   * Value (numerator of fraction)
   */
  uint64_t value;

  /**
   * Fraction (integer multiples of #TALER_AMOUNT_FRAC_BASE).
   */
  uint32_t fraction;

  /**
   * Currency string, left adjusted and padded with zeros.  All zeros
   * for "invalid" values.
   */
  char currency[TALER_CURRENCY_LEN];
};


/**
 * Check that the currency code in @a str is well-formed.
 *
 * @param str currency code name to validate
 * @return #GNUNET_OK if @a str is a valid currency code
 */
enum GNUNET_GenericReturnValue
TALER_check_currency (const char *str);


/**
 * Parse monetary amount, in the format "T:V.F".
 *
 * @param str amount string
 * @param[out] amount amount to write the result to
 * @return #GNUNET_OK if the string is a valid monetary amount specification,
 *         #GNUNET_SYSERR if it is invalid.
 */
enum GNUNET_GenericReturnValue
TALER_string_to_amount (const char *str,
                        struct TALER_Amount *amount);


/**
 * Parse monetary amount, in the format "T:V.F".
 * The result is stored in network byte order (NBO).
 *
 * @param str amount string
 * @param[out] amount_nbo amount to write the result to
 * @return #GNUNET_OK if the string is a valid amount specification,
 *         #GNUNET_SYSERR if it is invalid.
 */
enum GNUNET_GenericReturnValue
TALER_string_to_amount_nbo (const char *str,
                            struct TALER_AmountNBO *amount_nbo);


/**
 * Get the value of "zero" in a particular currency.
 *
 * @param cur currency description
 * @param[out] amount amount to write the result to
 * @return #GNUNET_OK if @a cur is a valid currency specification,
 *         #GNUNET_SYSERR if it is invalid.
 */
enum GNUNET_GenericReturnValue
TALER_amount_set_zero (const char *cur,
                       struct TALER_Amount *amount);


/**
 * Test if the given @a amount is zero.
 *
 * @param amount amount to compare to zero
 * @return true if the amount is zero,
 *         false if it is non-zero or invalid
 */
bool
TALER_amount_is_zero (const struct TALER_Amount *amount);


/**
 * Test if the given amount is valid.
 *
 * @param amount amount to check
 * @return #GNUNET_OK if @a amount is valid
 */
enum GNUNET_GenericReturnValue
TALER_amount_is_valid (const struct TALER_Amount *amount);


/**
 * Test if the given amount is in the given currency
 *
 * @param amount amount to check
 * @param currency currency to check for
 * @return #GNUNET_OK if @a amount is in @a currency
 */
enum GNUNET_GenericReturnValue
TALER_amount_is_currency (const struct TALER_Amount *amount,
                          const char *currency);


/**
 * Convert amount from host to network representation.
 *
 * @param[out] res where to store amount in network representation
 * @param d amount in host representation
 */
void
TALER_amount_hton (struct TALER_AmountNBO *res,
                   const struct TALER_Amount *d);


/**
 * Convert amount from network to host representation.
 *
 * @param[out] res where to store amount in host representation
 * @param dn amount in network representation
 */
void
TALER_amount_ntoh (struct TALER_Amount *res,
                   const struct TALER_AmountNBO *dn);


/**
 * Compare the value/fraction of two amounts.  Does not compare the currency.
 * Comparing amounts of different currencies will cause the program to abort().
 * If unsure, check with #TALER_amount_cmp_currency() first to be sure that
 * the currencies of the two amounts are identical.
 *
 * @param a1 first amount
 * @param a2 second amount
 * @return result of the comparison
 *         -1 if `a1 < a2`
 *          1 if `a1 > a2`
 *          0 if `a1 == a2`.
 */
int
TALER_amount_cmp (const struct TALER_Amount *a1,
                  const struct TALER_Amount *a2);


/**
 * Compute maximum of two amounts.
 *
 * @param[out] ma set to maximum of @a a1 and @a a2
 * @param a1 first amount
 * @param a2 second amount
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_amount_max (struct TALER_Amount *ma,
                  const struct TALER_Amount *a1,
                  const struct TALER_Amount *a2);


/**
 * Compute minimum of two amounts.
 *
 * @param[out] mi set to minimum of @a a1 and @a a2
 * @param a1 first amount
 * @param a2 second amount
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_amount_min (struct TALER_Amount *mi,
                  const struct TALER_Amount *a1,
                  const struct TALER_Amount *a2);


/**
 * Compare the value/fraction of two amounts.  Does not compare the currency.
 * Comparing amounts of different currencies will cause the program to abort().
 * If unsure, check with #TALER_amount_cmp_currency() first to be sure that
 * the currencies of the two amounts are identical. NBO variant.
 *
 * @param a1 first amount
 * @param a2 second amount
 * @return result of the comparison
 *         -1 if `a1 < a2`
 *          1 if `a1 > a2`
 *          0 if `a1 == a2`.
 */
int
TALER_amount_cmp_nbo (const struct TALER_AmountNBO *a1,
                      const struct TALER_AmountNBO *a2);


/**
 * Test if @a a1 and @a a2 are the same currency.
 *
 * @param a1 amount to test
 * @param a2 amount to test
 * @return #GNUNET_YES if @a a1 and @a a2 are the same currency
 *         #GNUNET_NO if the currencies are different
 *         #GNUNET_SYSERR if either amount is invalid
 */
enum GNUNET_GenericReturnValue
TALER_amount_cmp_currency (const struct TALER_Amount *a1,
                           const struct TALER_Amount *a2);


/**
 * Test if @a a1 and @a a2 are the same currency, NBO variant.
 *
 * @param a1 amount to test
 * @param a2 amount to test
 * @return #GNUNET_YES if @a a1 and @a a2 are the same currency
 *         #GNUNET_NO if the currencies are different
 *         #GNUNET_SYSERR if either amount is invalid
 */
enum GNUNET_GenericReturnValue
TALER_amount_cmp_currency_nbo (const struct TALER_AmountNBO *a1,
                               const struct TALER_AmountNBO *a2);


/**
 * Possible results from calling #TALER_amount_subtract() and
 * possibly other arithmetic operations. Negative values
 * indicate that the operation did not generate a result.
 */
enum TALER_AmountArithmeticResult
{

  /**
   * Operation succeeded, result is positive.
   */
  TALER_AAR_RESULT_POSITIVE = 1,

  /**
   * Operation succeeded, result is exactly zero.
   */
  TALER_AAR_RESULT_ZERO = 0,

  /**
   * Operation failed, the result would have been negative.
   */
  TALER_AAR_INVALID_NEGATIVE_RESULT = -1,

  /**
   * Operation failed, result outside of the representable range.
   */
  TALER_AAR_INVALID_RESULT_OVERFLOW = -2,

  /**
   * Operation failed, inputs could not be normalized.
   */
  TALER_AAR_INVALID_NORMALIZATION_FAILED = -3,

  /**
   * Operation failed, input currencies were not identical.
   */
  TALER_AAR_INVALID_CURRENCIES_INCOMPATIBLE = -4

};

/**
 * Perform saturating subtraction of amounts.
 *
 * @param[out] diff where to store (@a a1 - @a a2), or invalid if @a a2 > @a a1
 * @param a1 amount to subtract from
 * @param a2 amount to subtract
 * @return operation status, negative on failures
 */
enum TALER_AmountArithmeticResult
TALER_amount_subtract (struct TALER_Amount *diff,
                       const struct TALER_Amount *a1,
                       const struct TALER_Amount *a2);


/**
 * Perform addition of amounts.
 *
 * @param[out] sum where to store @a a1 + @a a2, set to "invalid" on overflow
 * @param a1 first amount to add
 * @param a2 second amount to add
 * @return operation status, negative on failures
 */
enum TALER_AmountArithmeticResult
TALER_amount_add (struct TALER_Amount *sum,
                  const struct TALER_Amount *a1,
                  const struct TALER_Amount *a2);


/**
 * Divide an amount by a @ divisor.  Note that this function
 * may introduce a rounding error!
 *
 * @param[out] result where to store @a dividend / @a divisor
 * @param dividend amount to divide
 * @param divisor by what to divide, must be positive
 */
void
TALER_amount_divide (struct TALER_Amount *result,
                     const struct TALER_Amount *dividend,
                     uint32_t divisor);

/**
 * Divide one amount by another.  Note that this function
 * may introduce a rounding error. It rounds down.
 *
 * @param dividend amount to divide
 * @param divisor by what to divide, must be positive
 * @return @a dividend / @a divisor, rounded down. -1 on currency mismatch,
 *         INT_MAX for division by zero
 */
int
TALER_amount_divide2 (const struct TALER_Amount *dividend,
                      const struct TALER_Amount *divisor);


/**
 * Multiply an @a amount by a @ factor.
 *
 * @param[out] result where to store @a amount * @a factor
 * @param amount amount to multiply
 * @param factor factor by which to multiply
 */
enum TALER_AmountArithmeticResult
TALER_amount_multiply (struct TALER_Amount *result,
                       const struct TALER_Amount *amount,
                       uint32_t factor);


/**
 * Normalize the given amount.
 *
 * @param[in,out] amount amount to normalize
 * @return #GNUNET_OK if normalization worked
 *         #GNUNET_NO if value was already normalized
 *         #GNUNET_SYSERR if value was invalid or could not be normalized
 */
enum GNUNET_GenericReturnValue
TALER_amount_normalize (struct TALER_Amount *amount);


/**
 * Convert amount to string.
 *
 * @param amount amount to convert to string
 * @return freshly allocated string representation,
 *         NULL if the @a amount was invalid
 */
char *
TALER_amount_to_string (const struct TALER_Amount *amount);


/**
 * Convert amount to string.
 *
 * @param amount amount to convert to string
 * @return statically allocated buffer with string representation,
 *         NULL if the @a amount was invalid
 */
const char *
TALER_amount2s (const struct TALER_Amount *amount);


/**
 * Round the amount to something that can be transferred on the wire.
 * The rounding mode is specified via the smallest transferable unit,
 * which must only have a fractional part *or* only a value (either
 * of the two must be zero!).
 *
 * @param[in,out] amount amount to round down
 * @param[in] round_unit unit that should be rounded down to, and
 *            either value part or the faction must be zero (but not both)
 * @return #GNUNET_OK on success, #GNUNET_NO if rounding was unnecessary,
 *         #GNUNET_SYSERR if the amount or currency or @a round_unit was invalid
 */
enum GNUNET_GenericReturnValue
TALER_amount_round_down (struct TALER_Amount *amount,
                         const struct TALER_Amount *round_unit);


#if 0                           /* keep Emacsens' auto-indent happy */
{
#endif
#ifdef __cplusplus
}
#endif


#endif
