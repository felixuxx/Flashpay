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
 * @file sq/sq_query_helper.c
 * @brief helper functions for Taler-specific SQLite3 interactions
 * @author Jonathan Buchanan
 */
#include "platform.h"
#include <sqlite3.h>
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_sq_lib.h>
#include "taler_sq_lib.h"


/**
 * Function called to convert input argument into SQL parameters.
 *
 * @param cls closure
 * @param data pointer to input argument, here a `struct TALER_AmountNBO`
 * @param data_len number of bytes in @a data (if applicable)
 * @param stmt sqlite statement to parameters for
 * @param off offset of the argument to bind in @a stmt, numbered from 1,
 *            so immediately suitable for passing to `sqlite3_bind`-functions.
 * @return #GNUNET_SYSERR on error, #GNUNET_OK on success
 */
static int
qconv_amount_nbo (void *cls,
                  const void *data,
                  size_t data_len,
                  sqlite3_stmt *stmt,
                  unsigned int off)
{
  const struct TALER_AmountNBO *amount = data;

  GNUNET_assert (sizeof (struct TALER_AmountNBO) == data_len);
  if (SQLITE_OK != sqlite3_bind_int64 (stmt,
                                       (int) off,
                                       (sqlite3_int64) amount->value))
    return GNUNET_SYSERR;
  if (SQLITE_OK != sqlite3_bind_int64 (stmt,
                                       (int) off + 1,
                                       (sqlite3_int64) amount->fraction))
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


/**
 * Generate query parameter for a currency, consisting of the three
 * components "value", "fraction" in this order. The
 * types must be a 64-bit integer and a 64-bit integer.
 *
 * @param x pointer to the query parameter to pass
 */
struct GNUNET_SQ_QueryParam
TALER_SQ_query_param_amount_nbo (const struct TALER_AmountNBO *x)
{
  struct GNUNET_SQ_QueryParam res =
  { &qconv_amount_nbo, NULL, x, sizeof (*x), 2 };
  return res;
}


/* end of sq/sq_query_helper.c */
