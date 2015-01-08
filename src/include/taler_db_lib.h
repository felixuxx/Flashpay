/*
  This file is part of TALER
  (C) 2014 Christian Grothoff (and other contributing authors)

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
 * @file include/taler_db_lib.h
 * @brief helper functions for DB interactions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Florian Dold
 */

#ifndef TALER_DB_LIB_H_
#define TALER_DB_LIB_H_

#include <libpq-fe.h>
#include "taler_util.h"

#define TALER_DB_QUERY_PARAM_END { NULL, 0, 0 }
#define TALER_DB_QUERY_PARAM_PTR(x) { (x), sizeof (*(x)), 1 }
#define TALER_DB_QUERY_PARAM_PTR_SIZED(x, s) { (x), (s), 1 }


#define TALER_DB_RESULT_SPEC_END { NULL, 0, NULL }
#define TALER_DB_RESULT_SPEC(name, dst) { (void *) (dst), sizeof (*(dst)), (name) }
#define TALER_DB_RESULT_SPEC_SIZED(name, dst, s) { (void *) (dst), (s), (name) }


/**
 * Description of a DB query parameter.
 */
struct TALER_DB_QueryParam
{
  /**
   * Data or NULL
   */
  const void *data;
  /**
   * Size of 'data'
   */
  size_t size;
  /**
   * Non-null if this is not the last parameter.
   * This allows for null as sentinal value.
   */
  int more;
};


/**
 * Description of a DB result cell.
 */
struct TALER_DB_ResultSpec
{
  /**
   * Destination for the data.
   */
  void *dst;

  /**
   * Allowed size for the data.
   */
  size_t dst_size;

  /**
   * Field name of the desired result.
   */
  char *fname;
};


/**
 * Execute a prepared statement.
 */
PGresult *
TALER_DB_exec_prepared (PGconn *db_conn,
                        const char *name,
                        const struct TALER_DB_QueryParam *params);


/**
 * Extract results from a query result according to the given specification.
 * If colums are NULL, the destination is not modified, and GNUNET_NO
 * is returned.
 *
 * @return
 *   GNUNET_YES if all results could be extracted
 *   GNUNET_NO if at least one result was NULL
 *   GNUNET_SYSERR if a result was invalid (non-existing field)
 */
int
TALER_DB_extract_result (PGresult *result, struct TALER_DB_ResultSpec *rs, int row);


int
TALER_DB_field_isnull (PGresult *result,
                       int row,
                       const char *fname);


int
TALER_DB_extract_amount_nbo (PGresult *result,
                             int row,
                             const char *val_name,
                             const char *frac_name,
                             const char *curr_name,
                             struct TALER_AmountNBO *r_amount_nbo);


int
TALER_DB_extract_amount (PGresult *result,
                         int row,
                         const char *val_name,
                         const char *frac_name,
                         const char *curr_name,
                         struct TALER_Amount *r_amount);

#endif  /* TALER_DB_LIB_H_ */

/* end of include/taler_db_lib.h */
