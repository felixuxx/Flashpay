/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @param denom_pub pointer to the query parameter to pass
 */
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_denom_pub (
  const struct TALER_DenominationPublicKey *denom_pub);


/**
 * Generate query parameter for a denomination signature.  Internally, the
 * various attributes of the signature will be serialized into on
 * variable-size BLOB.
 *
 * @param denom_sig pointer to the query parameter to pass
 */
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_denom_sig (
  const struct TALER_DenominationSignature *denom_sig);


/**
 * Generate query parameter for a blinded planchet.
 * Internally, various attributes of the blinded
 * planchet will be serialized into on
 * variable-size BLOB.
 *
 * @param bp pointer to the query parameter to pass
 */
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_blinded_planchet (
  const struct TALER_BlindedPlanchet *bp);


/**
 * Generate query parameter for a blinded denomination signature.  Internally,
 * the various attributes of the signature will be serialized into on
 * variable-size BLOB.
 *
 * @param denom_sig pointer to the query parameter to pass
 */
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_blinded_denom_sig (
  const struct TALER_BlindedDenominationSignature *denom_sig);


/**
 * Generate query parameter for the exchange's contribution during a
 * withdraw. Internally, the various attributes of the @a alg_values will be
 * serialized into on variable-size BLOB.
 *
 * @param alg_values pointer to the query parameter to pass
 */
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_exchange_withdraw_values (
  const struct TALER_ExchangeWithdrawValues *alg_values);


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
 * Generate query parameter for an array of blinded denomination signatures
 *
 * @param num number of elements in @e denom_sigs
 * @param denom_sigs array of blinded denomination signatures
 * @param db context for the db-connection
 */
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_array_blinded_denom_sig (
  size_t num,
  const struct TALER_BlindedDenominationSignature *denom_sigs,
  const struct GNUNET_PQ_Context *db
  );

/**
 * Generate query parameter for an array of blinded hashes of coin envelopes
 *
 * @param num number of elements in @e denom_sigs
 * @param coin_evs array of blinded hashes of coin envelopes
 * @param db context for the db-connection
 */
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_array_blinded_coin_hash (
  size_t num,
  const struct TALER_BlindedCoinHashP *coin_evs,
  const struct GNUNET_PQ_Context *db);

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
 * Exchange withdraw values expected.
 *
 * @param name name of the field in the table
 * @param[out] ewv where to store the exchange values
 * @return array entry for the result specification to use
 */
struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_exchange_withdraw_values (
  const char *name,
  struct TALER_ExchangeWithdrawValues *ewv);


/**
 * Blinded planchet expected.
 *
 * @param name name of the field in the table
 * @param[out] bp where to store the blinded planchet
 * @return array entry for the result specification to use
 */
struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_blinded_planchet (
  const char *name,
  struct TALER_BlindedPlanchet *bp);


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
 * Array of blinded denomination signature expected
 *
 * @param db context of the database connection
 * @param name name of the field in the table
 * @param[out] num number of elements in @e denom_sigs
 * @param[out] denom_sigs where to store the result
 * @return array entry for the result specification to use
 */
struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_array_blinded_denom_sig (
  const struct GNUNET_PQ_Context *db,
  const char *name,
  size_t *num,
  struct TALER_BlindedDenominationSignature **denom_sigs);

/**
 * Array of blinded hashes of coin envelopes
 *
 * @param db context of the database connection
 * @param name name of the field in the table
 * @param[out] num number of elements in @e denom_sigs
 * @param[out] h_coin_evs where to store the result
 * @return array entry for the result specification to use
 */
struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_array_blinded_coin_hash (
  const struct GNUNET_PQ_Context *db,
  const char *name,
  size_t *num,
  struct TALER_BlindedCoinHashP **h_coin_evs);

/**
 * Array of hashes of denominations
 *
 * @param db context of the database connection
 * @param name name of the field in the table
 * @param[out] num number of elements in @e denom_sigs
 * @param[out] denom_hs where to store the result
 * @return array entry for the result specification to use
 */
struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_array_denom_hash (
  const struct GNUNET_PQ_Context *db,
  const char *name,
  size_t *num,
  struct TALER_DenominationHashP **denom_hs);

#endif  /* TALER_PQ_LIB_H_ */

/* end of include/taler_pq_lib.h */
