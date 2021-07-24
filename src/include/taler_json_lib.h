/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016, 2021 Taler Systems SA

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
 * The @a currency must be a valid pointer while the
 * parsing is done, a copy is not made.
 *
 * @param name name of the amount field in the JSON
 * @param currency the currency the amount must be in
 * @param[out] r_amount where the amount has to be written
 * @return spec for parsing an amount
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_amount (const char *name,
                        const char *currency,
                        struct TALER_Amount *r_amount);


/**
 * Provide specification to parse given JSON object to an amount
 * in network byte order.
 * The @a currency must be a valid pointer while the
 * parsing is done, a copy is not made.
 *
 * @param name name of the amount field in the JSON
 * @param currency the currency the amount must be in
 * @param[out] r_amount where the amount has to be written
 * @return spec for parsing an amount
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_amount_nbo (const char *name,
                            const char *currency,
                            struct TALER_AmountNBO *r_amount);


/**
 * Provide specification to parse given JSON object to an amount
 * in any currency.
 *
 * @param name name of the amount field in the JSON
 * @param[out] r_amount where the amount has to be written
 * @return spec for parsing an amount
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_amount_any (const char *name,
                            struct TALER_Amount *r_amount);


/**
 * Provide specification to parse given JSON object to an amount
 * in any currency in network byte order.
 *
 * @param name name of the amount field in the JSON
 * @param[out] r_amount where the amount has to be written
 * @return spec for parsing an amount
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_amount_any_nbo (const char *name,
                                struct TALER_AmountNBO *r_amount);


/**
 * Provide specification to parse given JSON object to an absolute time.
 * The absolute time value is expected to be already rounded.
 *
 * @param name name of the time field in the JSON
 * @param[out] r_time where the time has to be written
 * @return spec for parsing an absolute time
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
 * @return spec for parsing an absolute time
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_absolute_time_nbo (const char *name,
                                   struct GNUNET_TIME_AbsoluteNBO *r_time);


/**
 * Provide specification to parse given JSON object to a relative time.
 * The absolute time value is expected to be already rounded.
 *
 * @param name name of the time field in the JSON
 * @param[out] r_time where the time has to be written
 * @return spec for parsing a relative time
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_relative_time (const char *name,
                               struct GNUNET_TIME_Relative *r_time);


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
 * The expected field stores a possibly internationalized string.
 * Internationalization means that there is another field "$name_i18n"
 * which is an object where the keys are languages.  If this is
 * present, and if @a language_pattern is non-NULL, this function
 * should return the best match from @a language pattern from the
 * "_i18n" field.  If no language matches, the normal field under
 * @a name is to be returned.
 *
 * The @a language_pattern is given using the format from
 * https://tools.ietf.org/html/rfc7231#section-5.3.1
 * so that #TALER_language_matches() can be used.
 *
 * @param name name of the JSON field
 * @param language_pattern language pattern to use to find best match, possibly NULL
 * @param[out] strptr where to store a pointer to the field with the best variant
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_i18n_string (const char *name,
                             const char *language_pattern,
                             const char **strptr);


/**
 * The expected field stores a possibly internationalized string.
 * Internationalization means that there is another field "$name_i18n" which
 * is an object where the keys are languages.  If this is present, this
 * function should return the best match based on the locale from the "_i18n"
 * field.  If no language matches, the normal field under @a name is to be
 * returned.
 *
 * @param name name of the JSON field
 * @param[out] strptr where to store a pointer to the field with the best variant
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_i18n_str (const char *name,
                          const char **strptr);


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
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO if @a json was malformed
 *         #GNUNET_SYSERR on internal error
 */
enum GNUNET_GenericReturnValue
TALER_JSON_contract_hash (const json_t *json,
                          struct GNUNET_HashCode *hc);


/**
 * Take a given contract with "forgettable" fields marked
 * but with 'True' instead of a real salt. Replaces all
 * 'True' values with proper random salts.  Fails if any
 * forgettable markers are neither 'True' nor valid salts.
 *
 * @param[in,out] json JSON to transform
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_JSON_contract_seed_forgettable (json_t *json);


/**
 * Mark part of a contract object as 'forgettable'.
 *
 * @param[in,out] json some JSON object to modify
 * @param field name of the field to mark as forgettable
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
enum GNUNET_GenericReturnValue
TALER_JSON_contract_mark_forgettable (json_t *json,
                                      const char *field);


/**
 * Forget part of a contract object.
 *
 * @param[in,out] json some JSON object to modify
 * @param field name of the field to forget
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO if the field was already forgotten before
 *         #GNUNET_SYSERR on error
 */
enum GNUNET_GenericReturnValue
TALER_JSON_contract_part_forget (json_t *json,
                                 const char *field);


/**
 * Called for each path found after expanding a path.
 *
 * @param cls the closure.
 * @param object_id the name of the object that is pointed to.
 * @param parent the parent of the object at @e object_id.
 */
typedef void
(*TALER_JSON_ExpandPathCallback) (
  void *cls,
  const char *object_id,
  json_t *parent);


/**
 * Expands a path for a json object. May call the callback several times
 * if the path contains a wildcard.
 *
 * @param json the json object the path references.
 * @param path the path to expand. Must begin with "$." and follow dot notation,
 *        and may include array indices and wildcards.
 * @param cb the callback.
 * @param cb_cls closure for the callback.
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if @e path is invalid.
 */
enum GNUNET_GenericReturnValue
TALER_JSON_expand_path (json_t *json,
                        const char *path,
                        TALER_JSON_ExpandPathCallback cb,
                        void *cb_cls);


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
 * Validate payto:// account URL (only account information,
 * wire subject and amount are ignored).
 *
 * @param payto_uri URL to parse
 * @return #GNUNET_YES if @a payto_uri is a valid payto://iban URI
 *         #GNUNET_NO if @a payto_uri  is a payto URI of an unsupported type (but may be valid)
 *         #GNUNET_SYSERR if the account incorrect or this is not a payto://-URI at all
 */
enum GNUNET_GenericReturnValue
TALER_JSON_validate_payto (const char *payto_uri);


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
 * Extract a string from @a object under the field @a field, but respecting
 * the Taler i18n rules and the language preferences expressed in @a
 * language_pattern.
 *
 * Basically, the @a object may optionally contain a sub-object
 * "${field}_i18n" with a map from IETF BCP 47 language tags to a localized
 * version of the string. If this map exists and contains an entry that
 * matches the @a language pattern, that object (usually a string) is
 * returned. If the @a language_pattern does not match any entry, or if the
 * i18n sub-object does not exist, we simply return @a field of @a object
 * (also usually a string).
 *
 * If @a object does not have a member @a field we return NULL (error).
 *
 * @param object the object to extract internationalized
 *        content from
 * @param language_pattern a language preferences string
 *        like "fr-CH, fr;q=0.9, en;q=0.8, *;q=0.1", following
 *        https://tools.ietf.org/html/rfc7231#section-5.3.1
 * @param field name of the field to extract
 * @return NULL on error, otherwise the member from
 *        @a object. Note that the reference counter is
 *        NOT incremented.
 */
const json_t *
TALER_JSON_extract_i18n (const json_t *object,
                         const char *language_pattern,
                         const char *field);


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
