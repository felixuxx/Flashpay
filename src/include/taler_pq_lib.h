/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 Taler Systems SA

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
 * @file include/taler_pq_lib.h
 * @brief helper functions for DB interactions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Florian Dold
 * @author Christian Grothoff
 */
#ifndef TALER_PQ_LIB_H_
#define TALER_PQ_LIB_H_

#include <libpq-fe.h>
#include <jansson.h>
#include <gnunet/gnunet_pq_lib.h>
#include "taler_util.h"

/**
 * Generate query parameter for a currency, consisting of the three
 * components "value", "fraction" and "currency" in this order. The
 * types must be a 64-bit integer, 32-bit integer and a
 * #TALER_CURRENCY_LEN-sized BLOB/VARCHAR respectively.
 *
 * @param x pointer to the query parameter to pass
 */
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_amount_nbo (const struct TALER_AmountNBO *x);


/**
 * Generate query parameter for an amount, consisting of the two
 * components "value" and "fraction" in this order. The
 * types must be a 64-bit integer and a 32-bit integer
 * respectively. The currency is dropped.
 *
 * @param x pointer to the query parameter to pass
 */
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_amount (const struct TALER_Amount *x);


/**
 * Generate query parameter for a denomination public
 * key. Internally, the various attributes of the
 * public key will be serialized into on variable-size
 * BLOB.
 *
 * @param x pointer to the query parameter to pass
 */
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_denom_pub (
  const struct TALER_DenominationPublicKey *denom_pub);


/**
 * Generate query parameter for a denomination signature.  Internally, the
 * various attributes of the signature will be serialized into on
 * variable-size BLOB.
 *
 * @param x pointer to the query parameter to pass
 */
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_denom_sig (
  const struct TALER_DenominationSignature *denom_sig);


/**
 * Generate query parameter for a blinded denomination signature.  Internally,
 * the various attributes of the signature will be serialized into on
 * variable-size BLOB.
 *
 * @param x pointer to the query parameter to pass
 */
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_blinded_denom_sig (
  const struct TALER_BlindedDenominationSignature *denom_sig);


/**
 * Generate query parameter for a JSON object (stored as a string
 * in the DB).  Note that @a x must really be a JSON object or array,
 * passing just a value (string, integer) is not supported and will
 * result in an abort.
 *
 * @param x pointer to the json object to pass
 */
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_json (const json_t *x);


/**
 * Generate query parameter for an absolute time value.
 * In contrast to
 * #GNUNET_PQ_query_param_absolute_time(), this function
 * will abort (!) if the time given is not rounded!
 * The database must store a 64-bit integer.
 *
 * @param x pointer to the query parameter to pass
 */
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_absolute_time (const struct GNUNET_TIME_Absolute *x);


/**
 * Generate query parameter for an absolute time value.
 * In contrast to
 * #GNUNET_PQ_query_param_absolute_time(), this function
 * will abort (!) if the time given is not rounded!
 * The database must store a 64-bit integer.
 *
 * @param x pointer to the query parameter to pass
 */
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_absolute_time_nbo (const struct
                                        GNUNET_TIME_AbsoluteNBO *x);


/**
 * Currency amount expected.
 *
 * @param name name of the field in the table
 * @param currency currency to use for @a amount
 * @param[out] amount where to store the result
 * @return array entry for the result specification to use
 */
struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_amount_nbo (const char *name,
                                 const char *currency,
                                 struct TALER_AmountNBO *amount);


/**
 * Currency amount expected.
 *
 * @param name name of the field in the table
 * @param currency currency to use for @a amount
 * @param[out] amount where to store the result
 * @return array entry for the result specification to use
 */
struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_amount (const char *name,
                             const char *currency,
                             struct TALER_Amount *amount);


/**
 * Denomination public key expected.
 *
 * @param name name of the field in the table
 * @param[out] denom_pub where to store the public key
 * @return array entry for the result specification to use
 */
struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_denom_pub (const char *name,
                                struct TALER_DenominationPublicKey *denom_pub);


/**
 * Denomination signature expected.
 *
 * @param name name of the field in the table
 * @param[out] denom_sig where to store the denomination signature
 * @return array entry for the result specification to use
 */
struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_denom_sig (const char *name,
                                struct TALER_DenominationSignature *denom_sig);


/**
 * Blinded denomination signature expected.
 *
 * @param name name of the field in the table
 * @param[out] denom_sig where to store the denomination signature
 * @return array entry for the result specification to use
 */
struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_blinded_denom_sig (
  const char *name,
  struct TALER_BlindedDenominationSignature *denom_sig);


/**
 * json_t expected.
 *
 * @param name name of the field in the table
 * @param[out] jp where to store the result
 * @return array entry for the result specification to use
 */
struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_json (const char *name,
                           json_t **jp);


/**
 * Rounded absolute time expected.
 * In contrast to #GNUNET_PQ_query_param_absolute_time_nbo(),
 * this function ensures that the result is rounded and can
 * be converted to JSON.
 *
 * @param name name of the field in the table
 * @param[out] at where to store the result
 * @return array entry for the result specification to use
 */
struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_absolute_time (const char *name,
                                    struct GNUNET_TIME_Absolute *at);


/**
 * Rounded absolute time expected.
 * In contrast to #GNUNET_PQ_result_spec_absolute_time_nbo(),
 * this function ensures that the result is rounded and can
 * be converted to JSON.
 *
 * @param name name of the field in the table
 * @param[out] at where to store the result
 * @return array entry for the result specification to use
 */
struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_absolute_time_nbo (const char *name,
                                        struct GNUNET_TIME_AbsoluteNBO *at);


#endif  /* TALER_PQ_LIB_H_ */

/* end of include/taler_pq_lib.h */
