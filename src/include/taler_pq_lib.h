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
 * Different formats of results that can be added to a query.
 */
enum TALER_PQ_QueryFormat
{

  /**
   * List terminator.
   */
  TALER_PQ_QF_END,

  /**
   * We have a fixed-size result (binary blob, no endianess conversion).
   */
  TALER_PQ_QF_FIXED_BLOB,

  /**
   * We have a variable-size result (binary blob, no endianess conversion).
   */
  TALER_PQ_QF_VARSIZE_BLOB,

  /**
   * We have a currency amount (with endianess conversion).
   * Data points to a `struct TALER_AmountNBO`, size is only used to check.
   */
  TALER_PQ_QF_AMOUNT_NBO,

  /**
   * We have a currency amount (with endianess conversion).
   * Data points to a `struct TALER_Amount`, size is only used to check.
   */
  TALER_PQ_QF_AMOUNT,

  /**
   * We have an RSA public key.
   * Data points to a `struct GNUNET_CRYPTO_rsa_PublicKey`, size is not used.
   */
  TALER_PQ_QF_RSA_PUBLIC_KEY,

  /**
   * We have an RSA signature.
   * Data points to a `struct GNUNET_CRYPTO_rsa_Signature`, size is not used.
   */
  TALER_PQ_QF_RSA_SIGNATURE,

  /**
   * We have an absolute time.
   * Data points to a `struct GNUNET_TIME_Absolute`, size is only used to check.
   */
  TALER_PQ_QF_TIME_ABSOLUTE

};


/**
 * @brief Description of a DB query parameter.
 */
struct TALER_PQ_QueryParam
{

  /**
   * Format of the rest of the entry, determines the data
   * type that is being added to the query.
   */
  enum TALER_PQ_QueryFormat format;

  /**
   * Data or NULL.
   */
  const void *data;

  /**
   * Size of @e data
   */
  size_t size;

};


/**
 * End of query parameter specification.
 */
#define TALER_PQ_QUERY_PARAM_END { TALER_PQ_QF_END, NULL, 0 }

/**
 * Generate fixed-size query parameter with size given explicitly.
 *
 * @param x pointer to the query parameter to pass
 * @param s number of bytes of @a x to use for the query
 */
#define TALER_PQ_QUERY_PARAM_PTR_SIZED(x,s) { TALER_PQ_QF_FIXED_BLOB, (x), (s) }


/**
 * Generate fixed-size query parameter with size determined
 * by variable type.
 *
 * @param x pointer to the query parameter to pass.
 */
#define TALER_PQ_QUERY_PARAM_PTR(x) { TALER_PQ_QF_VARSIZE_BLOB, x, sizeof (*(x)) }


/**
 * Generate query parameter for a currency, consisting of the three
 * components "value", "fraction" and "currency" in this order. The
 * types must be a 64-bit integer, 32-bit integer and a
 * TALER_CURRENCY_LEN-sized BLOB/VARCHAR respectively.
 *
 * @param x pointer to the query parameter to pass
 */
struct TALER_PQ_QueryParam
TALER_PQ_QUERY_PARAM_AMOUNT_NBO(const struct TALER_AmountNBO *x);


/**
 * Generate query parameter for a currency, consisting of the three
 * components "value", "fraction" and "currency" in this order. The
 * types must be a 64-bit integer, 32-bit integer and a
 * TALER_CURRENCY_LEN-sized BLOB/VARCHAR respectively.
 *
 * @param x pointer to the query parameter to pass
 */
struct TALER_PQ_QueryParam
TALER_PQ_QUERY_PARAM_AMOUNT(const struct TALER_Amount *x);


/**
 * Generate query parameter for an RSA public key.  The
 * database must contain a BLOB type in the respective position.
 *
 * @param x the query parameter to pass.
 */
struct TALER_PQ_QueryParam
TALER_PQ_QUERY_PARAM_RSA_PUBLIC_KEY(const struct GNUNET_CRYPTO_rsa_PublicKey *x);


/**
 * Generate query parameter for an RSA signature.  The
 * database must contain a BLOB type in the respective position.
 *
 * @param x the query parameter to pass
 */
struct TALER_PQ_QueryParam
TALER_PQ_QUERY_PARAM_RSA_SIGNATURE(const struct GNUNET_CRYPTO_rsa_Signature *x);


/**
 * Generate query parameter for an absolute time value.
 * The database must store a 64-bit integer.
 *
 * @param x pointer to the query parameter to pass
 */
