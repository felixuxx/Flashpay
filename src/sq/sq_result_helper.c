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
extract_amount (void *cls,
                sqlite3_stmt *result,
                unsigned int column,
                size_t *dst_size,
                void *dst)
{
  struct TALER_Amount *amount = dst;
  const char *currency = cls;
  if ((sizeof (struct TALER_Amount) != *dst_size) ||
      (SQLITE_INTEGER != sqlite3_column_type (result,
                                              (int) column)) ||
      (SQLITE_INTEGER != sqlite3_column_type (result,
                                              (int) column + 1)))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_strlcpy (amount->currency,
                  currency,
                  TALER_CURRENCY_LEN);
  amount->value = (uint64_t) sqlite3_column_int64 (result,
                                                   (int) column);
  uint64_t frac = (uint64_t) sqlite3_column_int64 (result,
                                                   (int) column + 1);
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
TALER_SQ_result_spec_amount (const char *currency,
                             struct TALER_Amount *amount)
{
  struct GNUNET_SQ_ResultSpec res = {
    .conv = &extract_amount,
    .cls = (void *) currency,
    .dst = (void *) amount,
    .dst_size = sizeof (struct TALER_Amount),
    .num_params = 2
  };

  return res;
}


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
  struct TALER_Amount amount_hbo;
  size_t amount_hbo_size = sizeof (struct TALER_Amount);
  if (GNUNET_YES != extract_amount (cls,
                                    result,
                                    column,
                                    &amount_hbo_size,
                                    &amount_hbo))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  TALER_amount_hton (amount,
                     &amount_hbo);
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


/**
 * Extract amount data from a SQLite database
 *
 * @param cls closure
 * @param result where to extract data from
 * @param column column to extract data from
 * @param[in,out] dst_size where to store size of result, may be NULL
 * @param[out] dst where to store the result
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_SYSERR if a result was invalid (non-existing field or NULL)
 */
static int
extract_json (void *cls,
              sqlite3_stmt *result,
              unsigned int column,
              size_t *dst_size,
              void *dst)
{
  json_t **j_dst = dst;
  const char *res;
  json_error_t json_error;
  size_t slen;

  (void) cls;
  (void) dst_size;
  if (SQLITE_TEXT != sqlite3_column_type (result,
                                          column))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  res = (const char *) sqlite3_column_text (result,
                                            column);
  slen = strlen (res);
  *j_dst = json_loadb (res,
                       slen,
                       JSON_REJECT_DUPLICATES,
                       &json_error);
  if (NULL == *j_dst)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to parse JSON result for column %d: %s (%s)\n",
                column,
                json_error.text,
                json_error.source);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Function called to clean up memory allocated
 * by a #GNUNET_SQ_ResultConverter.
 *
 * @param cls closure
 */
static void
clean_json (void *cls)
{
  json_t **dst = cls;

  (void) cls;
  if (NULL != *dst)
  {
    json_decref (*dst);
    *dst = NULL;
  }
}


/**
 * json_t expected.
 *
 * @param[out] jp where to store the result
 * @return array entry for the result specification to use
 */
struct GNUNET_SQ_ResultSpec
TALER_SQ_result_spec_json (json_t **jp)
{
  struct GNUNET_SQ_ResultSpec res = {
    .conv = &extract_json,
    .cleaner = &clean_json,
    .dst = (void *) jp,
    .cls = (void *) jp,
    .num_params = 1
  };

  return res;
}


/**
 * Extract amount data from a SQLite database
 *
 * @param cls closure
 * @param result where to extract data from
 * @param column column to extract data from
 * @param[in,out] dst_size where to store size of result, may be NULL
 * @param[out] dst where to store the result
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_SYSERR if a result was invalid (non-existing field or NULL)
 */
static int
extract_round_time (void *cls,
                    sqlite3_stmt *result,
                    unsigned int column,
                    size_t *dst_size,
                    void *dst)
{
  struct GNUNET_TIME_Absolute *udst = dst;
  struct GNUNET_TIME_Absolute tmp;

  (void) cls;
  if (SQLITE_INTEGER != sqlite3_column_type (result,
                                             (int) column))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_assert (NULL != dst);
  if (sizeof (struct GNUNET_TIME_Absolute) != *dst_size)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  tmp.abs_value_us = sqlite3_column_int64 (result,
                                           (int) column);
  GNUNET_break (GNUNET_OK ==
                GNUNET_TIME_round_abs (&tmp));
  *udst = tmp;
  return GNUNET_OK;
}


/**
 * Rounded absolute time expected.
 * In contrast to #GNUNET_SQ_query_param_absolute_time_nbo(),
 * this function ensures that the result is rounded and can
 * be converted to JSON.
 *
 * @param[out] at where to store the result
 * @return array entry for the result specification to use
 */
struct GNUNET_SQ_ResultSpec
TALER_SQ_result_spec_absolute_time (struct GNUNET_TIME_Absolute *at)
{
  struct GNUNET_SQ_ResultSpec res = {
    .conv = &extract_round_time,
    .dst = (void *) at,
    .dst_size = sizeof (struct GNUNET_TIME_Absolute),
    .num_params = 1
  };

  return res;
}


/**
 * Extract amount data from a SQLite database
 *
 * @param cls closure
 * @param result where to extract data from
 * @param column column to extract data from
 * @param[in,out] dst_size where to store size of result, may be NULL
 * @param[out] dst where to store the result
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_SYSERR if a result was invalid (non-existing field or NULL)
 */
static int
extract_round_time_nbo (void *cls,
                        sqlite3_stmt *result,
                        unsigned int column,
                        size_t *dst_size,
                        void *dst)
{
  struct GNUNET_TIME_AbsoluteNBO *udst = dst;
  struct GNUNET_TIME_Absolute tmp;

  (void) cls;
  if (SQLITE_INTEGER != sqlite3_column_type (result,
                                             (int) column))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_assert (NULL != dst);
  if (sizeof (struct GNUNET_TIME_AbsoluteNBO) != *dst_size)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  tmp.abs_value_us = sqlite3_column_int64 (result,
                                           (int) column);
  GNUNET_break (GNUNET_OK ==
                GNUNET_TIME_round_abs (&tmp));
  *udst = GNUNET_TIME_absolute_hton (tmp);
  return GNUNET_OK;
}


/**
 * Rounded absolute time expected.
 * In contrast to #GNUNET_SQ_result_spec_absolute_time_nbo(),
 * this function ensures that the result is rounded and can
 * be converted to JSON.
 *
 * @param[out] at where to store the result
 * @return array entry for the result specification to use
 */
struct GNUNET_SQ_ResultSpec
TALER_SQ_result_spec_absolute_time_nbo (struct GNUNET_TIME_AbsoluteNBO *at)
{
  struct GNUNET_SQ_ResultSpec res = {
    .conv = &extract_round_time_nbo,
    .dst = (void *) at,
    .dst_size = sizeof (struct GNUNET_TIME_AbsoluteNBO),
    .num_params = 1
  };

  return res;
}


/* end of sq/sq_result_helper.c */
