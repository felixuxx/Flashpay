/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016, 2021, 2022 Taler Systems SA

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
 * Details about an encrypted contract.
 */
struct TALER_EncryptedContract
{

  /**
   * Signature of the client affiming this encrypted contract.
   */
  struct TALER_PurseContractSignatureP econtract_sig;

  /**
   * Contract decryption key for the purse.
   */
  struct TALER_ContractDiffiePublicP contract_pub;

  /**
   * Encrypted contract, can be NULL.
   */
  void *econtract;

  /**
   * Number of bytes in @e econtract.
   */
  size_t econtract_size;


};


/**
 * Print JSON parsing related error information
 * @deprecated
 */
#define TALER_json_warn(error)                                         \
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,                                \
              "JSON parsing failed at %s:%u: %s (%s)\n",                  \
              __FILE__, __LINE__, error.text, error.source)


/**
 * Generate packer instruction for a JSON field of type
 * absolute time creating a human-readable timestamp.
 *
 * @param name name of the field to add to the object
 * @param at absolute time to pack
 * @return json pack specification
 */
struct GNUNET_JSON_PackSpec
TALER_JSON_pack_time_abs_human (const char *name,
                                struct GNUNET_TIME_Absolute at);


/**
 * Put an error code into a JSON reply, including
 * both the numeric value and the hint.
 *
 * @param ec error code to encode using canonical field names
 */
#define TALER_JSON_pack_ec(ec) \
  GNUNET_JSON_pack_string ("hint", TALER_ErrorCode_get_hint (ec)), \
  GNUNET_JSON_pack_uint64 ("code", ec)

/**
 * Generate packer instruction for a JSON field of type
 * absolute time creating a human-readable timestamp.
 *
 * @param name name of the field to add to the object
 * @param at absolute time to pack
 * @return json pack specification
 */
struct GNUNET_JSON_PackSpec
TALER_JSON_pack_time_abs_nbo_human (const char *name,
                                    struct GNUNET_TIME_AbsoluteNBO at);


/**
 * Generate packer instruction for a JSON field of type
 * denomination public key.
 *
 * @param name name of the field to add to the object
 * @param pk public key
 * @return json pack specification
 */
struct GNUNET_JSON_PackSpec
TALER_JSON_pack_denom_pub (
  const char *name,
  const struct TALER_DenominationPublicKey *pk);


/**
 * Generate packer instruction for a JSON field of type
 * denomination signature.
 *
 * @param name name of the field to add to the object
 * @param sig signature
 * @return json pack specification
 */
struct GNUNET_JSON_PackSpec
TALER_JSON_pack_denom_sig (
  const char *name,
  const struct TALER_DenominationSignature *sig);


/**
 * Generate packer instruction for a JSON field of type
 * blinded denomination signature (that needs to be
 * unblinded before it becomes valid).
 *
 * @param name name of the field to add to the object
 * @param sig signature
 * @return json pack specification
 */
struct GNUNET_JSON_PackSpec
TALER_JSON_pack_blinded_denom_sig (
  const char *name,
  const struct TALER_BlindedDenominationSignature *sig);


/**
 * Generate packer instruction for a JSON field of type
 * blinded planchet.
 *
 * @param name name of the field to add to the object
 * @param blinded_planchet blinded planchet
 * @return json pack specification
 */
struct GNUNET_JSON_PackSpec
TALER_JSON_pack_blinded_planchet (
  const char *name,
  const struct TALER_BlindedPlanchet *blinded_planchet);


/**
 * Generate packer instruction for a JSON field of type
 * exchange withdraw values (/csr).
 *
 * @param name name of the field to add to the object
 * @param ewv values to transmit
 * @return json pack specification
 */
struct GNUNET_JSON_PackSpec
TALER_JSON_pack_exchange_withdraw_values (
  const char *name,
  const struct TALER_ExchangeWithdrawValues *ewv);


/**
 * Generate packer instruction for a JSON field of type
 * amount.
 *
 * @param name name of the field to add to the object
 * @param amount valid amount to pack
 * @return json pack specification
 */
struct GNUNET_JSON_PackSpec
TALER_JSON_pack_amount (const char *name,
                        const struct TALER_Amount *amount);