struct TALER_PQ_QueryParam
TALER_PQ_QUERY_PARAM_ABSOLUTE_TIME(struct GNUNET_TIME_Absolute x);


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
   * We expect a fixed-size result (binary blob, no endianess conversion).
   */
  TALER_PQ_RF_FIXED_BLOB,

  /**
   * We expect a variable-size result (binary blob, no endianess conversion).
   */
  TALER_PQ_RF_VARSIZE_BLOB,

  /**
   * We expect a currency amount.
   * Data points to a `struct TALER_AmountNBO`, size only used for checking.
   */
  TALER_PQ_RF_AMOUNT_NBO,

  /**
   * We expect a currency amount.
   * Data points to a `struct TALER_Amount`, size only used for checking.
   */
  TALER_PQ_RF_AMOUNT,

  /**
   * We expect an RSA public key.
   * Data points to a `struct GNUNET_CRYPTO_rsa_PublicKey **`, size is not used.
   */
  TALER_PQ_RF_RSA_PUBLIC_KEY,

  /**
   * We expect an RSA signature.
   * Data points to a `struct GNUNET_CRYPTO_rsa_Signature **`, size is not used.
   */
  TALER_PQ_RF_RSA_SIGNATURE,

  /**
   * We expect an absolute time.
   * Data points to a `struct GNUNET_TIME_Absolute`, size is only used for checking.
   */
  TALER_PQ_RF_TIME_ABSOLUTE

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
  const char *fname;

  /**
   * Where to store actual size of the result.
   */
  size_t *result_size;

};


/**
 * End of result parameter specification.
 *
 * @return array last entry for the result specification to use
 */
#define TALER_PQ_RESULT_SPEC_END { TALER_PQ_RF_END, NULL, 0, NULL, NULL }

/**
 * We expect a fixed-size result, with size given explicitly
 *
 * @param name name of the field in the table
 * @param dst point to where to store the result
 * @param s number of bytes we should use in @a dst
 * @return array entry for the result specification to use
 */
#define TALER_PQ_RESULT_SPEC_SIZED(name, dst, s) { TALER_PQ_RF_FIXED_BLOB,  (void *) (dst), (s), (name), NULL }


/**
 * We expect a fixed-size result, with size determined by the type of `* dst`
 *
 * @param name name of the field in the table
 * @param dst point to where to store the result, type fits expected result size
 * @return array entry for the result specification to use
 */
#define TALER_PQ_RESULT_SPEC(name, dst) { TALER_PQ_RF_FIXED_BLOB, (void *) (dst), sizeof (*(dst)), name, NULL }


/**
 * Variable-size result expected.
 *
 * @param name name of the field in the table
 * @param[out] dst where to store the result, allocated
 * @param[out] sptr where to store the size of @a dst
 * @return array entry for the result specification to use
 */
struct TALER_PQ_ResultSpec
TALER_PQ_RESULT_SPEC_VAR (const char *name,
			  void **dst,
			  size_t *sptr);


/**
 * Currency amount expected.
 *
 * @param name name of the field in the table
 * @param[out] amount where to store the result
 * @return array entry for the result specification to use
 */
struct TALER_PQ_ResultSpec
TALER_PQ_RESULT_SPEC_AMOUNT_NBO (const char *name,
				 struct TALER_AmountNBO *amount);


/**
 * Currency amount expected.
 *
 * @param name name of the field in the table
 * @param[out] amount where to store the result
 * @return array entry for the result specification to use
 */
struct TALER_PQ_ResultSpec
TALER_PQ_RESULT_SPEC_AMOUNT (const char *name,
			     struct TALER_Amount *amount);


/**
 * RSA public key expected.
 *
 * @param name name of the field in the table
 * @param[out] rsa where to store the result
 * @return array entry for the result specification to use
 */
struct TALER_PQ_ResultSpec
TALER_PQ_RESULT_SPEC_RSA_PUBLIC_KEY (const char *name,
				     struct GNUNET_CRYPTO_rsa_PublicKey **rsa);


/**
 * RSA signature expected.
 *
 * @param name name of the field in the table
 * @param[out] sig where to store the result;
 * @return array entry for the result specification to use
 */
struct TALER_PQ_ResultSpec
TALER_PQ_RESULT_SPEC_RSA_SIGNATURE (const char *name,
				    struct GNUNET_CRYPTO_rsa_Signature **sig);


/**
 * Absolute time expected.
 *
 * @param name name of the field in the table
 * @param[out] at where to store the result
 * @return array entry for the result specification to use
 */
struct TALER_PQ_ResultSpec
TALER_PQ_RESULT_SPEC_ABSOLUTE_TIME (const char *name,
				    struct GNUNET_TIME_Absolute *at);


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
 * Free all memory that was allocated in @a rs during
 * #TALER_PQ_extract_result().
 *
 * @param rs reult specification to clean up
 */
void
TALER_PQ_cleanup_result (struct TALER_PQ_ResultSpec *rs);


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

/* end of include/taler_pq_lib.h */
