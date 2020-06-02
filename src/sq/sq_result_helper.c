/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file sq/sq_result_helper.c
 * @brief functions to initialize parameter arrays
 * @author Jonathan Buchanan
 */
#include "platform.h"
#include <sqlite3.h>
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_sq_lib.h>
#include "taler_sq_lib.h"
#include "taler_amount_lib.h"


/**
 * Extract amount data from a SQLite database
 *
 * @param cls closure, a `const char *` giving the currency
 * @param result where to extract data from
 * @param column column to extract data from
 * @param[in,out] dst_size where to store size of result, may be NULL
 * @param[out] dst where to store the result
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_SYSERR if a result was invalid (non-existing field or NULL)
 */
static int
extract_amount_nbo (void *cls,
                    sqlite3_stmt *result,
                    unsigned int column,
                    size_t *dst_size,
                    void *dst)
{
  struct TALER_AmountNBO *amount = dst;
  const char *currency = cls;
  if ((sizeof (struct TALER_AmountNBO) != *dst_size) ||
      (SQLITE_INTEGER != sqlite3_column_type (result,
                                              (int) column)) ||
      (SQLITE_INTEGER != sqlite3_column_type (result,
                                              (int) column + 1)))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_strlcpy (amount->currency, currency, TALER_CURRENCY_LEN);
  amount->value = (uint64_t) sqlite3_column_int64 (result,
                                                   (int) column);
  uint64_t frac = (uint64_t) sqlite3_column_int64 (result,
                                                   column + 1);
  amount->fraction = (uint32_t) frac;
  return GNUNET_YES;
}


/**
 * Currency amount expected.
 *
 * @param currency the currency to use for @a amount
 * @param[out] amount where to store the result
 * @return array entry for the result specification to use
 */
struct GNUNET_SQ_ResultSpec
TALER_SQ_result_spec_amount_nbo (const char *currency,
                                 struct TALER_AmountNBO *amount)
{
  struct GNUNET_SQ_ResultSpec res = {
    .conv = &extract_amount_nbo,
    .cls = (void *) currency,
    .dst = (void *) amount,
    .dst_size = sizeof (struct TALER_AmountNBO),
    .num_params = 2
  };

  return res;
}


/* end of sq/sq_result_helper.c */