/**
 * Generate packer instruction for a JSON field of type
 * amount.
 *
 * @param name name of the field to add to the object
 * @param amount valid amount to pack
 * @return json pack specification
 */
struct GNUNET_JSON_PackSpec
TALER_JSON_pack_amount_nbo (const char *name,
                            const struct TALER_AmountNBO *amount);


/**
 * Generate packer instruction for a JSON field of type
 * encrypted contract.
 *
 * @param name name of the field to add to the object
 * @param econtract the encrypted contract
 * @return json pack specification
 */
struct GNUNET_JSON_PackSpec
TALER_JSON_pack_econtract (
  const char *name,
  const struct TALER_EncryptedContract *econtract);

/**
 * Generate packer instruction for a JSON field of type age_commitment
 *
 * @param name name of the field to add to the object
 * @param age_commitment age commitment to add
 * @return json pack specification
 */
struct GNUNET_JSON_PackSpec
TALER_JSON_pack_age_commitment (
  const char *name,
  const struct TALER_AgeCommitment *age_commitment);


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
 * Provide specification to parse given JSON object to an encrypted contract.
 *
 * @param name name of the amount field in the JSON
 * @param[out] econtract where to store the encrypted contract
 * @return spec for parsing an amount
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_econtract (const char *name,
                           struct TALER_EncryptedContract *econtract);


/**
 * Provide specification to parse a given JSON object to an age commitment.
 *
 * @param name name of the age commitment field in the JSON
 * @param[out] age_commitment where to store the age commitment
 * @return spec for parsing an age commitment
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_age_commitment (const char *name,
                                struct TALER_AgeCommitment *age_commitment);

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
 * Generate specification to parse all fees for
 * a denomination under a prefix @a pfx.
 *
 * @param pfx string prefix to use
 * @param currency which currency to expect
 * @param[out] dfs a `struct TALER_DenomFeeSet` to initialize
 */
#define TALER_JSON_SPEC_DENOM_FEES(pfx,currency,dfs) \
  TALER_JSON_spec_amount (pfx "_withdraw", (currency), &(dfs)->withdraw), \
  TALER_JSON_spec_amount (pfx "_deposit", (currency), &(dfs)->deposit),   \
  TALER_JSON_spec_amount (pfx "_refresh", (currency), &(dfs)->refresh),   \
  TALER_JSON_spec_amount (pfx "_refund", (currency), &(dfs)->refund)


/**
 * Macro to pack all of a denominations' fees under
 * a given @a pfx.
 *
 * @param pfx string prefix to use
 * @param dfs a `struct TALER_DenomFeeSet` to pack
 */
#define TALER_JSON_PACK_DENOM_FEES(pfx, dfs) \
  TALER_JSON_pack_amount (pfx "_withdraw", &(dfs)->withdraw),   \
  TALER_JSON_pack_amount (pfx "_deposit", &(dfs)->deposit),     \
  TALER_JSON_pack_amount (pfx "_refresh", &(dfs)->refresh),     \
  TALER_JSON_pack_amount (pfx "_refund", &(dfs)->refund)


/**
 * Generate specification to parse all global fees.
 *
 * @param currency which currency to expect
 * @param[out] gfs a `struct TALER_GlobalFeeSet` to initialize
 */
#define TALER_JSON_SPEC_GLOBAL_FEES(currency,gfs) \
  TALER_JSON_spec_amount ("kyc_fee", (currency), &(gfs)->kyc), \
  TALER_JSON_spec_amount ("history_fee", (currency), &(gfs)->history),   \
  TALER_JSON_spec_amount ("account_fee", (currency), &(gfs)->account),   \
  TALER_JSON_spec_amount ("purse_fee", (currency), &(gfs)->purse)

/**
 * Macro to pack all of the global fees.
 *
 * @param gfs a `struct TALER_GlobalFeeSet` to pack
 */
#define TALER_JSON_PACK_GLOBAL_FEES(gfs) \
  TALER_JSON_pack_amount ("kyc_fee", &(gfs)->kyc),   \
  TALER_JSON_pack_amount ("history_fee", &(gfs)->history),     \
  TALER_JSON_pack_amount ("account_fee", &(gfs)->account),     \
  TALER_JSON_pack_amount ("purse_fee", &(gfs)->purse)

