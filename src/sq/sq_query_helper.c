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
static int
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


/**
 * Generate query parameter for a currency, consisting of the
 * components "value", "fraction" in this order. The
 * types must be a 64-bit integer and a 64-bit integer.
 *
 * @param x pointer to the query parameter to pass
 */
struct GNUNET_SQ_QueryParam
TALER_SQ_query_param_amount (const struct TALER_Amount *x)
{
  struct GNUNET_SQ_QueryParam res =
  { &qconv_amount, NULL, x, sizeof (*x), 2 };
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
static int
qconv_amount_nbo (void *cls,
                  const void *data,
                  size_t data_len,
                  sqlite3_stmt *stmt,
                  unsigned int off)
{
  const struct TALER_AmountNBO *amount = data;
  struct TALER_Amount amount_hbo;

  (void) cls;
  TALER_amount_ntoh (&amount_hbo,
                     amount);
  return qconv_amount (cls,
                       &amount_hbo,
                       sizeof (struct TALER_Amount),
                       stmt,
                       off);
}


/**
 * Generate query parameter for a currency, consisting of the
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
static int
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


/**
 * Generate query parameter for a JSON object (stored as a string
 * in the DB).  Note that @a x must really be a JSON object or array,
 * passing just a value (string, integer) is not supported and will
 * result in an abort.
 *
 * @param x pointer to the json object to pass
 */
struct GNUNET_SQ_QueryParam
TALER_SQ_query_param_json (const json_t *x)
{
  struct GNUNET_SQ_QueryParam res =
  { &qconv_json, NULL, x, sizeof (*x), 1 };
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
static int
qconv_round_time (void *cls,
                  const void *data,
                  size_t data_len,
                  sqlite3_stmt *stmt,
                  unsigned int off)
{
  const struct GNUNET_TIME_Absolute *at = data;
  struct GNUNET_TIME_Absolute tmp;

  (void) cls;
  GNUNET_assert (sizeof (struct GNUNET_TIME_AbsoluteNBO) == data_len);
  GNUNET_break (NULL == cls);
  tmp = *at;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_TIME_round_abs (&tmp));
  if (SQLITE_OK != sqlite3_bind_int64 (stmt,
                                       (int) off,
                                       (sqlite3_int64) at->abs_value_us))
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


/**
 * Generate query parameter for an absolute time value.
 * In contrast to
 * #GNUNET_SQ_query_param_absolute_time(), this function
 * will abort (!) if the time given is not rounded!
 * The database must store a 64-bit integer.
 *
 * @param x pointer to the query parameter to pass
 */
struct GNUNET_SQ_QueryParam
TALER_SQ_query_param_absolute_time (const struct GNUNET_TIME_Absolute *x)
{
  struct GNUNET_SQ_QueryParam res =
  { &qconv_round_time, NULL, x, sizeof (*x), 1 };
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
static int
qconv_round_time_abs (void *cls,
                      const void *data,
                      size_t data_len,
                      sqlite3_stmt *stmt,
                      unsigned int off)
{
  const struct GNUNET_TIME_AbsoluteNBO *at = data;
  struct GNUNET_TIME_Absolute tmp;

  (void) cls;
  GNUNET_assert (sizeof (struct GNUNET_TIME_AbsoluteNBO) == data_len);
  GNUNET_break (NULL == cls);
  tmp = GNUNET_TIME_absolute_ntoh (*at);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_TIME_round_abs (&tmp));
  if (SQLITE_OK != sqlite3_bind_int64 (stmt,
                                       (int) off,
                                       (sqlite3_int64) tmp.abs_value_us))
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


/**
 * Generate query parameter for an absolute time value.
 * In contrast to
 * #GNUNET_SQ_query_param_absolute_time(), this function
 * will abort (!) if the time given is not rounded!
 * The database must store a 64-bit integer.
 *
 * @param x pointer to the query parameter to pass
 */
struct GNUNET_SQ_QueryParam
TALER_SQ_query_param_absolute_time_nbo (const struct
                                        GNUNET_TIME_AbsoluteNBO *x)
{
  struct GNUNET_SQ_QueryParam res =
  { &qconv_round_time_abs, NULL, x, sizeof (*x), 1 };
  return res;
}


/* end of sq/sq_query_helper.c */
