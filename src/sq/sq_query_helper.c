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
 * @param data pointer to input argument, here a `struct TALER_Amount`
 * @param data_len number of bytes in @a data (if applicable)
 * @param stmt sqlite statement to parameters for
 * @param off offset of the argument to bind in @a stmt, numbered from 1,
 *            so immediately suitable for passing to `sqlite3_bind`-functions.
 * @return #GNUNET_SYSERR on error, #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
qconv_amount (void *cls,
              const void *data,
              size_t data_len,
              sqlite3_stmt *stmt,
              unsigned int off)
{
  const struct TALER_Amount *amount = data;

  (void) cls;
  GNUNET_assert (sizeof (struct TALER_Amount) == data_len);
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


struct GNUNET_SQ_QueryParam
TALER_SQ_query_param_amount (const struct TALER_Amount *x)
{
  struct GNUNET_SQ_QueryParam res = {
    .conv = &qconv_amount,
    .data = x,
    .size = sizeof (*x),
    .num_params = 2
  };

  return res;
}


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
static enum GNUNET_GenericReturnValue
qconv_amount_nbo (void *cls,
                  const void *data,
                  size_t data_len,
                  sqlite3_stmt *stmt,
                  unsigned int off)
{
  const struct TALER_AmountNBO *amount = data;
  struct TALER_Amount amount_hbo;

  (void) cls;
  (void) data_len;
  TALER_amount_ntoh (&amount_hbo,
                     amount);
  return qconv_amount (cls,
                       &amount_hbo,
                       sizeof (struct TALER_Amount),
                       stmt,
                       off);
}


struct GNUNET_SQ_QueryParam
TALER_SQ_query_param_amount_nbo (const struct TALER_AmountNBO *x)
{
  struct GNUNET_SQ_QueryParam res = {
    .conv = &qconv_amount_nbo,
    .data = x,
    .size = sizeof (*x),
    .num_params = 2
  };

  return res;
}


/**
 * Function called to convert input argument into SQL parameters.
 *
 * @param cls closure
 * @param data pointer to input argument, here a `struct TALER_Amount`
 * @param data_len number of bytes in @a data (if applicable)
 * @param stmt sqlite statement to parameters for
 * @param off offset of the argument to bind in @a stmt, numbered from 1,
 *            so immediately suitable for passing to `sqlite3_bind`-functions.
 * @return #GNUNET_SYSERR on error, #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
qconv_json (void *cls,
            const void *data,
            size_t data_len,
            sqlite3_stmt *stmt,
            unsigned int off)
{
  const json_t *json = data;
  char *str;

  (void) cls;
  (void) data_len;
  str = json_dumps (json, JSON_COMPACT);
  if (NULL == str)
    return GNUNET_SYSERR;

  if (SQLITE_OK != sqlite3_bind_text (stmt,
                                      (int) off,
                                      str,
                                      strlen (str) + 1,
                                      SQLITE_TRANSIENT))
    return GNUNET_SYSERR;
  GNUNET_free (str);
  return GNUNET_OK;
}


struct GNUNET_SQ_QueryParam
TALER_SQ_query_param_json (const json_t *x)
{
  struct GNUNET_SQ_QueryParam res = {
    .conv = &qconv_json,
    .data = x,
    .size = sizeof (*x),
    .num_params = 1
  };

  return res;
}


/* end of sq/sq_query_helper.c */