/**
 * Group of Denominations.  These are the common fields of an array of
 * denominations.
 *
 * The corresponding JSON-blob will also contain an array of particular
 * denominations with only the timestamps, cipher-specific public key and the
 * master signature.
 *
 **/
struct TALER_DenominationGroup
{
  enum TALER_DenominationCipher cipher;
  struct TALER_Amount value;
  struct TALER_DenomFeeSet fees;
  struct TALER_AgeMask age_mask;

  // hash is/should be the XOR of all SHA-512 hashes of the public keys in this
  // group
  struct GNUNET_HashCode hash;
};

/**
 * Generate a parser for a group of denominations.
 *
 * @param[in] field name of the field, maybe NULL
 * @param[in] currency name of the currency
 * @param[out] group denomination group information
 * @return corresponding field spec
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_denomination_group (const char *field,
                                    const char *currency,
                                    struct TALER_DenominationGroup *group);

/**
 * Generate line in parser specification for denomination public key.
 *
 * @param field name of the field
 * @param[out] pk key to initialize
 * @return corresponding field spec
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_denom_pub (const char *field,
                           struct TALER_DenominationPublicKey *pk);

/**
 * Generate a parser specification for a denomination public key of a given
 * cipher.
 *
 * @param field name of the field
 * @param cipher which cipher type to parse for
 * @param[out] pk key to fill
 * @return corresponding field spec
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_denom_pub_cipher (const char *field,
                                  const enum TALER_DenominationCipher cipher,
                                  struct TALER_DenominationPublicKey *pk);


/**
 * Generate line in parser specification for denomination signature.
 *
 * @param field name of the field
 * @param[out] sig the signature to initialize
 * @return corresponding field spec
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_denom_sig (const char *field,
                           struct TALER_DenominationSignature *sig);


/**
 * Generate line in parser specification for a
 * blinded denomination signature.
 *
 * @param field name of the field
 * @param[out] sig the blinded signature to initialize
 * @return corresponding field spec
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_blinded_denom_sig (
  const char *field,
  struct TALER_BlindedDenominationSignature *sig);


/**
 * Generate line in parser specification for
 * exchange withdraw values (/csr).
 *
 * @param field name of the field
 * @param[out] ewv the exchange withdraw values to initialize
 * @return corresponding field spec
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_exchange_withdraw_values (
  const char *field,
  struct TALER_ExchangeWithdrawValues *ewv);


/**
 * Generate line in parser specification for a
 * blinded planchet.
 *
 * @param field name of the field
 * @param[out] blinded_planchet the blinded planchet to initialize
 * @return corresponding field spec
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_blinded_planchet (const char *field,
                                  struct TALER_BlindedPlanchet *blinded_planchet);


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
                          struct TALER_PrivateContractHashP *hc);


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
enum GNUNET_GenericReturnValue
TALER_JSON_merchant_wire_signature_hash (const json_t *wire_s,
                                         struct TALER_MerchantWireHashP *hc);


/**
 * Check the signature in @a wire_s.  Also performs rudimentary
 * checks on the account data *if* supported.
 *
 * @param wire_s signed wire information of an exchange
 * @param master_pub master public key of the exchange
 * @return #GNUNET_OK if signature is valid
 */
enum GNUNET_GenericReturnValue
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
 * Check whether a given @a i18n object is wellformed.
 *
 * @param i18n object with internationalized content
 * @return true if @a i18n is well-formed
 */
bool
TALER_JSON_check_i18n (const json_t *i18n);


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


/**
 * Hash @a extensions in deposits.
 *
 * @param extensions contract extensions to hash
 * @param[out] ech where to write the extension hash
 */
void
TALER_deposit_extension_hash (const json_t *extensions,
                              struct TALER_ExtensionContractHashP *ech);

/**
 * Hash the @a config of an extension, given as JSON
 *
 * @param config configuration of the extension
 * @param[out] eh where to write the extension hash
 * @return GNUNET_OK on success, GNUNET_SYSERR on failure
 */
enum GNUNET_GenericReturnValue
TALER_JSON_extensions_config_hash (const json_t *config,
                                   struct TALER_ExtensionConfigHashP *eh);

/**
 * Canonicalize a JSON input to a string according to RFC 8785.
 */
char *
TALER_JSON_canonicalize (const json_t *input);

#endif /* TALER_JSON_LIB_H_ */

/* End of taler_json_lib.h */
