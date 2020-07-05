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
 * @file include/taler_json_lib.h
 * @brief helper functions for JSON processing using libjansson
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#ifndef TALER_JSON_LIB_H_
#define TALER_JSON_LIB_H_

#include <jansson.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_util.h"
#include "taler_error_codes.h"

/**
 * Print JSON parsing related error information
 * @deprecated
 */
#define TALER_json_warn(error)                                         \
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,                                \
              "JSON parsing failed at %s:%u: %s (%s)\n",                  \
              __FILE__, __LINE__, error.text, error.source)

/**
 * Convert a TALER amount to a JSON object.
 *
 * @param amount the amount
 * @return a json object describing the amount
 */
json_t *
TALER_JSON_from_amount (const struct TALER_Amount *amount);


/**
 * Convert a TALER amount to a JSON object.
 *
 * @param amount the amount
 * @return a json object describing the amount
 */
json_t *
TALER_JSON_from_amount_nbo (const struct TALER_AmountNBO *amount);


/**
 * Provide specification to parse given JSON object to an amount.
 *
 * @param name name of the amount field in the JSON
 * @param[out] r_amount where the amount has to be written
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_amount (const char *name,
                        struct TALER_Amount *r_amount);


/**
 * Provide specification to parse given JSON object to an amount
 * in network byte order.
 *
 * @param name name of the amount field in the JSON
 * @param[out] r_amount where the amount has to be written
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_amount_nbo (const char *name,
                            struct TALER_AmountNBO *r_amount);


/**
 * Provide specification to parse given JSON object to an absolute time.
 * The absolute time value is expected to be already rounded.
 *
 * @param name name of the time field in the JSON
 * @param[out] r_time where the time has to be written
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_absolute_time (const char *name,
                               struct GNUNET_TIME_Absolute *r_time);


/**
 * Provide specification to parse given JSON object to an absolute time
 * in network byte order.
 * The absolute time value is expected to be already rounded.
 *
 * @param name name of the time field in the JSON
 * @param[out] r_time where the time has to be written
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_absolute_time_nbo (const char *name,
                                   struct GNUNET_TIME_AbsoluteNBO *r_time);


/**
 * Generate line in parser specification for denomination public key.
 *
 * @param field name of the field
 * @param[out] pk key to initialize
 * @return corresponding field spec
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_denomination_public_key (const char *field,
                                         struct TALER_DenominationPublicKey *pk);


/**
 * Generate line in parser specification for denomination signature.
 *
 * @param field name of the field
 * @param sig the signature to initialize
 * @return corresponding field spec
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_denomination_signature (const char *field,
                                        struct TALER_DenominationSignature *sig);


/**
 * Hash a JSON for binary signing.
 *
 * See https://tools.ietf.org/html/draft-rundgren-json-canonicalization-scheme-15
 * for fun JSON canonicalization problems.  Callers must ensure that
 * those are avoided in the input. We will use libjanson's "JSON_COMPACT"
 * encoding for whitespace and "JSON_SORT_KEYS" to canonicalize as best
 * as we can.
 *
 * @param[in] json some JSON value to hash
 * @param[out] hc resulting hash code
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_JSON_hash (const json_t *json,
                 struct GNUNET_HashCode *hc);

/**
 * Extract the Taler error code from the given @a json object.
 * Note that #TALER_EC_NONE is returned if no "code" is present.
 *
 * @param json response to extract the error code from
 * @return the "code" value from @a json
 */
enum TALER_ErrorCode
TALER_JSON_get_error_code (const json_t *json);


/**
 * Extract the Taler error hint from the given @a json object.
 * Note that NULL is returned if no "hint" is present.
 *
 * @param json response to extract the error hint from
 * @return the "hint" value from @a json; only valid as long as @a json is valid
 */
const char *
TALER_JSON_get_error_hint (const json_t *json);


/**
 * Extract the Taler error code from the given @a data object, which is expected to be in JSON.
 * Note that #TALER_EC_INVALID is returned if no "code" is present or if @a data is not in JSON.
 *
 * @param data response to extract the error code from
 * @param data_size number of bytes in @a data
 * @return the "code" value from @a json
 */
enum TALER_ErrorCode
TALER_JSON_get_error_code2 (const void *data,
                            size_t data_size);


/* **************** /wire account offline signing **************** */

/**
 * Compute the hash of the given wire details.   The resulting
 * hash is what is put into the contract.  Also performs rudimentary
 * checks on the account data *if* supported.
 *
 * @param wire_s wire details to hash
 * @param[out] hc set to the hash
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if @a wire_s is malformed
 */
int
TALER_JSON_merchant_wire_signature_hash (const json_t *wire_s,
                                         struct GNUNET_HashCode *hc);


/**
 * Check the signature in @a wire_s.  Also performs rudimentary
 * checks on the account data *if* supported.
 *
 * @param wire_s signed wire information of an exchange
 * @param master_pub master public key of the exchange
 * @return #GNUNET_OK if signature is valid
 */
int
TALER_JSON_exchange_wire_signature_check (
  const json_t *wire_s,
  const struct TALER_MasterPublicKeyP *master_pub);


/**
 * Create a signed wire statement for the given account.
 *
 * @param payto_uri account specification
 * @param master_priv private key to sign with
 * @return NULL if @a payto_uri is malformed
 */
json_t *
TALER_JSON_exchange_wire_signature_make (
  const char *payto_uri,
  const struct TALER_MasterPrivateKeyP *master_priv);


/**
 * Obtain the wire method associated with the given
 * wire account details.  @a wire_s must contain a payto://-URL
 * under 'url'.
 *
 * @return NULL on error
 */
char *
TALER_JSON_wire_to_method (const json_t *wire_s);


/**
 * Obtain the payto://-URL associated with the given
 * wire account details.  @a wire_s must contain a payto://-URL
 * under 'payto_uri'.
 *
 * @return NULL on error
 */
char *
TALER_JSON_wire_to_payto (const json_t *wire_s);


#endif /* TALER_JSON_LIB_H_ */

/* End of taler_json_lib.h */
