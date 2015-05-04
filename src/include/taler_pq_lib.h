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
 * @file include/taler_pq_lib.h
 * @brief helper functions for DB interactions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Florian Dold
 * @author Christian Grothoff
 */
#ifndef TALER_PQ_LIB_H_
#define TALER_PQ_LIB_H_

#include <libpq-fe.h>
#include "taler_util.h"

/**
 * @brief Description of a DB query parameter.
 */
struct TALER_PQ_QueryParam
{
  /**
   * Data or NULL.
   */
  const void *data;

  /**
   * Size of @e data
   */
  size_t size;

  /**
   * Non-null if this is not the last parameter.
   * This allows us to detect the end of the list.
   */
  int more;
};


/**
 * End of query parameter specification.
 */
#define TALER_PQ_QUERY_PARAM_END { NULL, 0, 0 }

/**
 * Generate fixed-size query parameter with size given explicitly.
 *
 * @param x pointer to the query parameter to pass
 * @param s number of bytes of @a x to use for the query
 */
#define TALER_PQ_QUERY_PARAM_PTR_SIZED(x, s) { (x), (s), 1 }

/**
 * Generate fixed-size query parameter with size determined
 * by variable type.
 *
 * @param x pointer to the query parameter to pass.
 */
#define TALER_PQ_QUERY_PARAM_PTR(x) TALER_PQ_QUERY_PARAM_PTR_SIZED(x, sizeof (*(x)))


/**
 * Different formats of results that can be extracted.
 */
enum TALER_PQ_ResultFormat
{

  /**
   * List terminator.
   */
  TALER_PQ_RF_END,

  /**
   * We have a fixed-size result (binary blob, no endianess conversion).
   */
  TALER_PQ_RF_FIXED_BLOB,

  /**
   * We have a variable-size result (binary blob, no endianess conversion).
   */
  TALER_PQ_RF_VARSIZE_BLOB,

  /**
   * We have a currency amount (with endianess conversion).
   * Data points to a `struct TALER_Amount`, size is not used.
   */
  TALER_PQ_RF_AMOUNT
};


/**
 * @brief Description of a DB result cell.
 */
struct TALER_PQ_ResultSpec
{

  /**
   * What is the format of the result?
   */
  enum TALER_PQ_ResultFormat format;

  /**
   * Destination for the data.
   */
  void *dst;

  /**
   * Allowed size for the data, 0 for variable-size
   * (in this case, the type of @e dst is a `void **`
   * and we need to allocate a buffer of the right size).
   */
  size_t dst_size;

  /**
   * Field name of the desired result.
   */
  char *fname;

  /**
   * Where to store actual size of the result.
   */
  size_t *result_size;

};


/**
 * End of result parameter specification.
 */
#define TALER_PQ_RESULT_SPEC_END { TALER_PQ_RF_END, NULL, 0, NULL, NULL }

/**
 * We expect a fixed-size result, with size given explicitly
 *
 * @param name name of the field in the table
 * @param dst point to where to store the result
 * @param s number of bytes we should use in @a dst
 */
#define TALER_PQ_RESULT_SPEC_SIZED(name, dst, s) { TALER_PQ_RF_FIXED_BLOB,  (void *) (dst), (s), (name), NULL }


/**
 * We expect a fixed-size result, with size determined by the type of `* dst`
 *
 * @param name name of the field in the table
 * @param dst point to where to store the result, type fits expected result size
 */
#define TALER_PQ_RESULT_SPEC(name, dst) TALER_PQ_RESULT_SPEC_SIZED(name, dst, sizeof (*(dst)))


/**
 * Variable-size result expected.
 *
 * @param name name of the field in the table
 * @param dst where to store the result (of type void **), to be allocated
 * @param sptr pointer to a `size_t` for where to store the size of @a dst
 */
#define TALER_PQ_RESULT_SPEC_VAR(name, dst, sptr) {TALER_PQ_RF_VARSIZE_BLOB, (void *) (dst), 0, (name), sptr }


/**
 * Currency amount expected.
 *
 * @param name name of the field in the table
 * @param amount a `struct TALER_Amount` where to store the result
 */
#define TALER_PQ_RESULT_SPEC_AMOUNT(name, amount) {TALER_PQ_RF_AMOUNT, (void *) (&dst), 0, (name), sptr }


/**
 * Execute a prepared statement.
 *
 * @param db_conn database connection
 * @param name name of the prepared statement
 * @param params parameters to the statement
 * @return postgres result
 */
PGresult *
TALER_PQ_exec_prepared (PGconn *db_conn,
                        const char *name,
                        const struct TALER_PQ_QueryParam *params);


/**
 * Extract results from a query result according to the given specification.
 * If colums are NULL, the destination is not modified, and GNUNET_NO
 * is returned.
 *
 * @param result result to process
 * @param[in|out] rs result specification to extract for
 * @param row row from the result to extract
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_NO if at least one result was NULL
 *   #GNUNET_SYSERR if a result was invalid (non-existing field)
 */
int
TALER_PQ_extract_result (PGresult *result,
                         struct TALER_PQ_ResultSpec *rs,
                         int row);


/**
 * Extract a currency amount from a query result according to the
 * given specification.
 *
 * @param result the result to extract the amount from
 * @param row which row of the result to extract the amount from (needed as results can have multiple rows)
 * @param val_name name of the column with the amount's "value", must include the substring "_val".
 * @param frac_name name of the column with the amount's "fractional" value, must include the substring "_frac".
 * @param curr_name name of the column with the amount's currency name, must include the substring "_curr".
 * @param[out] r_amount_nbo where to store the amount, in network byte order
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_NO if at least one result was NULL
 *   #GNUNET_SYSERR if a result was invalid (non-existing field)
 */
int
TALER_PQ_extract_amount_nbo (PGresult *result,
                             int row,
                             const char *val_name,
                             const char *frac_name,
                             const char *curr_name,
                             struct TALER_AmountNBO *r_amount_nbo);


/**
 * Extract a currency amount from a query result according to the
 * given specification.
 *
 * @param result the result to extract the amount from
 * @param row which row of the result to extract the amount from (needed as results can have multiple rows)
 * @param val_name name of the column with the amount's "value", must include the substring "_val".
 * @param frac_name name of the column with the amount's "fractional" value, must include the substring "_frac".
 * @param curr_name name of the column with the amount's currency name, must include the substring "_curr".
 * @param[out] r_amount where to store the amount, in host byte order
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_NO if at least one result was NULL
 *   #GNUNET_SYSERR if a result was invalid (non-existing field)
 */
int
TALER_PQ_extract_amount (PGresult *result,
                         int row,
                         const char *val_name,
                         const char *frac_name,
                         const char *curr_name,
                         struct TALER_Amount *r_amount);




#endif  /* TALER_PQ_LIB_H_ */

/* end of db/taler_pq_lib.h */
