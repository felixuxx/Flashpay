/*
   This file is part of TALER
   Copyright (C) 2014-2023 Taler Systems SA

   TALER is free software; you can redistribute it and/or modify it under the
   terms of the GNU Affero General Public License as published by the Free Software
   Foundation; either version 3, or (at your option) any later version.

   TALER is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
   A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

   You should have received a copy of the GNU Affero General Public License along with
   TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
 */
/**
 * @file include/taler_exchange_service.h
 * @brief C interface of libtalerexchange, a C library to use exchange's HTTP API
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 * @author Özgür Kesim
 */
#ifndef _TALER_EXCHANGE_SERVICE_H
#define _TALER_EXCHANGE_SERVICE_H

#include <jansson.h>
#include "taler_util.h"
#include "taler_error_codes.h"
#include "taler_kyclogic_lib.h"
#include <gnunet/gnunet_curl_lib.h>


/* *********************  /keys *********************** */


/**
 * @brief Exchange's signature key
 */
struct TALER_EXCHANGE_SigningPublicKey
{
  /**
   * The signing public key
   */
  struct TALER_ExchangePublicKeyP key;

  /**
   * Signature over this signing key by the exchange's master signature.
   */
  struct TALER_MasterSignatureP master_sig;

  /**
   * Validity start time
   */
  struct GNUNET_TIME_Timestamp valid_from;

  /**
   * Validity expiration time (how long the exchange may use it).
   */
  struct GNUNET_TIME_Timestamp valid_until;

  /**
   * Validity expiration time for legal disputes.
   */
  struct GNUNET_TIME_Timestamp valid_legal;
};


/**
 * @brief Public information about a exchange's denomination key
 */
struct TALER_EXCHANGE_DenomPublicKey
{
  /**
   * The public key
   */
  struct TALER_DenominationPublicKey key;

  /**
   * The hash of the public key.
   */
  struct TALER_DenominationHashP h_key;

  /**
   * Exchange's master signature over this denomination record.
   */
  struct TALER_MasterSignatureP master_sig;

  /**
   * Timestamp indicating when the denomination key becomes valid
   */
  struct GNUNET_TIME_Timestamp valid_from;

  /**
   * Timestamp indicating when the denomination key can’t be used anymore to
   * withdraw new coins.
   */
  struct GNUNET_TIME_Timestamp withdraw_valid_until;

  /**
   * Timestamp indicating when coins of this denomination become invalid.
   */
  struct GNUNET_TIME_Timestamp expire_deposit;

  /**
   * When do signatures with this denomination key become invalid?
   * After this point, these signatures cannot be used in (legal)
   * disputes anymore, as the Exchange is then allowed to destroy its side
   * of the evidence.  @e expire_legal is expected to be significantly
   * larger than @e expire_deposit (by a year or more).
   */
  struct GNUNET_TIME_Timestamp expire_legal;

  /**
   * The value of this denomination
   */
  struct TALER_Amount value;

  /**
   * The applicable fees for this denomination
   */
  struct TALER_DenomFeeSet fees;

  /**
   * Set to true if this denomination key has been
   * revoked by the exchange.
   */
  bool revoked;

};


/**
 * Information we track per denomination audited by the auditor.
 */
struct TALER_EXCHANGE_AuditorDenominationInfo
{

  /**
   * Signature by the auditor affirming that it is monitoring this
   * denomination.
   */
  struct TALER_AuditorSignatureP auditor_sig;

  /**
   * Offsets into the key's main `denom_keys` array identifying the
   * denomination being audited by this auditor.
   */
  unsigned int denom_key_offset;

};


/**
 * @brief Information we get from the exchange about auditors.
 */
struct TALER_EXCHANGE_AuditorInformation
{
  /**
   * Public key of the auditing institution.  Wallets and merchants
   * are expected to be configured with a set of public keys of
   * auditors that they deem acceptable.  These public keys are
   * the roots of the Taler PKI.
   */
  struct TALER_AuditorPublicKeyP auditor_pub;

  /**
   * URL of the auditing institution.  Signed by the auditor's public
   * key, this URL is a place where applications can direct users for
   * additional information about the auditor.  In the future, there
   * should also be an auditor API for automated submission about
   * claims of misbehaving exchange providers.
   */
  char *auditor_url;

  /**
   * Array of length @a num_denom_keys with the denomination
   * keys audited by this auditor.
   */
  struct TALER_EXCHANGE_AuditorDenominationInfo *denom_keys;

  /**
   * Number of denomination keys audited by this auditor.
   */
  unsigned int num_denom_keys;
};


/**
 * Global fees and options of an exchange for a given time period.
 */
struct TALER_EXCHANGE_GlobalFee
{

  /**
   * Signature affirming all of the data.
   */
  struct TALER_MasterSignatureP master_sig;

  /**
   * Starting time of the validity period (inclusive).
   */
  struct GNUNET_TIME_Timestamp start_date;

  /**
   * End time of the validity period (exclusive).
   */
  struct GNUNET_TIME_Timestamp end_date;

  /**
   * Unmerged purses will be timed out after at most this time.
   */
  struct GNUNET_TIME_Relative purse_timeout;

  /**
   * Account history is limited to this timeframe.
   */
  struct GNUNET_TIME_Relative history_expiration;

  /**
   * Fees that apply globally, independent of denomination
   * and wire method.
   */
  struct TALER_GlobalFeeSet fees;

  /**
   * Number of free purses per account.
   */
  uint32_t purse_account_limit;
};


/**
 * @brief Information about keys from the exchange.
 */
struct TALER_EXCHANGE_Keys
{

  /**
   * Long-term offline signing key of the exchange.
   */
  struct TALER_MasterPublicKeyP master_pub;

  /**
   * Signature over extension configuration data, if any.
   */
  struct TALER_MasterSignatureP extensions_sig;

  /**
   * Array of the exchange's online signing keys.
   */
  struct TALER_EXCHANGE_SigningPublicKey *sign_keys;

  /**
   * Array of the exchange's denomination keys.
   */
  struct TALER_EXCHANGE_DenomPublicKey *denom_keys;

  /**
   * Array of the keys of the auditors of the exchange.
   */
  struct TALER_EXCHANGE_AuditorInformation *auditors;

  /**
   * Array with the global fees of the exchange.
   */
  struct TALER_EXCHANGE_GlobalFee *global_fees;

  /**
   * Configuration data for extensions.
   */
  json_t *extensions;

  /**
   * Supported Taler protocol version by the exchange.
   * String in the format current:revision:age using the
   * semantics of GNU libtool.  See
   * https://www.gnu.org/software/libtool/manual/html_node/Versioning.html#Versioning
   */
  char *version;

  /**
   * Supported currency of the exchange.
   */
  char *currency;

  /**
   * What is the base URL of the exchange that returned
   * these keys?
   */
  char *exchange_url;

  /**
   * Asset type used by the exchange. Typical values
   * are "fiat" or "crypto" or "regional" or "stock".
   * Wallets should adjust their UI/UX based on this
   * value.
   */
  char *asset_type;

  /**
   * Array of amounts a wallet is allowed to hold from
   * this exchange before it must undergo further KYC checks.
   */
  struct TALER_Amount *wallet_balance_limit_without_kyc;

  /**
   * How long after a reserve went idle will the exchange close it?
   * This is an approximate number, not cryptographically signed by
   * the exchange (advisory-only, may change anytime).
   */
  struct GNUNET_TIME_Relative reserve_closing_delay;

  /**
   * Timestamp indicating the /keys generation.
   */
  struct GNUNET_TIME_Timestamp list_issue_date;

  /**
   * When does this keys data expire?
   */
  struct GNUNET_TIME_Timestamp key_data_expiration;

  /**
   * Timestamp indicating the creation time of the last
   * denomination key in /keys.
   * Used to fetch /keys incrementally.
   */
  struct GNUNET_TIME_Timestamp last_denom_issue_date;

  /**
   * If age restriction is enabled on the exchange, we get an non-zero age_mask
   */
  struct TALER_AgeMask age_mask;

  /**
   * Length of the @e wallet_balance_limit_without_kyc
   * array.
   */
  unsigned int wblwk_length;

  /**
   * Length of the @e global_fees array.
   */
  unsigned int num_global_fees;

  /**
   * Length of the @e sign_keys array (number of valid entries).
   */
  unsigned int num_sign_keys;

  /**
   * Length of the @e denom_keys array.
   */
  unsigned int num_denom_keys;

  /**
   * Length of the @e auditors array.
   */
  unsigned int num_auditors;

  /**
   * Actual length of the @e auditors array (size of allocation).
   */
  unsigned int auditors_size;

  /**
   * Actual length of the @e denom_keys array (size of allocation).
   */
  unsigned int denom_keys_size;

  /**
   * Reference counter for this structure.
   * Freed when it reaches 0.
   */
  unsigned int rc;

  /**
   * Set to true if rewards are allowed at this exchange.
   */
  bool rewards_allowed;
};


/**
 * How compatible are the protocol version of the exchange and this
 * client?  The bits (1,2,4) can be used to test if the exchange's
 * version is incompatible, older or newer respectively.
 */
enum TALER_EXCHANGE_VersionCompatibility
{

  /**
   * The exchange runs exactly the same protocol version.
   */
  TALER_EXCHANGE_VC_MATCH = 0,

  /**
   * The exchange is too old or too new to be compatible with this
   * implementation (bit)
   */
  TALER_EXCHANGE_VC_INCOMPATIBLE = 1,

  /**
   * The exchange is older than this implementation (bit)
   */
  TALER_EXCHANGE_VC_OLDER = 2,

  /**
   * The exchange is too old to be compatible with
   * this implementation.
   */
  TALER_EXCHANGE_VC_INCOMPATIBLE_OUTDATED
    = TALER_EXCHANGE_VC_INCOMPATIBLE
      | TALER_EXCHANGE_VC_OLDER,

  /**
   * The exchange is more recent than this implementation (bit).
   */
  TALER_EXCHANGE_VC_NEWER = 4,

  /**
   * The exchange is too recent for this implementation.
   */
  TALER_EXCHANGE_VC_INCOMPATIBLE_NEWER
    = TALER_EXCHANGE_VC_INCOMPATIBLE
      | TALER_EXCHANGE_VC_NEWER,

  /**
   * We could not even parse the version data.
   */
  TALER_EXCHANGE_VC_PROTOCOL_ERROR = 8

};


/**
 * General information about the HTTP response we obtained
 * from the exchange for a request.
 */
struct TALER_EXCHANGE_HttpResponse
{

  /**
   * The complete JSON reply. NULL if we failed to parse the
   * reply (too big, invalid JSON).
   */
  const json_t *reply;

  /**
   * Set to the human-readable 'hint' that is optionally
   * provided by the exchange together with errors. NULL
   * if no hint was provided or if there was no error.
   */
  const char *hint;

  /**
   * HTTP status code for the response.  0 if the
   * HTTP request failed and we did not get any answer, or
   * if the answer was invalid and we set @a ec to a
   * client-side error code.
   */
  unsigned int http_status;

  /**
   * Taler error code.  #TALER_EC_NONE if everything was
   * OK.  Usually set to the "code" field of an error
   * response, but may be set to values created at the
   * client side, for example when the response was
   * not in JSON format or was otherwise ill-formed.
   */
  enum TALER_ErrorCode ec;

};


/**
 * Response from /keys.
 */
struct TALER_EXCHANGE_KeysResponse
{
  /**
   * HTTP response data
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details depending on the HTTP status code.
   */
  union
  {

    /**
     * Details on #MHD_HTTP_OK.
     */
    struct
    {
      /**
       * Information about the various keys used by the exchange.
       */
      const struct TALER_EXCHANGE_Keys *keys;

      /**
       * Protocol compatibility information
       */
      enum TALER_EXCHANGE_VersionCompatibility compat;
    } ok;
  } details;

};


/**
 * Function called with information about who is auditing
 * a particular exchange and what keys the exchange is using.
 * The ownership over the @a keys object is passed to
 * the callee, thus it is given explicitly and not
 * (only) via @a kr.
 *
 * @param cls closure
 * @param kr response from /keys
 * @param[in] keys keys object passed to callback with
 *  reference counter of 1. Must be freed by callee
 *  using #TALER_EXCHANGE_keys_decref(). NULL on failure.
 */
typedef void
(*TALER_EXCHANGE_GetKeysCallback) (
  void *cls,
  const struct TALER_EXCHANGE_KeysResponse *kr,
  struct TALER_EXCHANGE_Keys *keys);


/**
 * @brief Handle for a GET /keys request.
 */
struct TALER_EXCHANGE_GetKeysHandle;


/**
 * Fetch the main /keys resources from an exchange.  Does an incremental
 * fetch if @a last_keys is given.  The obtained information will be passed to
 * the @a cert_cb (possibly after first merging it with @a last_keys to
 * produce a full picture; expired keys (for deposit) will be removed from @a
 * last_keys if there are any).
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param[in,out] last_keys previous keys object, NULL for none
 * @param cert_cb function to call with the exchange's certification information,
 *                possibly called repeatedly if the information changes
 * @param cert_cb_cls closure for @a cert_cb
 * @return the exchange handle; NULL upon error
 */
struct TALER_EXCHANGE_GetKeysHandle *
TALER_EXCHANGE_get_keys (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *last_keys,
  TALER_EXCHANGE_GetKeysCallback cert_cb,
  void *cert_cb_cls);


/**
 * Serialize the latest data from @a keys to be persisted
 * (for example, to be used as @a last_keys later).
 *
 * @param kd the key data to serialize
 * @return NULL on error; otherwise JSON object owned by the caller
 */
json_t *
TALER_EXCHANGE_keys_to_json (const struct TALER_EXCHANGE_Keys *kd);


/**
 * Deserialize keys data stored in @a j.
 *
 * @param j JSON keys data previously returned from #TALER_EXCHANGE_keys_to_json()
 * @return NULL on error (i.e. invalid JSON); otherwise
 *         keys object with reference counter 1 owned by the caller
 */
struct TALER_EXCHANGE_Keys *
TALER_EXCHANGE_keys_from_json (const json_t *j);


/**
 * Cancel GET /keys operation.
 *
 * @param[in] gkh the GET /keys handle
 */
void
TALER_EXCHANGE_get_keys_cancel (struct TALER_EXCHANGE_GetKeysHandle *gkh);


/**
 * Increment reference counter for @a keys
 *
 * @param[in,out] keys object to increment reference counter for
 * @return keys, with incremented reference counter
 */
struct TALER_EXCHANGE_Keys *
TALER_EXCHANGE_keys_incref (struct TALER_EXCHANGE_Keys *keys);


/**
 * Deccrement reference counter for @a keys.
 * Frees @a keys if reference counter becomes zero.
 *
 * @param[in,out] keys object to decrement reference counter for
 */
void
TALER_EXCHANGE_keys_decref (struct TALER_EXCHANGE_Keys *keys);


/**
 * Test if the given @a pub is a the current signing key from the exchange
 * according to @a keys.
 *
 * @param keys the exchange's key set
 * @param pub claimed current online signing key for the exchange
 * @return #GNUNET_OK if @a pub is (according to /keys) a current signing key
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_test_signing_key (
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ExchangePublicKeyP *pub);


/**
 * Obtain the denomination key details from the exchange.
 *
 * @param keys the exchange's key set
 * @param pk public key of the denomination to lookup
 * @return details about the given denomination key, NULL if the key is not
 * found
 */
const struct TALER_EXCHANGE_DenomPublicKey *
TALER_EXCHANGE_get_denomination_key (
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_DenominationPublicKey *pk);


/**
 * Obtain the global fee details from the exchange.
 *
 * @param keys the exchange's key set
 * @param ts time for when to fetch the fees
 * @return details about the fees, NULL if no fees are known at @a ts
 */
const struct TALER_EXCHANGE_GlobalFee *
TALER_EXCHANGE_get_global_fee (
  const struct TALER_EXCHANGE_Keys *keys,
  struct GNUNET_TIME_Timestamp ts);


/**
 * Create a copy of a denomination public key.
 *
 * @param key key to copy
 * @returns a copy, must be freed with #TALER_EXCHANGE_destroy_denomination_key()
 * @deprecated
 */
struct TALER_EXCHANGE_DenomPublicKey *
TALER_EXCHANGE_copy_denomination_key (
  const struct TALER_EXCHANGE_DenomPublicKey *key);


/**
 * Destroy a denomination public key.
 * Should only be called with keys created by #TALER_EXCHANGE_copy_denomination_key().
 *
 * @param key key to destroy.
 * @deprecated
 */
void
TALER_EXCHANGE_destroy_denomination_key (
  struct TALER_EXCHANGE_DenomPublicKey *key);


/**
 * Obtain the denomination key details from the exchange.
 *
 * @param keys the exchange's key set
 * @param hc hash of the public key of the denomination to lookup
 * @return details about the given denomination key
 */
const struct TALER_EXCHANGE_DenomPublicKey *
TALER_EXCHANGE_get_denomination_key_by_hash (
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_DenominationHashP *hc);


/**
 * Obtain meta data about an exchange (online) signing
 * key.
 *
 * @param keys from where to obtain the meta data
 * @param exchange_pub public key to lookup
 * @return NULL on error (@a exchange_pub not known)
 */
const struct TALER_EXCHANGE_SigningPublicKey *
TALER_EXCHANGE_get_signing_key_info (
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ExchangePublicKeyP *exchange_pub);


/* *********************  /wire *********************** */


/**
 * List sorted by @a start_date with fees to be paid for aggregate wire transfers.
 */
struct TALER_EXCHANGE_WireAggregateFees
{
  /**
   * This is a linked list.
   */
  struct TALER_EXCHANGE_WireAggregateFees *next;

  /**
   * Fee to be paid whenever the exchange wires funds to the merchant.
   */
  struct TALER_WireFeeSet fees;

  /**
   * Time when this fee goes into effect (inclusive)
   */
  struct GNUNET_TIME_Timestamp start_date;

  /**
   * Time when this fee stops being in effect (exclusive).
   */
  struct GNUNET_TIME_Timestamp end_date;

  /**
   * Signature affirming the above fee structure.
   */
  struct TALER_MasterSignatureP master_sig;
};


/**
 * Information about wire fees by wire method.
 */
struct TALER_EXCHANGE_WireFeesByMethod
{
  /**
   * Wire method with the given @e fees.
   */
  const char *method;

  /**
   * Linked list of wire fees the exchange charges for
   * accounts of the wire @e method.
   */
  struct TALER_EXCHANGE_WireAggregateFees *fees_head;

};


/**
 * Type of an account restriction.
 */
enum TALER_EXCHANGE_AccountRestrictionType
{
  /**
   * Invalid restriction.
   */
  TALER_EXCHANGE_AR_INVALID = 0,

  /**
   * Account must not be used for this operation.
   */
  TALER_EXCHANGE_AR_DENY = 1,

  /**
   * Other account must match given regular expression.
   */
  TALER_EXCHANGE_AR_REGEX = 2
};

/**
 * Restrictions that apply to using a given exchange bank account.
 */
struct TALER_EXCHANGE_AccountRestriction
{

  /**
   * Type of the account restriction.
   */
  enum TALER_EXCHANGE_AccountRestrictionType type;

  /**
   * Restriction details depending on @e type.
   */
  union
  {
    /**
     * Details if type is #TALER_EXCHANGE_AR_REGEX.
     */
    struct
    {
      /**
       * Regular expression that the payto://-URI of the partner account must
       * follow.  The regular expression should follow posix-egrep, but
       * without support for character classes, GNU extensions,
       * back-references or intervals. See
       * https://www.gnu.org/software/findutils/manual/html_node/find_html/posix_002degrep-regular-expression-syntax.html
       * for a description of the posix-egrep syntax. Applications may support
       * regexes with additional features, but exchanges must not use such
       * regexes.
       */
      const char *posix_egrep;

      /**
       * Hint for a human to understand the restriction.
       */
      const char *human_hint;

      /**
       * Internationalizations for the @e human_hint.  Map from IETF BCP 47
       * language tax to localized human hints.
       */
      const json_t *human_hint_i18n;
    } regex;
  } details;

};


/**
 * Information about a wire account of the exchange.
 */
struct TALER_EXCHANGE_WireAccount
{
  /**
   * payto://-URI of the exchange.
   */
  const char *payto_uri;

  /**
   * URL of a conversion service in case using this account is subject to
   * currency conversion.  NULL for no conversion needed.
   */
  const char *conversion_url;

  /**
   * Array of restrictions that apply when crediting
   * this account.
   */
  struct TALER_EXCHANGE_AccountRestriction *credit_restrictions;

  /**
   * Array of restrictions that apply when debiting
   * this account.
   */
  struct TALER_EXCHANGE_AccountRestriction *debit_restrictions;

  /**
   * Length of the @e credit_restrictions array.
   */
  unsigned int credit_restrictions_length;

  /**
   * Length of the @e debit_restrictions array.
   */
  unsigned int debit_restrictions_length;

  /**
   * Signature of the exchange over the account (was checked by the API).
   */
  struct TALER_MasterSignatureP master_sig;

};


/**
 * Parse array of @a accounts of the exchange into @a was.
 *
 * @param master_pub master public key of the exchange, NULL to not verify signatures
 * @param accounts array of accounts to parse
 * @param[out] was where to write the result (already allocated)
 * @param was_length length of the @a was array, must match the length of @a accounts
 * @return #GNUNET_OK if parsing @a accounts succeeded
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_parse_accounts (
  const struct TALER_MasterPublicKeyP *master_pub,
  const json_t *accounts,
  unsigned int was_length,
  struct TALER_EXCHANGE_WireAccount was[static was_length]);


/**
 * Free data within @a was, but not @a was itself.
 *
 * @param was array of wire account data
 * @param was_len length of the @a was array
 */
void
TALER_EXCHANGE_free_accounts (
  unsigned int was_len,
  struct TALER_EXCHANGE_WireAccount was[static was_len]);


/**
 * Response to a /wire request.
 */
struct TALER_EXCHANGE_WireResponse
{
  /**
   * HTTP response details.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Response details depending on status.
   */
  union
  {

    /**
     * Details for #MHD_HTTP_OK.
     */
    struct
    {

      /**
       * Array of accounts of the exchange.
       */
      const struct TALER_EXCHANGE_WireAccount *accounts;

      /**
       * Array of wire fees by wire method.
       */
      const struct TALER_EXCHANGE_WireFeesByMethod *fees;

      /**
       * Length of @e accounts array.
       */
      unsigned int accounts_len;

      /**
       * Length of @e fees array.
       */
      unsigned int fees_len;

    } ok;

  } details;
};


/**
 * Callbacks of this type are used to serve the result of submitting a wire
 * format inquiry request to a exchange.
 *
 * If the request fails to generate a valid response from the
 * exchange, the http_status will also be zero.
 *
 * @param cls closure
 * @param wr response data
 */
typedef void
(*TALER_EXCHANGE_WireCallback) (
  void *cls,
  const struct TALER_EXCHANGE_WireResponse *wr);


/**
 * @brief A Wire format inquiry handle
 */
struct TALER_EXCHANGE_WireHandle;


/**
 * Obtain information about a exchange's wire instructions.  A
 * exchange may provide wire instructions for creating a reserve.  The
 * wire instructions also indicate which wire formats merchants may
 * use with the exchange.  This API is typically used by a wallet for
 * wiring funds, and possibly by a merchant to determine supported
 * wire formats.
 *
 * Note that while we return the (main) response verbatim to the
 * caller for further processing, we do already verify that the
 * response is well-formed (i.e. that signatures included in the
 * response are all valid).  If the exchange's reply is not
 * well-formed, we return an HTTP status code of zero to @a cb.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param keys the keys of the exchange
 * @param wire_cb the callback to call when a reply for this request is available
 * @param wire_cb_cls closure for the above callback
 * @return a handle for this request
 */
struct TALER_EXCHANGE_WireHandle *
TALER_EXCHANGE_wire (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  TALER_EXCHANGE_WireCallback wire_cb,
  void *wire_cb_cls);


/**
 * Cancel a wire information request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param wh the wire information request handle
 */
void
TALER_EXCHANGE_wire_cancel (struct TALER_EXCHANGE_WireHandle *wh);


/* *********************  /coins/$COIN_PUB/deposit *********************** */


/**
 * Information needed for a coin to be deposited.
 */
struct TALER_EXCHANGE_CoinDepositDetail
{

  /**
   * The amount to be deposited.
   */
  struct TALER_Amount amount;

  /**
   * Hash over the age commitment of the coin.
   */
  struct TALER_AgeCommitmentHash h_age_commitment;

  /**
   * The coin’s public key.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * The signature made with purpose #TALER_SIGNATURE_WALLET_COIN_DEPOSIT made
   * by the customer with the coin’s private key.
   */
  struct TALER_CoinSpendSignatureP coin_sig;

  /**
   * Exchange’s unblinded signature of the coin.
   */
  struct TALER_DenominationSignature denom_sig;

  /**
   * Hash of the public key of the coin.
   */
  struct TALER_DenominationHashP h_denom_pub;
};


/**
 * Meta information about the contract relevant for a coin's deposit
 * operation.
 */
struct TALER_EXCHANGE_DepositContractDetail
{

  /**
   * Execution date, until which the merchant would like the exchange to
   * settle the balance (advisory, the exchange cannot be forced to settle in
   * the past or upon very short notice, but of course a well-behaved exchange
   * will limit aggregation based on the advice received).
   */
  struct GNUNET_TIME_Timestamp wire_deadline;

  /**
   * The merchant’s account details, in the payto://-format supported by the
   * exchange.
   */
  const char *merchant_payto_uri;

  /**
   * Salt used to hash the @e merchant_payto_uri.
   */
  struct TALER_WireSaltP wire_salt;

  /**
   * Hash of the contact of the merchant with the customer (further details
   * are never disclosed to the exchange)
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Policy extension specific details about the deposit relevant to the exchange.
   */
  json_t *policy_details;

  /**
   * Timestamp when the contract was finalized, must match approximately the
   * current time of the exchange.
   */
  struct GNUNET_TIME_Timestamp timestamp;

  /**
   * The public key of the merchant (used to identify the merchant for refund
   * requests).
   */
  struct TALER_MerchantPublicKeyP merchant_pub;

  /**
   * Date until which the merchant can issue a refund to the customer via the
   * exchange (can be zero if refunds are not allowed); must not be after the
   * @e wire_deadline.
   */
  struct GNUNET_TIME_Timestamp refund_deadline;

};


/**
 * @brief A Batch Deposit Handle
 */
struct TALER_EXCHANGE_BatchDepositHandle;


/**
 * Structure with information about a batch deposit
 * operation's result.
 */
struct TALER_EXCHANGE_BatchDepositResult
{
  /**
   * HTTP response data
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  union
  {

    /**
     * Information returned if the HTTP status is
     * #MHD_HTTP_OK.
     */
    struct
    {
      /**
       * Time when the exchange generated the batch deposit confirmation
       */
      struct GNUNET_TIME_Timestamp deposit_timestamp;

      /**
       * Array of signatures provided by the exchange
       */
      const struct TALER_ExchangeSignatureP *exchange_sigs;

      /**
       * exchange key used to sign @a exchange_sig.
       */
      const struct TALER_ExchangePublicKeyP *exchange_pub;

      /**
       * Base URL for looking up wire transfers, or
       * NULL to use the default base URL.
       */
      const char *transaction_base_url;

      /**
       * Length of the @e exchange_sigs array.
       */
      unsigned int num_signatures;

    } ok;

    /**
     * Information returned if the HTTP status is
     * #MHD_HTTP_CONFLICT.
     */
    struct
    {
      /* TODO: returning full details is not implemented */
    } conflict;

  } details;
};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * deposit permission request to a exchange.
 *
 * @param cls closure
 * @param dr deposit response details
 */
typedef void
(*TALER_EXCHANGE_BatchDepositResultCallback) (
  void *cls,
  const struct TALER_EXCHANGE_BatchDepositResult *dr);


/**
 * Submit a batch of deposit permissions to the exchange and get the
 * exchange's response.  This API is typically used by a merchant.  Note that
 * while we return the response verbatim to the caller for further processing,
 * we do already verify that the response is well-formed (i.e. that signatures
 * included in the response are all valid).  If the exchange's reply is not
 * well-formed, we return an HTTP status code of zero to @a cb.
 *
 * We also verify that the @a cdds.coin_sig are valid for this deposit
 * request, and that the @a cdds.ub_sig are a valid signatures for @a
 * coin_pub.  Also, the @a exchange must be ready to operate (i.e.  have
 * finished processing the /keys reply).  If either check fails, we do
 * NOT initiate the transaction with the exchange and instead return NULL.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param keys exchange keys
 * @param dcd details about the contract the deposit is for
 * @param num_cdds length of the @a cdds array
 * @param cdds array with details about the coins to be deposited
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @param[out] ec if NULL is returned, set to the error code explaining why the operation failed
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_EXCHANGE_BatchDepositHandle *
TALER_EXCHANGE_batch_deposit (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_EXCHANGE_DepositContractDetail *dcd,
  unsigned int num_cdds,
  const struct TALER_EXCHANGE_CoinDepositDetail cdds[static num_cdds],
  TALER_EXCHANGE_BatchDepositResultCallback cb,
  void *cb_cls,
  enum TALER_ErrorCode *ec);


/**
 * Change the chance that our deposit confirmation will be given to the
 * auditor to 100%.
 *
 * @param[in,out] deposit the batch deposit permission request handle
 */
void
TALER_EXCHANGE_batch_deposit_force_dc (
  struct TALER_EXCHANGE_BatchDepositHandle *deposit);


/**
 * Cancel a batch deposit permission request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param[in] deposit the deposit permission request handle
 */
void
TALER_EXCHANGE_batch_deposit_cancel (
  struct TALER_EXCHANGE_BatchDepositHandle *deposit);


/* *********************  /coins/$COIN_PUB/refund *********************** */

/**
 * @brief A Refund Handle
 */
struct TALER_EXCHANGE_RefundHandle;

/**
 * Response from the /refund API.
 */
struct TALER_EXCHANGE_RefundResponse
{
  /**
   * HTTP response data
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Response details depending on the HTTP status code.
   */
  union
  {
    /**
     * Details on #MHD_HTTP_OK.
     */
    struct
    {
      /**
       * Exchange key used to sign.
       */
      struct TALER_ExchangePublicKeyP exchange_pub;

      /**
       * The actual signature
       */
      struct TALER_ExchangeSignatureP exchange_sig;
    } ok;
  } details;
};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * refund request to an exchange.
 *
 * @param cls closure
 * @param rr refund response
 */
typedef void
(*TALER_EXCHANGE_RefundCallback) (
  void *cls,
  const struct TALER_EXCHANGE_RefundResponse *rr);

/**
 * Submit a refund request to the exchange and get the exchange's response.
 * This API is used by a merchant.  Note that while we return the response
 * verbatim to the caller for further processing, we do already verify that
 * the response is well-formed (i.e. that signatures included in the response
 * are all valid).  If the exchange's reply is not well-formed, we return an
 * HTTP status code of zero to @a cb.
 *
 * The @a exchange must be ready to operate (i.e.  have
 * finished processing the /keys reply).  If this check fails, we do
 * NOT initiate the transaction with the exchange and instead return NULL.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param keys exchange keys
 * @param amount the amount to be refunded; must be larger than the refund fee
 *        (as that fee is still being subtracted), and smaller than the amount
 *        (with deposit fee) of the original deposit contribution of this coin
 * @param h_contract_terms hash of the contact of the merchant with the customer that is being refunded
 * @param coin_pub coin’s public key of the coin from the original deposit operation
 * @param rtransaction_id transaction id for the transaction between merchant and customer (of refunding operation);
 *                        this is needed as we may first do a partial refund and later a full refund.  If both
 *                        refunds are also over the same amount, we need the @a rtransaction_id to make the disjoint
 *                        refund requests different (as requests are idempotent and otherwise the 2nd refund might not work).
 * @param merchant_priv the private key of the merchant, used to generate signature for refund request
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_EXCHANGE_RefundHandle *
TALER_EXCHANGE_refund (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_Amount *amount,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  uint64_t rtransaction_id,
  const struct TALER_MerchantPrivateKeyP *merchant_priv,
  TALER_EXCHANGE_RefundCallback cb,
  void *cb_cls);


/**
 * Cancel a refund permission request.  This function cannot be used
 * on a request handle if a response is already served for it.  If
 * this function is called, the refund may or may not have happened.
 * However, it is fine to try to refund the coin a second time.
 *
 * @param refund the refund request handle
 */
void
TALER_EXCHANGE_refund_cancel (struct TALER_EXCHANGE_RefundHandle *refund);


/* ********************* POST /csr-melt *********************** */


/**
 * @brief A /csr-melt Handle
 */
struct TALER_EXCHANGE_CsRMeltHandle;


/**
 * Details about a response for a CS R request.
 */
struct TALER_EXCHANGE_CsRMeltResponse
{
  /**
   * HTTP response data.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details about the response.
   */
  union
  {
    /**
     * Details if the status is #MHD_HTTP_OK.
     */
    struct
    {
      /**
       * Length of the @e alg_values array.
       */
      unsigned int alg_values_len;

      /**
       * Values contributed by the exchange for the
       * respective coin's withdraw operation.
       */
      const struct TALER_ExchangeWithdrawValues *alg_values;
    } ok;

    /**
     * Details if the status is #MHD_HTTP_GONE.
     */
    struct
    {
      /* TODO: returning full details is not implemented */
    } gone;

  } details;
};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * CS R request to a exchange.
 *
 * @param cls closure
 * @param csrr response details
 */
typedef void
(*TALER_EXCHANGE_CsRMeltCallback) (
  void *cls,
  const struct TALER_EXCHANGE_CsRMeltResponse *csrr);


/**
 * Information we pass per coin to a /csr-melt request.
 */
struct TALER_EXCHANGE_NonceKey
{
  /**
   * Which denomination key is the /csr-melt request for?
   */
  const struct TALER_EXCHANGE_DenomPublicKey *pk;

  /**
   * What is number to derive the client nonce for the
   * fresh coin?
   */
  uint32_t cnc_num;
};


/**
 * Get a set of CS R values using a /csr-melt request.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param rms master key used for the derivation of the CS values
 * @param nks_len length of the @a nks array
 * @param nks array of denominations and nonces
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return handle for the operation on success, NULL on error, i.e.
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_CsRMeltHandle *
TALER_EXCHANGE_csr_melt (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_RefreshMasterSecretP *rms,
  unsigned int nks_len,
  struct TALER_EXCHANGE_NonceKey nks[static nks_len],
  TALER_EXCHANGE_CsRMeltCallback res_cb,
  void *res_cb_cls);


/**
 *
 * Cancel a CS R melt request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param csrh the withdraw handle
 */
void
TALER_EXCHANGE_csr_melt_cancel (struct TALER_EXCHANGE_CsRMeltHandle *csrh);


/* ********************* POST /csr-withdraw *********************** */


/**
 * @brief A /csr-withdraw Handle
 */
struct TALER_EXCHANGE_CsRWithdrawHandle;


/**
 * Details about a response for a CS R request.
 */
struct TALER_EXCHANGE_CsRWithdrawResponse
{
  /**
   * HTTP response data.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details about the response.
   */
  union
  {
    /**
     * Details if the status is #MHD_HTTP_OK.
     */
    struct
    {
      /**
       * Values contributed by the exchange for the
       * respective coin's withdraw operation.
       */
      struct TALER_ExchangeWithdrawValues alg_values;
    } ok;

    /**
     * Details if the status is #MHD_HTTP_GONE.
     */
    struct
    {
      /* TODO: returning full details is not implemented */
    } gone;

  } details;
};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * CS R withdraw request to a exchange.
 *
 * @param cls closure
 * @param csrr response details
 */
typedef void
(*TALER_EXCHANGE_CsRWithdrawCallback) (
  void *cls,
  const struct TALER_EXCHANGE_CsRWithdrawResponse *csrr);


/**
 * Get a CS R using a /csr-withdraw request.
 *
 * @param curl_ctx The curl context to use for the requests
 * @param exchange_url Base-URL to the excnange
 * @param pk Which denomination key is the /csr request for
 * @param nonce client nonce for the request
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return handle for the operation on success, NULL on error, i.e.
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_CsRWithdrawHandle *
TALER_EXCHANGE_csr_withdraw (
  struct GNUNET_CURL_Context *curl_ctx,
  const char *exchange_url,
  const struct TALER_EXCHANGE_DenomPublicKey *pk,
  const struct TALER_CsNonce *nonce,
  TALER_EXCHANGE_CsRWithdrawCallback res_cb,
  void *res_cb_cls);


/**
 *
 * Cancel a CS R withdraw request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param csrh the withdraw handle
 */
void
TALER_EXCHANGE_csr_withdraw_cancel (
  struct TALER_EXCHANGE_CsRWithdrawHandle *csrh);


/* ********************* GET /reserves/$RESERVE_PUB *********************** */

/**
 * Ways how a reserve's balance may change.
 */
enum TALER_EXCHANGE_ReserveTransactionType
{

  /**
   * Deposit into the reserve.
   */
  TALER_EXCHANGE_RTT_CREDIT,

  /**
   * Withdrawal from the reserve.
   */
  TALER_EXCHANGE_RTT_WITHDRAWAL,

  /**
   * /recoup operation.
   */
  TALER_EXCHANGE_RTT_RECOUP,

  /**
   * Reserve closed operation.
   */
  TALER_EXCHANGE_RTT_CLOSING,

  /**
   * Reserve history request.
   */
  TALER_EXCHANGE_RTT_HISTORY,

  /**
   * Reserve purse merge operation.
   */
  TALER_EXCHANGE_RTT_MERGE,

  /**
   * Reserve open request operation.
   */
  TALER_EXCHANGE_RTT_OPEN,

  /**
   * Reserve close request operation.
   */
  TALER_EXCHANGE_RTT_CLOSE

};


/**
 * @brief Entry in the reserve's transaction history.
 */
struct TALER_EXCHANGE_ReserveHistoryEntry
{

  /**
   * Type of the transaction.
   */
  enum TALER_EXCHANGE_ReserveTransactionType type;

  /**
   * Amount transferred (in or out).
   */
  struct TALER_Amount amount;

  /**
   * Details depending on @e type.
   */
  union
  {

    /**
     * Information about a deposit that filled this reserve.
     * @e type is #TALER_EXCHANGE_RTT_CREDIT.
     */
    struct
    {
      /**
       * Sender account payto://-URL of the incoming transfer.
       */
      char *sender_url;

      /**
       * Information that uniquely identifies the wire transfer.
       */
      uint64_t wire_reference;

      /**
       * When did the wire transfer happen?
       */
      struct GNUNET_TIME_Timestamp timestamp;

    } in_details;

    /**
     * Information about withdraw operation.
     * @e type is #TALER_EXCHANGE_RTT_WITHDRAWAL.
     */
    struct
    {
      /**
       * Signature authorizing the withdrawal for outgoing transaction.
       */
      json_t *out_authorization_sig;

      /**
       * Fee that was charged for the withdrawal.
       */
      struct TALER_Amount fee;
    } withdraw;

    /**
     * Information provided if the reserve was filled via /recoup.
     * @e type is #TALER_EXCHANGE_RTT_RECOUP.
     */
    struct
    {

      /**
       * Public key of the coin that was paid back.
       */
      struct TALER_CoinSpendPublicKeyP coin_pub;

      /**
       * Signature of the coin of type
       * #TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP.
       */
      struct TALER_ExchangeSignatureP exchange_sig;

      /**
       * Public key of the exchange that was used for @e exchange_sig.
       */
      struct TALER_ExchangePublicKeyP exchange_pub;

      /**
       * When did the /recoup operation happen?
       */
      struct GNUNET_TIME_Timestamp timestamp;

    } recoup_details;

    /**
     * Information about a close operation of the reserve.
     * @e type is #TALER_EXCHANGE_RTT_CLOSE.
     */
    struct
    {
      /**
       * Receiver account information for the outgoing wire transfer.
       */
      const char *receiver_account_details;

      /**
       * Wire transfer details for the outgoing wire transfer.
       */
      struct TALER_WireTransferIdentifierRawP wtid;

      /**
       * Signature of the coin of type
       * #TALER_SIGNATURE_EXCHANGE_RESERVE_CLOSED.
       */
      struct TALER_ExchangeSignatureP exchange_sig;

      /**
       * Public key of the exchange that was used for @e exchange_sig.
       */
      struct TALER_ExchangePublicKeyP exchange_pub;

      /**
       * When did the wire transfer happen?
       */
      struct GNUNET_TIME_Timestamp timestamp;

      /**
       * Fee that was charged for the closing.
       */
      struct TALER_Amount fee;

    } close_details;

    /**
     * Information about a history operation of the reserve.
     * @e type is #TALER_EXCHANGE_RTT_HISTORY.
     */
    struct
    {

      /**
       * When was the request made.
       */
      struct GNUNET_TIME_Timestamp request_timestamp;

      /**
       * Signature by the reserve approving the history request.
       */
      struct TALER_ReserveSignatureP reserve_sig;

    } history_details;

    /**
     * Information about a merge operation on the reserve.
     * @e type is #TALER_EXCHANGE_RTT_MERGE.
     */
    struct
    {

      /**
       * Fee paid for the purse.
       */
      struct TALER_Amount purse_fee;

      /**
       * Hash over the contract.
       */
      struct TALER_PrivateContractHashP h_contract_terms;

      /**
       * Merge capability key.
       */
      struct TALER_PurseMergePublicKeyP merge_pub;

      /**
       * Purse public key.
       */
      struct TALER_PurseContractPublicKeyP purse_pub;

      /**
       * Signature by the reserve approving the merge.
       */
      struct TALER_ReserveSignatureP reserve_sig;

      /**
       * When was the merge made.
       */
      struct GNUNET_TIME_Timestamp merge_timestamp;

      /**
       * When was the purse set to expire.
       */
      struct GNUNET_TIME_Timestamp purse_expiration;

      /**
       * Minimum age required for depositing into the purse.
       */
      uint32_t min_age;

      /**
       * Flags of the purse.
       */
      enum TALER_WalletAccountMergeFlags flags;

      /**
       * True if the purse was actually merged, false
       * if only the @e purse_fee was charged.
       */
      bool merged;

    } merge_details;

    /**
     * Information about an open request operation on the reserve.
     * @e type is #TALER_EXCHANGE_RTT_OPEN.
     */
    struct
    {

      /**
       * Signature by the reserve approving the open.
       */
      struct TALER_ReserveSignatureP reserve_sig;

      /**
       * Amount to be paid from the reserve balance to open
       * the reserve.
       */
      struct TALER_Amount reserve_payment;

      /**
       * When was the request created.
       */
      struct GNUNET_TIME_Timestamp request_timestamp;

      /**
       * For how long should the reserve be kept open.
       * (Determines amount to be paid.)
       */
      struct GNUNET_TIME_Timestamp reserve_expiration;

      /**
       * How many open purses should be included with the
       * open reserve?
       * (Determines amount to be paid.)
       */
      uint32_t purse_limit;

    } open_request;

    /**
     * Information about an close request operation on the reserve.
     * @e type is #TALER_EXCHANGE_RTT_CLOSE.
     */
    struct
    {

      /**
       * Signature by the reserve approving the close.
       */
      struct TALER_ReserveSignatureP reserve_sig;

      /**
       * When was the request created.
       */
      struct GNUNET_TIME_Timestamp request_timestamp;

      /**
       * Hash of the payto://-URI of the target account
       * for the closure, or all zeros for the reserve
       * origin account.
       */
      struct TALER_PaytoHashP target_account_h_payto;

    } close_request;


  } details;

};


/**
 * @brief A /reserves/ GET Handle
 */
struct TALER_EXCHANGE_ReservesGetHandle;


/**
 * @brief Reserve summary.
 */
struct TALER_EXCHANGE_ReserveSummary
{

  /**
   * High-level HTTP response details.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details depending on @e hr.http_status.
   */
  union
  {

    /**
     * Information returned on success, if
     * @e hr.http_status is #MHD_HTTP_OK
     */
    struct
    {

      /**
       * Reserve balance.
       */
      struct TALER_Amount balance;

    } ok;

  } details;

};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * reserve status request to a exchange.
 *
 * @param cls closure
 * @param rs HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ReservesGetCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ReserveSummary *rs);


/**
 * Submit a request to obtain the transaction history of a reserve
 * from the exchange.  Note that while we return the full response to the
 * caller for further processing, we do already verify that the
 * response is well-formed (i.e. that signatures included in the
 * response are all valid and add up to the balance).  If the exchange's
 * reply is not well-formed, we return an HTTP status code of zero to
 * @a cb.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param reserve_pub public key of the reserve to inspect
 * @param timeout how long to wait for an affirmative reply
 *        (enables long polling if the reserve does not yet exist)
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_EXCHANGE_ReservesGetHandle *
TALER_EXCHANGE_reserves_get (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct GNUNET_TIME_Relative timeout,
  TALER_EXCHANGE_ReservesGetCallback cb,
  void *cb_cls);


/**
 * Cancel a reserve GET request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param rgh the reserve request handle
 */
void
TALER_EXCHANGE_reserves_get_cancel (
  struct TALER_EXCHANGE_ReservesGetHandle *rgh);


/**
 * @brief A /reserves/$RID/status Handle
 */
struct TALER_EXCHANGE_ReservesStatusHandle;


/**
 * @brief Reserve status details.
 */
struct TALER_EXCHANGE_ReserveStatus
{

  /**
   * High-level HTTP response details.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details depending on @e hr.http_status.
   */
  union
  {

    /**
     * Information returned on success, if
     * @e hr.http_status is #MHD_HTTP_OK
     */
    struct
    {

      /**
       * Current reserve balance.  May not be the difference between
       * @e total_in and @e total_out because the @e may be truncated.
       */
      struct TALER_Amount balance;

      /**
       * Total of all inbound transactions in @e history.
       */
      struct TALER_Amount total_in;

      /**
       * Total of all outbound transactions in @e history.
       */
      struct TALER_Amount total_out;

      /**
       * Reserve history.
       */
      const struct TALER_EXCHANGE_ReserveHistoryEntry *history;

      /**
       * Length of the @e history array.
       */
      unsigned int history_len;

    } ok;

  } details;

};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * reserve status request to a exchange.
 *
 * @param cls closure
 * @param rs HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ReservesStatusCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ReserveStatus *rs);


/**
 * Submit a request to obtain the reserve status.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param keys exchange keys
 * @param reserve_priv private key of the reserve to inspect
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_EXCHANGE_ReservesStatusHandle *
TALER_EXCHANGE_reserves_status (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  TALER_EXCHANGE_ReservesStatusCallback cb,
  void *cb_cls);


/**
 * Cancel a reserve status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param rsh the reserve request handle
 */
void
TALER_EXCHANGE_reserves_status_cancel (
  struct TALER_EXCHANGE_ReservesStatusHandle *rsh);


/**
 * @brief A /reserves/$RID/history Handle
 */
struct TALER_EXCHANGE_ReservesHistoryHandle;


/**
 * @brief Reserve history details.
 */
struct TALER_EXCHANGE_ReserveHistory
{

  /**
   * High-level HTTP response details.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Timestamp of when we made the history request
   * (client-side).
   */
  struct GNUNET_TIME_Timestamp ts;

  /**
   * Reserve signature affirming the history request
   * (generated as part of the request).
   */
  const struct TALER_ReserveSignatureP *reserve_sig;

  /**
   * Details depending on @e hr.http_status.
   */
  union
  {

    /**
     * Information returned on success, if
     * @e hr.http_status is #MHD_HTTP_OK
     */
    struct
    {

      /**
       * Reserve balance. May not be the difference between
       * @e total_in and @e total_out because the @e may be truncated
       * due to expiration.
       */
      struct TALER_Amount balance;

      /**
       * Total of all inbound transactions in @e history.
       */
      struct TALER_Amount total_in;

      /**
       * Total of all outbound transactions in @e history.
       */
      struct TALER_Amount total_out;

      /**
       * Reserve history.
       */
      const struct TALER_EXCHANGE_ReserveHistoryEntry *history;

      /**
       * Length of the @e history array.
       */
      unsigned int history_len;

    } ok;

  } details;

};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * reserve history request to a exchange.
 *
 * @param cls closure
 * @param rs HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ReservesHistoryCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ReserveHistory *rs);


/**
 * Submit a request to obtain the reserve history.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param keys exchange keys
 * @param reserve_priv private key of the reserve to inspect
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_EXCHANGE_ReservesHistoryHandle *
TALER_EXCHANGE_reserves_history (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  TALER_EXCHANGE_ReservesHistoryCallback cb,
  void *cb_cls);


/**
 * Cancel a reserve history request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param rsh the reserve request handle
 */
void
TALER_EXCHANGE_reserves_history_cancel (
  struct TALER_EXCHANGE_ReservesHistoryHandle *rsh);


/* ********************* POST /reserves/$RESERVE_PUB/withdraw *********************** */


/**
 * @brief A /reserves/$RESERVE_PUB/withdraw Handle
 */
struct TALER_EXCHANGE_WithdrawHandle;


/**
 * Information input into the withdraw process per coin.
 */
struct TALER_EXCHANGE_WithdrawCoinInput
{
  /**
   * Denomination of the coin.
   */
  const struct TALER_EXCHANGE_DenomPublicKey *pk;

  /**
   * Master key material for the coin.
   */
  const struct TALER_PlanchetMasterSecretP *ps;

  /**
   * Age commitment for the coin.
   */
  const struct TALER_AgeCommitmentHash *ach;

};


/**
 * All the details about a coin that are generated during withdrawal and that
 * may be needed for future operations on the coin.
 */
struct TALER_EXCHANGE_PrivateCoinDetails
{
  /**
   * Private key of the coin.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Value used to blind the key for the signature.
   * Needed for recoup operations.
   */
  union TALER_DenominationBlindingKeyP bks;

  /**
   * Signature over the coin.
   */
  struct TALER_DenominationSignature sig;

  /**
   * Values contributed from the exchange during the
   * withdraw protocol.
   */
  struct TALER_ExchangeWithdrawValues exchange_vals;
};


/**
 * Details about a response for a withdraw request.
 */
struct TALER_EXCHANGE_WithdrawResponse
{
  /**
   * HTTP response data.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details about the response.
   */
  union
  {
    /**
     * Details if the status is #MHD_HTTP_OK.
     */
    struct TALER_EXCHANGE_PrivateCoinDetails ok;

    /**
     * Details if the status is #MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS.
     */
    struct
    {
      /**
       * Requirement row that the merchant should use
       * to check for its KYC status.
       */
      uint64_t requirement_row;

      /**
       * Hash of the payto-URI of the account to KYC;
       */
      struct TALER_PaytoHashP h_payto;

    } unavailable_for_legal_reasons;

    /**
     * Details if the status is #MHD_HTTP_CONFLICT.
     */
    struct
    {
      /* TODO: returning full details is not implemented */
    } conflict;

    /**
     * Details if the status is #MHD_HTTP_GONE.
     */
    struct
    {
      /* TODO: returning full details is not implemented */
    } gone;

  } details;
};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * withdraw request to a exchange.
 *
 * @param cls closure
 * @param wr response details
 */
typedef void
(*TALER_EXCHANGE_WithdrawCallback) (
  void *cls,
  const struct TALER_EXCHANGE_WithdrawResponse *wr);


/**
 * Withdraw a coin from the exchange using a /reserves/$RESERVE_PUB/withdraw
 * request.  This API is typically used by a wallet to withdraw from a
 * reserve.
 *
 * Note that to ensure that no money is lost in case of hardware
 * failures, the caller must have committed (most of) the arguments to
 * disk before calling, and be ready to repeat the request with the
 * same arguments in case of failures.
 *
 * @param curl_ctx The curl context to use
 * @param exchange_url The base-URL of the exchange
 * @param keys The /keys material from the exchange
 * @param reserve_priv private key of the reserve to withdraw from
 * @param wci inputs that determine the planchet
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for @a res_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_WithdrawHandle *
TALER_EXCHANGE_withdraw (
  struct GNUNET_CURL_Context *curl_ctx,
  const char *exchange_url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  const struct TALER_EXCHANGE_WithdrawCoinInput *wci,
  TALER_EXCHANGE_WithdrawCallback res_cb,
  void *res_cb_cls);


/**
 * Cancel a withdraw status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param wh the withdraw handle
 */
void
TALER_EXCHANGE_withdraw_cancel (struct TALER_EXCHANGE_WithdrawHandle *wh);


/**
 * @brief A /reserves/$RESERVE_PUB/batch-withdraw Handle
 */
struct TALER_EXCHANGE_BatchWithdrawHandle;


/**
 * Details about a response for a batch withdraw request.
 */
struct TALER_EXCHANGE_BatchWithdrawResponse
{
  /**
   * HTTP response data.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details about the response.
   */
  union
  {
    /**
     * Details if the status is #MHD_HTTP_OK.
     */
    struct
    {

      /**
       * Array of coins returned by the batch withdraw operation.
       */
      struct TALER_EXCHANGE_PrivateCoinDetails *coins;

      /**
       * Length of the @e coins array.
       */
      unsigned int num_coins;
    } ok;

    /**
     * Details if the status is #MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS.
     */
    struct
    {

      /**
       * Hash of the payto-URI of the account to KYC;
       */
      struct TALER_PaytoHashP h_payto;

      /**
       * Legitimization requirement that the merchant should use
       * to check for its KYC status, 0 if not known.
       */
      uint64_t requirement_row;
    } unavailable_for_legal_reasons;

    /**
     * Details if the status is #MHD_HTTP_CONFLICT.
     */
    struct
    {
      /* TODO: returning full details is not implemented */
    } conflict;

    /**
     * Details if the status is #MHD_HTTP_GONE.
     */
    struct
    {
      /* TODO: returning full details is not implemented */
    } gone;

  } details;
};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * batch withdraw request to a exchange.
 *
 * @param cls closure
 * @param wr response details
 */
typedef void
(*TALER_EXCHANGE_BatchWithdrawCallback) (
  void *cls,
  const struct TALER_EXCHANGE_BatchWithdrawResponse *wr);


/**
 * Withdraw multiple coins from the exchange using a /reserves/$RESERVE_PUB/batch-withdraw
 * request.  This API is typically used by a wallet to withdraw many coins from a
 * reserve.
 *
 * Note that to ensure that no money is lost in case of hardware
 * failures, the caller must have committed (most of) the arguments to
 * disk before calling, and be ready to repeat the request with the
 * same arguments in case of failures.
 *
 * @param curl_ctx The curl context to use
 * @param exchange_url The base-URL of the exchange
 * @param keys The /keys material from the exchange
 * @param reserve_priv private key of the reserve to withdraw from
 * @param wci_length number of entries in @a wcis
 * @param wcis inputs that determine the planchets
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for @a res_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_BatchWithdrawHandle *
TALER_EXCHANGE_batch_withdraw (
  struct GNUNET_CURL_Context *curl_ctx,
  const char *exchange_url,
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  unsigned int wci_length,
  const struct TALER_EXCHANGE_WithdrawCoinInput wcis[static wci_length],
  TALER_EXCHANGE_BatchWithdrawCallback res_cb,
  void *res_cb_cls);


/**
 * Cancel a batch withdraw status request.  This function cannot be used on a
 * request handle if a response is already served for it.
 *
 * @param wh the batch withdraw handle
 */
void
TALER_EXCHANGE_batch_withdraw_cancel (
  struct TALER_EXCHANGE_BatchWithdrawHandle *wh);


/**
 * Response from a withdraw2 request.
 */
struct TALER_EXCHANGE_Withdraw2Response
{
  /**
   * HTTP response data
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Response details depending on the HTTP status.
   */
  union
  {
    /**
     * Details if HTTP status is #MHD_HTTP_OK.
     */
    struct
    {
      /**
       * blind signature over the coin
       */
      struct TALER_BlindedDenominationSignature blind_sig;
    } ok;
  } details;

};

/**
 * Callbacks of this type are used to serve the result of submitting a
 * withdraw request to a exchange without the (un)blinding factor.
 *
 * @param cls closure
 * @param w2r response data
 */
typedef void
(*TALER_EXCHANGE_Withdraw2Callback) (
  void *cls,
  const struct TALER_EXCHANGE_Withdraw2Response *w2r);


/**
 * @brief A /reserves/$RESERVE_PUB/withdraw Handle, 2nd variant.
 * This variant does not do the blinding/unblinding and only
 * fetches the blind signature on the already blinded planchet.
 * Used internally by the `struct TALER_EXCHANGE_WithdrawHandle`
 * implementation as well as for the tipping logic of merchants.
 */
struct TALER_EXCHANGE_Withdraw2Handle;


/**
 * Withdraw a coin from the exchange using a /reserves/$RESERVE_PUB/withdraw
 * request.  This API is typically used by a merchant to withdraw a tip
 * where the blinding factor is unknown to the merchant.
 *
 * Note that to ensure that no money is lost in case of hardware
 * failures, the caller must have committed (most of) the arguments to
 * disk before calling, and be ready to repeat the request with the
 * same arguments in case of failures.
 *
 * @param curl_ctx The curl-context to use
 * @param exchange_url The base-URL of the exchange
 * @param keys The /keys material from the exchange
 * @param pd planchet details of the planchet to withdraw
 * @param reserve_priv private key of the reserve to withdraw from
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for @a res_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_Withdraw2Handle *
TALER_EXCHANGE_withdraw2 (
  struct GNUNET_CURL_Context *curl_ctx,
  const char *exchange_url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_PlanchetDetail *pd,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  TALER_EXCHANGE_Withdraw2Callback res_cb,
  void *res_cb_cls);


/**
 * Cancel a withdraw status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param wh the withdraw handle
 */
void
TALER_EXCHANGE_withdraw2_cancel (struct TALER_EXCHANGE_Withdraw2Handle *wh);


/**
 * Response from a batch-withdraw request (2nd variant).
 */
struct TALER_EXCHANGE_BatchWithdraw2Response
{
  /**
   * HTTP response data
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Response details depending on the HTTP status.
   */
  union
  {
    /**
     * Details if HTTP status is #MHD_HTTP_OK.
     */
    struct
    {
      /**
       * array of blind signatures over the coins.
       */
      const struct TALER_BlindedDenominationSignature *blind_sigs;

      /**
       * length of @e blind_sigs
       */
      unsigned int blind_sigs_length;

    } ok;
  } details;

};


/**
 * Callbacks of this type are used to serve the result of submitting a batch
 * withdraw request to a exchange without the (un)blinding factor.
 *
 * @param cls closure
 * @param bw2r response data
 */
typedef void
(*TALER_EXCHANGE_BatchWithdraw2Callback) (
  void *cls,
  const struct TALER_EXCHANGE_BatchWithdraw2Response *bw2r);


/**
 * @brief A /reserves/$RESERVE_PUB/batch-withdraw Handle, 2nd variant.
 * This variant does not do the blinding/unblinding and only
 * fetches the blind signatures on the already blinded planchets.
 * Used internally by the `struct TALER_EXCHANGE_BatchWithdrawHandle`
 * implementation as well as for the tipping logic of merchants.
 */
struct TALER_EXCHANGE_BatchWithdraw2Handle;


/**
 * Withdraw a coin from the exchange using a /reserves/$RESERVE_PUB/batch-withdraw
 * request.  This API is typically used by a merchant to withdraw a tip
 * where the blinding factor is unknown to the merchant.
 *
 * Note that to ensure that no money is lost in case of hardware
 * failures, the caller must have committed (most of) the arguments to
 * disk before calling, and be ready to repeat the request with the
 * same arguments in case of failures.
 *
 * @param curl_ctx The curl context to use
 * @param exchange_url The base-URL of the exchange
 * @param keys The /keys material from the exchange
 * @param pds array of planchet details of the planchet to withdraw
 * @param pds_length number of entries in the @a pds array
 * @param reserve_priv private key of the reserve to withdraw from
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for @a res_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_BatchWithdraw2Handle *
TALER_EXCHANGE_batch_withdraw2 (
  struct GNUNET_CURL_Context *curl_ctx,
  const char *exchange_url,
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  unsigned int pds_length,
  const struct TALER_PlanchetDetail pds[static pds_length],
  TALER_EXCHANGE_BatchWithdraw2Callback res_cb,
  void *res_cb_cls);


/**
 * Cancel a batch withdraw request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param wh the withdraw handle
 */
void
TALER_EXCHANGE_batch_withdraw2_cancel (
  struct TALER_EXCHANGE_BatchWithdraw2Handle *wh);


/* ********************* /reserve/$RESERVE_PUB/age-withdraw *************** */

/**
 * @brief Information needed to withdraw (and reveal) age restricted coins.
 */
struct TALER_EXCHANGE_AgeWithdrawCoinInput
{
  /**
   * The master secret from which we derive all other relevant values for
   * the coin: private key, nonces (if applicable) and age restriction
   */
  const struct TALER_PlanchetMasterSecretP secrets[TALER_CNC_KAPPA];

  /**
   * The denomination of the coin.  Must support age restriction, i.e
   * its .keys.age_mask MUST not be 0
   */
  const struct TALER_EXCHANGE_DenomPublicKey *denom_pub;
};

/**
 * @brief A handle to a /reserves/$RESERVE_PUB/age-withdraw request
 */
struct TALER_EXCHANGE_AgeWithdrawHandle;

/**
 * @brief Details about the response for a age withdraw request.
 */
struct TALER_EXCHANGE_AgeWithdrawResponse
{
  /**
   * HTTP response data.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details about the response
   */
  union
  {
    /**
     * Details if the status is #MHD_HTTP_OK.
     */
    struct
    {
      /**
       * Index that should not be revealed during the age-withdraw reveal phase.
       * The struct TALER_PlanchetMasterSecretP * from the request
       * with this index are the ones to keep.
       */
      uint8_t noreveal_index;

      /**
       * The commitment of the call to /age-withdraw
       */
      struct TALER_AgeWithdrawCommitmentHashP h_commitment;

      /**
       * Signature of the exchange over the origina TALER_AgeWithdrawRequestPS
       */
      struct TALER_ExchangeSignatureP exchange_sig;

      /**
       * Key used by the exchange for @e exchange_sig
       */
      struct TALER_ExchangePublicKeyP exchange_pub;

    } ok;
    /* FIXME[oec]: error cases */
  } details;
};

typedef void
(*TALER_EXCHANGE_AgeWithdrawCallback)(
  void *cls,
  const struct TALER_EXCHANGE_AgeWithdrawResponse *awr);

/**
 * Submit an age-withdraw request to the exchange and get the exchange's
 * response.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, the provided
 * argument @a rd should be committed to persistent storage
 * prior to calling this function.
 *
 * @param curl_ctx The curl context
 * @param exchange_url The base url of the exchange
 * @param keys The denomination keys from the exchange
 * @param reserve_priv The pivate key to the reserve
 * @param num_coins The number of elements in @e coin_inputs
 * @param coin_inputs The input for the coins to withdraw
 * @param max_age The maximum age we commit to.
 * @param res_cb A callback for the result, maybe NULL
 * @param res_cb_cls A closure for @e res_cb, maybe NULL
 * @return a handle for this request; NULL if the argument was invalid.
 *         In this case, the callback will not be called.
 */
struct TALER_EXCHANGE_AgeWithdrawHandle *
TALER_EXCHANGE_age_withdraw (
  struct GNUNET_CURL_Context *curl_ctx,
  const char *exchange_url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  size_t num_coins,
  const struct TALER_EXCHANGE_AgeWithdrawCoinInput coin_inputs[static
                                                               num_coins],
  uint8_t max_age,
  TALER_EXCHANGE_AgeWithdrawCallback res_cb,
  void *res_cb_cls);

/**
 * Cancel a age-withdraw request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param awh the age-withdraw handle
 */
void
TALER_EXCHANGE_age_withdraw_cancel (
  struct TALER_EXCHANGE_AgeWithdrawHandle *awh);


/* ********************* /age-withdraw/$ACH/reveal ************************ */

/**
 * @brief A handle to a /age-withdraw/$ACH/reveal request
 */
struct TALER_EXCHANGE_AgeWithdrawRevealHandle;


/**
 *
 */

struct TALER_EXCHANGE_AgeWithdrawRevealResponse
{
  /**
   * HTTP response data.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details about the response
   */
  union
  {
    /**
     * Details if the status is #MHD_HTTP_OK.
     */
    struct
    {
      /**
       * Number of coins returned.
       */
      unsigned int num_coins;

      /**
       * Array of @e num_coins values about the coins obtained via the reveal
       * operation.  The array give thes coins in the same order (and should
       * have the same length) in which the original age-withdraw request
       * specified the respective denomination keys.
       */
      const struct TALER_EXCHANGE_RevealedCoinInfo *coins;

    } ok;
    /* FIXME[oec]: error cases */
  } details;

};

typedef void
(*TALER_EXCHANGE_AgeWithdrawRevealCallback)(
  void *cls,
  const struct TALER_EXCHANGE_AgeWithdrawRevealResponse *awr);

/**
 * Submit an age-withdraw-reveal request to the exchange and get the exchange's
 * response.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, the provided
 * argument @a rd should be committed to persistent storage
 * prior to calling this function.
 *
 * @param curl_ctx The curl context
 * @param exchange_url The base url of the exchange
 * @param reserve_priv The pivate key to the reserve
 * @param num_coins The number of elements in @e coin_inputs
 * @param coins_input The input for the coins to withdraw
 * @param noreveal_index The index into each of the kappa coin candidates, that should not be revealed to the exchange
 * @param h_commitment The commmitment from the previous call to /age-withdraw
 * @param res_cb A callback for the result, maybe NULL
 * @param res_cb_cls A closure for @e res_cb, maybe NULL
 * @return a handle for this request; NULL if the argument was invalid.
 *         In this case, the callback will not be called.
 */
struct TALER_EXCHANGE_AgeWithdrawRevealHandle *
TALER_EXCHANGE_age_withdraw_reveal (
  struct GNUNET_CURL_Context *curl_ctx,
  const char *exchange_url,
  size_t num_coins,
  const struct TALER_EXCHANGE_AgeWithdrawCoinInput coins_input[static
                                                               num_coins],
  uint8_t noreveal_index,
  const struct TALER_AgeWithdrawCommitmentHashP *h_commitment,
  TALER_EXCHANGE_AgeWithdrawRevealCallback res_cb,
  void *res_cb_cls);


/**
 * @brief Cancel an age-withdraw-reveal request
 *
 * @param awrh Handle to an age-withdraw-reqveal request
 */
void
TALER_EXCHANGE_age_withdraw_reveal_cancel (
  struct TALER_EXCHANGE_AgeWithdrawRevealHandle *awrh);


/* ********************* /refresh/melt+reveal ***************************** */


/**
 * Information needed to melt (partially spent) coins to obtain fresh coins
 * that are unlinkable to the original coin(s).  Note that melting more than
 * one coin in a single request will make those coins linkable, so we only melt one coin at a time.
 */
struct TALER_EXCHANGE_RefreshData
{
  /**
   * private key of the coin to melt
   */
  struct TALER_CoinSpendPrivateKeyP melt_priv;

  /*
   * age commitment and proof and its hash that went into the original coin,
   * might be NULL.
   */
  const struct TALER_AgeCommitmentProof *melt_age_commitment_proof;
  const struct TALER_AgeCommitmentHash *melt_h_age_commitment;

  /**
   * amount specifying how much the coin will contribute to the melt
   * (including fee)
   */
  struct TALER_Amount melt_amount;

  /**
   * signatures affirming the validity of the public keys corresponding to the
   * @e melt_priv private key
   */
  struct TALER_DenominationSignature melt_sig;

  /**
   * denomination key information record corresponding to the @e melt_sig
   * validity of the keys
   */
  struct TALER_EXCHANGE_DenomPublicKey melt_pk;

  /**
   * array of @e pks_len denominations of fresh coins to create
   */
  const struct TALER_EXCHANGE_DenomPublicKey *fresh_pks;

  /**
   * length of the @e pks array
   */
  unsigned int fresh_pks_len;
};


/* ********************* /coins/$COIN_PUB/melt ***************************** */

/**
 * @brief A /coins/$COIN_PUB/melt Handle
 */
struct TALER_EXCHANGE_MeltHandle;


/**
 * Information we obtain per coin during melting.
 */
struct TALER_EXCHANGE_MeltBlindingDetail
{
  /**
   * Exchange values contributed to the refresh operation
   */
  struct TALER_ExchangeWithdrawValues alg_value;

};


/**
 * Response returned to a /melt request.
 */
struct TALER_EXCHANGE_MeltResponse
{
  /**
   * Full HTTP response details.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Parsed response details, variant depending on the
   * @e hr.http_status.
   */
  union
  {
    /**
     * Results for status #MHD_HTTP_OK.
     */
    struct
    {

      /**
       * Information returned per coin.
       */
      const struct TALER_EXCHANGE_MeltBlindingDetail *mbds;

      /**
       * Key used by the exchange to sign the response.
       */
      struct TALER_ExchangePublicKeyP sign_key;

      /**
       * Length of the @a mbds array with the exchange values
       * and blinding keys we are using.
       */
      unsigned int num_mbds;

      /**
       * Gamma value chosen by the exchange.
       */
      uint32_t noreveal_index;
    } ok;

  } details;
};


/**
 * Callbacks of this type are used to notify the application about the result
 * of the /coins/$COIN_PUB/melt stage.  If successful, the @a noreveal_index
 * should be committed to disk prior to proceeding
 * #TALER_EXCHANGE_refreshes_reveal().
 *
 * @param cls closure
 * @param mr response details
 */
typedef void
(*TALER_EXCHANGE_MeltCallback) (
  void *cls,
  const struct TALER_EXCHANGE_MeltResponse *mr);


/**
 * Submit a melt request to the exchange and get the exchange's
 * response.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, the provided
 * argument @a rd should be committed to persistent storage
 * prior to calling this function.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param keys exchange keys
 * @param rms the fresh secret that defines the refresh operation
 * @param rd the refresh data specifying the characteristics of the operation
 * @param melt_cb the callback to call with the result
 * @param melt_cb_cls closure for @a melt_cb
 * @return a handle for this request; NULL if the argument was invalid.
 *         In this case, neither callback will be called.
 */
struct TALER_EXCHANGE_MeltHandle *
TALER_EXCHANGE_melt (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_RefreshMasterSecretP *rms,
  const struct TALER_EXCHANGE_RefreshData *rd,
  TALER_EXCHANGE_MeltCallback melt_cb,
  void *melt_cb_cls);


/**
 * Cancel a melt request.  This function cannot be used
 * on a request handle if the callback was already invoked.
 *
 * @param mh the melt handle
 */
void
TALER_EXCHANGE_melt_cancel (struct TALER_EXCHANGE_MeltHandle *mh);


/* ********************* /refreshes/$RCH/reveal ***************************** */


/**
 * Information about a coin obtained via /refreshes/$RCH/reveal.
 */
struct TALER_EXCHANGE_RevealedCoinInfo
{
  /**
   * Private key of the coin.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Master secret of this coin.
   */
  struct TALER_PlanchetMasterSecretP ps;

  /**
   * Age commitment and its hash of the coin, might be NULL.
   */
  struct TALER_AgeCommitmentProof *age_commitment_proof;
  struct TALER_AgeCommitmentHash h_age_commitment;

  /**
   * Blinding keys used to blind the fresh coin.
   */
  union TALER_DenominationBlindingKeyP bks;

  /**
   * Signature affirming the validity of the coin.
   */
  struct TALER_DenominationSignature sig;

};


/**
 * Result of a /refreshes/$RCH/reveal request.
 */
struct TALER_EXCHANGE_RevealResult
{
  /**
   * HTTP status.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Parsed response details, variant depending on the
   * @e hr.http_status.
   */
  union
  {
    /**
     * Results for status #MHD_HTTP_OK.
     */
    struct
    {
      /**
       * Array of @e num_coins values about the coins obtained via the refresh
       * operation.  The array give the coins in the same order (and should
       * have the same length) in which the original melt request specified the
       * respective denomination keys.
       */
      const struct TALER_EXCHANGE_RevealedCoinInfo *coins;

      /**
       * Number of coins returned.
       */
      unsigned int num_coins;
    } ok;

  } details;

};


/**
 * Callbacks of this type are used to return the final result of
 * submitting a refresh request to a exchange.  If the operation was
 * successful, this function returns the signatures over the coins
 * that were remelted.
 *
 * @param cls closure
 * @param rr result of the reveal operation
 */
typedef void
(*TALER_EXCHANGE_RefreshesRevealCallback)(
  void *cls,
  const struct TALER_EXCHANGE_RevealResult *rr);


/**
 * @brief A /refreshes/$RCH/reveal Handle
 */
struct TALER_EXCHANGE_RefreshesRevealHandle;


/**
 * Submit a /refreshes/$RCH/reval request to the exchange and get the exchange's
 * response.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, the provided
 * arguments should have been committed to persistent storage
 * prior to calling this function.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param rms the fresh secret that defines the refresh operation
 * @param rd the refresh data that characterizes the refresh operation
 * @param num_coins number of fresh coins to be created, length of the @a exchange_vals array, must match value in @a rd
 * @param alg_values array @a num_coins of exchange values contributed to the refresh operation
 * @param noreveal_index response from the exchange to the
 *        #TALER_EXCHANGE_melt() invocation
 * @param reveal_cb the callback to call with the final result of the
 *        refresh operation
 * @param reveal_cb_cls closure for the above callback
 * @return a handle for this request; NULL if the argument was invalid.
 *         In this case, neither callback will be called.
 */
struct TALER_EXCHANGE_RefreshesRevealHandle *
TALER_EXCHANGE_refreshes_reveal (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_RefreshMasterSecretP *rms,
  const struct TALER_EXCHANGE_RefreshData *rd,
  unsigned int num_coins,
  const struct TALER_ExchangeWithdrawValues alg_values[static num_coins],
  uint32_t noreveal_index,
  TALER_EXCHANGE_RefreshesRevealCallback reveal_cb,
  void *reveal_cb_cls);


/**
 * Cancel a refresh reveal request.  This function cannot be used
 * on a request handle if the callback was already invoked.
 *
 * @param rrh the refresh reval handle
 */
void
TALER_EXCHANGE_refreshes_reveal_cancel (
  struct TALER_EXCHANGE_RefreshesRevealHandle *rrh);


/* ********************* /coins/$COIN_PUB/link ***************************** */


/**
 * @brief A /coins/$COIN_PUB/link Handle
 */
struct TALER_EXCHANGE_LinkHandle;


/**
 * Information about a coin obtained via /link.
 */
struct TALER_EXCHANGE_LinkedCoinInfo
{
  /**
   * Private key of the coin.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Age commitment and its hash, if applicable.
   */
  bool has_age_commitment;
  struct TALER_AgeCommitmentProof age_commitment_proof;
  struct TALER_AgeCommitmentHash h_age_commitment;

  /**
   * Master secret of this coin.
   */
  struct TALER_PlanchetMasterSecretP ps;

  /**
   * Signature affirming the validity of the coin.
   */
  struct TALER_DenominationSignature sig;

  /**
   * Denomination public key of the coin.
   */
  struct TALER_DenominationPublicKey pub;
};


/**
 * Result of a /link request.
 */
struct TALER_EXCHANGE_LinkResult
{
  /**
   * HTTP status.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Parsed response details, variant depending on the
   * @e hr.http_status.
   */
  union
  {
    /**
     * Results for status #MHD_HTTP_OK.
     */
    struct
    {
      /**
       * Array of @e num_coins values about the
       * coins obtained via linkage.
       */
      const struct TALER_EXCHANGE_LinkedCoinInfo *coins;

      /**
       * Number of coins returned.
       */
      unsigned int num_coins;
    } ok;

  } details;

};


/**
 * Callbacks of this type are used to return the final result of submitting a
 * /coins/$COIN_PUB/link request to a exchange.  If the operation was
 * successful, this function returns the signatures over the coins that were
 * created when the original coin was melted.
 *
 * @param cls closure
 * @param lr result of the /link operation
 */
typedef void
(*TALER_EXCHANGE_LinkCallback) (
  void *cls,
  const struct TALER_EXCHANGE_LinkResult *lr);


/**
 * Submit a link request to the exchange and get the exchange's response.
 *
 * This API is typically not used by anyone, it is more a threat against those
 * trying to receive a funds transfer by abusing the refresh protocol.
 *
 * @param ctx CURL context
 * @param url exchange base URL
 * @param coin_priv private key to request link data for
 * @param age_commitment_proof age commitment to the corresponding coin, might be NULL
 * @param link_cb the callback to call with the useful result of the
 *        refresh operation the @a coin_priv was involved in (if any)
 * @param link_cb_cls closure for @a link_cb
 * @return a handle for this request
 */
struct TALER_EXCHANGE_LinkHandle *
TALER_EXCHANGE_link (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  const struct TALER_AgeCommitmentProof *age_commitment_proof,
  TALER_EXCHANGE_LinkCallback link_cb,
  void *link_cb_cls);


/**
 * Cancel a link request.  This function cannot be used
 * on a request handle if the callback was already invoked.
 *
 * @param lh the link handle
 */
void
TALER_EXCHANGE_link_cancel (struct TALER_EXCHANGE_LinkHandle *lh);


/* ********************* /transfers/$WTID *********************** */

/**
 * @brief A /transfers/$WTID Handle
 */
struct TALER_EXCHANGE_TransfersGetHandle;


/**
 * Information the exchange returns per wire transfer.
 */
struct TALER_EXCHANGE_TransferData
{

  /**
   * exchange key used to sign
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

  /**
   * exchange signature over the transfer data
   */
  struct TALER_ExchangeSignatureP exchange_sig;

  /**
   * hash of the payto:// URI the transfer went to
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * time when the exchange claims to have performed the wire transfer
   */
  struct GNUNET_TIME_Timestamp execution_time;

  /**
   * Actual amount of the wire transfer, excluding the wire fee.
   */
  struct TALER_Amount total_amount;

  /**
   * wire fee that was charged by the exchange
   */
  struct TALER_Amount wire_fee;

  /**
   * length of the @e details array
   */
  unsigned int details_length;

  /**
   * array with details about the combined transactions
   */
  const struct TALER_TrackTransferDetails *details;

};


/**
 * Response for a GET /transfers request.
 */
struct TALER_EXCHANGE_TransfersGetResponse
{
  /**
   * HTTP response.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details depending on HTTP status code.
   */
  union
  {
    /**
     * Details if status code is #MHD_HTTP_OK.
     */
    struct
    {
      struct TALER_EXCHANGE_TransferData td;
    } ok;

  } details;
};


/**
 * Function called with detailed wire transfer data, including all
 * of the coin transactions that were combined into the wire transfer.
 *
 * @param cls closure
 * @param tgr response data
 */
typedef void
(*TALER_EXCHANGE_TransfersGetCallback)(
  void *cls,
  const struct TALER_EXCHANGE_TransfersGetResponse *tgr);


/**
 * Query the exchange about which transactions were combined
 * to create a wire transfer.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param keys exchange keys
 * @param wtid raw wire transfer identifier to get information about
 * @param cb callback to call
 * @param cb_cls closure for @a cb
 * @return handle to cancel operation
 */
struct TALER_EXCHANGE_TransfersGetHandle *
TALER_EXCHANGE_transfers_get (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  TALER_EXCHANGE_TransfersGetCallback cb,
  void *cb_cls);


/**
 * Cancel wire deposits request.  This function cannot be used on a request
 * handle if a response is already served for it.
 *
 * @param wdh the wire deposits request handle
 */
void
TALER_EXCHANGE_transfers_get_cancel (
  struct TALER_EXCHANGE_TransfersGetHandle *wdh);


/* ********************* GET /deposits/ *********************** */


/**
 * @brief A /deposits/ GET Handle
 */
struct TALER_EXCHANGE_DepositGetHandle;


/**
 * Data returned for a successful GET /deposits/ request.
 */
struct TALER_EXCHANGE_GetDepositResponse
{

  /**
   * HTTP response data.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details about the response.
   */
  union
  {

    /**
     * Response if the status was #MHD_HTTP_OK
     */
    struct TALER_EXCHANGE_DepositData
    {
      /**
       * exchange key used to sign, all zeros if exchange did not
       * yet execute the transaction
       */
      struct TALER_ExchangePublicKeyP exchange_pub;

      /**
       * signature from the exchange over the deposit data, all zeros if exchange did not
       * yet execute the transaction
       */
      struct TALER_ExchangeSignatureP exchange_sig;

      /**
       * wire transfer identifier used by the exchange, all zeros if exchange did not
       * yet execute the transaction
       */
      struct TALER_WireTransferIdentifierRawP wtid;

      /**
       * actual execution time for the wire transfer
       */
      struct GNUNET_TIME_Timestamp execution_time;

      /**
       * contribution to the total amount by this coin, all zeros if exchange did not
       * yet execute the transaction
       */
      struct TALER_Amount coin_contribution;

    } ok;

    /**
     * Response if the status was #MHD_HTTP_ACCEPTED
     */
    struct
    {

      /**
       * planned execution time for the wire transfer
       */
      struct GNUNET_TIME_Timestamp execution_time;

      /**
       * KYC legitimization requirement that the merchant should use to check
       * for its KYC status.
       */
      uint64_t requirement_row;

      /**
       * Current AML state for the account. May explain why transfers are
       * not happening.
       */
      enum TALER_AmlDecisionState aml_decision;

      /**
       * Set to 'true' if the KYC check is already finished and
       * the exchange is merely waiting for the @e execution_time.
       */
      bool kyc_ok;
    } accepted;

  } details;
};


/**
 * Function called with detailed wire transfer data.
 *
 * @param cls closure
 * @param dr details about the deposit response
 */
typedef void
(*TALER_EXCHANGE_DepositGetCallback)(
  void *cls,
  const struct TALER_EXCHANGE_GetDepositResponse *dr);


/**
 * Obtain the wire transfer details for a given transaction.  Tells the client
 * which aggregate wire transfer the deposit operation identified by @a coin_pub,
 * @a merchant_priv and @a h_contract_terms contributed to.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param keys exchange keys
 * @param merchant_priv the merchant's private key
 * @param h_wire hash of merchant's wire transfer details
 * @param h_contract_terms hash of the proposal data
 * @param coin_pub public key of the coin
 * @param timeout timeout to use for long-polling, 0 for no long polling
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to abort request
 */
struct TALER_EXCHANGE_DepositGetHandle *
TALER_EXCHANGE_deposits_get (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_MerchantPrivateKeyP *merchant_priv,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct GNUNET_TIME_Relative timeout,
  TALER_EXCHANGE_DepositGetCallback cb,
  void *cb_cls);


/**
 * Cancel deposit wtid request.  This function cannot be used on a request
 * handle if a response is already served for it.
 *
 * @param dwh the wire deposits request handle
 */
void
TALER_EXCHANGE_deposits_get_cancel (
  struct TALER_EXCHANGE_DepositGetHandle *dwh);


/**
 * Convenience function.  Verifies a coin's transaction history as
 * returned by the exchange.
 *
 * @param dk fee structure for the coin
 * @param coin_pub public key of the coin
 * @param history history of the coin in json encoding
 * @param[out] total how much of the coin has been spent according to @a history
 * @return #GNUNET_OK if @a history is valid, #GNUNET_SYSERR if not
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_verify_coin_history (
  const struct TALER_EXCHANGE_DenomPublicKey *dk,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const json_t *history,
  struct TALER_Amount *total);


/**
 * Parse history given in JSON format and return it in binary
 * format.
 *
 * @param keys exchange keys
 * @param history JSON array with the history
 * @param reserve_pub public key of the reserve to inspect
 * @param currency currency we expect the balance to be in
 * @param[out] total_in set to value of credits to reserve
 * @param[out] total_out set to value of debits from reserve
 * @param history_length number of entries in @a history
 * @param[out] rhistory array of length @a history_length, set to the
 *             parsed history entries
 * @return #GNUNET_OK if history was valid and @a rhistory and @a balance
 *         were set,
 *         #GNUNET_SYSERR if there was a protocol violation in @a history
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_parse_reserve_history (
  const struct TALER_EXCHANGE_Keys *keys,
  const json_t *history,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const char *currency,
  struct TALER_Amount *total_in,
  struct TALER_Amount *total_out,
  unsigned int history_length,
  struct TALER_EXCHANGE_ReserveHistoryEntry rhistory[static history_length]);


/**
 * Free memory (potentially) allocated by #TALER_EXCHANGE_parse_reserve_history().
 *
 * @param len number of entries in @a rhistory
 * @param[in] rhistory result to free
 */
void
TALER_EXCHANGE_free_reserve_history (
  unsigned int len,
  struct TALER_EXCHANGE_ReserveHistoryEntry rhistory[static len]);


/* ********************* /recoup *********************** */


/**
 * @brief A /recoup Handle
 */
struct TALER_EXCHANGE_RecoupHandle;


/**
 * Response from a recoup request.
 */
struct TALER_EXCHANGE_RecoupResponse
{
  /**
   * HTTP response data
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Response details depending on the HTTP status.
   */
  union
  {
    /**
     * Details if HTTP status is #MHD_HTTP_OK.
     */
    struct
    {
      /**
       * public key of the reserve receiving the recoup
       */
      struct TALER_ReservePublicKeyP reserve_pub;

    } ok;
  } details;

};


/**
 * Callbacks of this type are used to return the final result of
 * submitting a recoup request to a exchange.  If the operation was
 * successful, this function returns the @a reserve_pub of the
 * reserve that was credited.
 *
 * @param cls closure
 * @param rr response data
 */
typedef void
(*TALER_EXCHANGE_RecoupResultCallback) (
  void *cls,
  const struct TALER_EXCHANGE_RecoupResponse *rr);


/**
 * Ask the exchange to pay back a coin due to the exchange triggering
 * the emergency recoup protocol for a given denomination.  The value
 * of the coin will be refunded to the original customer (without fees).
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param keys exchange keys
 * @param pk kind of coin to pay back
 * @param denom_sig signature over the coin by the exchange using @a pk
 * @param exchange_vals contribution from the exchange on the withdraw
 * @param ps secret internals of the original planchet
 * @param recoup_cb the callback to call when the final result for this request is available
 * @param recoup_cb_cls closure for @a recoup_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_RecoupHandle *
TALER_EXCHANGE_recoup (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_EXCHANGE_DenomPublicKey *pk,
  const struct TALER_DenominationSignature *denom_sig,
  const struct TALER_ExchangeWithdrawValues *exchange_vals,
  const struct TALER_PlanchetMasterSecretP *ps,
  TALER_EXCHANGE_RecoupResultCallback recoup_cb,
  void *recoup_cb_cls);


/**
 * Cancel a recoup request.  This function cannot be used on a
 * request handle if the callback was already invoked.
 *
 * @param ph the recoup handle
 */
void
TALER_EXCHANGE_recoup_cancel (struct TALER_EXCHANGE_RecoupHandle *ph);


/* ********************* /recoup-refresh *********************** */


/**
 * @brief A /recoup-refresh Handle
 */
struct TALER_EXCHANGE_RecoupRefreshHandle;


/**
 * Response from a /recoup-refresh request.
 */
struct TALER_EXCHANGE_RecoupRefreshResponse
{
  /**
   * HTTP response data
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Response details depending on the HTTP status.
   */
  union
  {
    /**
     * Details if HTTP status is #MHD_HTTP_OK.
     */
    struct
    {
      /**
       * public key of the dirty coin that was credited
       */
      struct TALER_CoinSpendPublicKeyP old_coin_pub;

    } ok;
  } details;

};


/**
 * Callbacks of this type are used to return the final result of
 * submitting a recoup-refresh request to a exchange.
 *
 * @param cls closure
 * @param rrr response data
 */
typedef void
(*TALER_EXCHANGE_RecoupRefreshResultCallback) (
  void *cls,
  const struct TALER_EXCHANGE_RecoupRefreshResponse *rrr);


/**
 * Ask the exchange to pay back a coin due to the exchange triggering
 * the emergency recoup protocol for a given denomination.  The value
 * of the coin will be refunded to the original coin that the
 * revoked coin was refreshed from. The original coin is then
 * considered a zombie.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param keys exchange keys
 * @param pk kind of coin to pay back
 * @param denom_sig signature over the coin by the exchange using @a pk
 * @param exchange_vals contribution from the exchange on the withdraw
 * @param rms melt secret of the refreshing operation
 * @param ps coin-specific secrets derived for this coin during the refreshing operation
 * @param idx index of the fresh coin in the refresh operation that is now being recouped
 * @param recoup_cb the callback to call when the final result for this request is available
 * @param recoup_cb_cls closure for @a recoup_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_RecoupRefreshHandle *
TALER_EXCHANGE_recoup_refresh (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_EXCHANGE_DenomPublicKey *pk,
  const struct TALER_DenominationSignature *denom_sig,
  const struct TALER_ExchangeWithdrawValues *exchange_vals,
  const struct TALER_RefreshMasterSecretP *rms,
  const struct TALER_PlanchetMasterSecretP *ps,
  unsigned int idx,
  TALER_EXCHANGE_RecoupRefreshResultCallback recoup_cb,
  void *recoup_cb_cls);


/**
 * Cancel a recoup-refresh request.  This function cannot be used on a request
 * handle if the callback was already invoked.
 *
 * @param ph the recoup handle
 */
void
TALER_EXCHANGE_recoup_refresh_cancel (
  struct TALER_EXCHANGE_RecoupRefreshHandle *ph);


/* *********************  /kyc* *********************** */

/**
 * Handle for a ``/kyc-check`` operation.
 */
struct TALER_EXCHANGE_KycCheckHandle;


/**
 * KYC status response details.
 */
struct TALER_EXCHANGE_KycStatus
{
  /**
   * HTTP status code returned by the exchange.
   */
  unsigned int http_status;

  /**
   * Taler error code, if any.
   */
  enum TALER_ErrorCode ec;

  union
  {

    /**
     * KYC is OK, affirmation returned by the exchange.
     */
    struct
    {

      /**
       * Details about which KYC check(s) were passed.
       */
      const json_t *kyc_details;

      /**
       * Time of the affirmation.
       */
      struct GNUNET_TIME_Timestamp timestamp;

      /**
       * The signing public key used for @e exchange_sig.
       */
      struct TALER_ExchangePublicKeyP exchange_pub;

      /**
       * Signature of purpose
       * #TALER_SIGNATURE_EXCHANGE_ACCOUNT_SETUP_SUCCESS affirming
       * the successful KYC process.
       */
      struct TALER_ExchangeSignatureP exchange_sig;

      /**
       * AML status for the account.
       */
      enum TALER_AmlDecisionState aml_status;

    } ok;

    /**
     * KYC is required.
     */
    struct
    {

      /**
       * URL the user should open in a browser if
       * the KYC process is to be run. Returned if
       * @e http_status is #MHD_HTTP_ACCEPTED.
       */
      const char *kyc_url;

      /**
       * AML status for the account.
       */
      enum TALER_AmlDecisionState aml_status;

    } accepted;

    /**
     * KYC is OK, but account needs positive AML decision.
     */
    struct
    {

      /**
       * AML status for the account.
       */
      enum TALER_AmlDecisionState aml_status;

    } unavailable_for_legal_reasons;

  } details;

};

/**
 * Function called with the result of a KYC check.
 *
 * @param cls closure
 * @param ks the account's KYC status details
 */
typedef void
(*TALER_EXCHANGE_KycStatusCallback)(
  void *cls,
  const struct TALER_EXCHANGE_KycStatus *ks);


/**
 * Run interaction with exchange to check KYC status
 * of a merchant.
 *
 * @param ctx CURL context
 * @param url exchange base URL
 * @param keys keys of the exchange
 * @param requirement_row number identifying the KYC requirement
 * @param h_payto hash of the payto:// URI at @a payment_target
 * @param ut type of the entity performing the KYC check
 * @param timeout how long to wait for a positive KYC status
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return NULL on error
 */
struct TALER_EXCHANGE_KycCheckHandle *
TALER_EXCHANGE_kyc_check (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  uint64_t requirement_row,
  const struct TALER_PaytoHashP *h_payto,
  enum TALER_KYCLOGIC_KycUserType ut,
  struct GNUNET_TIME_Relative timeout,
  TALER_EXCHANGE_KycStatusCallback cb,
  void *cb_cls);


/**
 * Cancel KYC check operation.
 *
 * @param kyc handle for operation to cancel
 */
void
TALER_EXCHANGE_kyc_check_cancel (struct TALER_EXCHANGE_KycCheckHandle *kyc);


/**
 * KYC proof response details.
 */
struct TALER_EXCHANGE_KycProofResponse
{
  /**
   * HTTP status code returned by the exchange.
   */
  unsigned int http_status;

  union
  {

    /**
     * KYC is OK, affirmation returned by the exchange.
     */
    struct
    {

      /**
       * Where to redirect the client next.
       */
      const char *redirect_url;

    } found;

  } details;

};

/**
 * Function called with the result of a KYC check.
 *
 * @param cls closure
 * @param kpr the account's KYC status details
 */
typedef void
(*TALER_EXCHANGE_KycProofCallback)(
  void *cls,
  const struct TALER_EXCHANGE_KycProofResponse *kpr);


/**
 * Handle for a /kyc-proof operation.
 */
struct TALER_EXCHANGE_KycProofHandle;


/**
 * Run interaction with exchange to provide proof of KYC status.
 *
 * @param ctx CURL context
 * @param url exchange base URL
 * @param h_payto hash of payto URI identifying the target account
 * @param logic name of the KYC logic to run
 * @param args additional args to pass, can be NULL
 *        or a string to append to the URL. Must then begin with '&'.
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return NULL on error
 */
struct TALER_EXCHANGE_KycProofHandle *
TALER_EXCHANGE_kyc_proof (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_PaytoHashP *h_payto,
  const char *logic,
  const char *args,
  TALER_EXCHANGE_KycProofCallback cb,
  void *cb_cls);


/**
 * Cancel KYC proof operation.
 *
 * @param kph handle for operation to cancel
 */
void
TALER_EXCHANGE_kyc_proof_cancel (struct TALER_EXCHANGE_KycProofHandle *kph);


/**
 * Handle for a ``/kyc-wallet`` operation.
 */
struct TALER_EXCHANGE_KycWalletHandle;


/**
 * KYC status response details.
 */
struct TALER_EXCHANGE_WalletKycResponse
{

  /**
   * HTTP status code returned by the exchange.
   */
  unsigned int http_status;

  /**
   * Taler error code, if any.
   */
  enum TALER_ErrorCode ec;

  /**
   * Variants depending on @e http_status.
   */
  union
  {

    /**
     * In case @e http_status is #MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS.
     */
    struct
    {
      /**
       * Wallet's KYC requirement row.
       */
      uint64_t requirement_row;

      /**
       * Hash of the payto-URI identifying the wallet to KYC.
       */
      struct TALER_PaytoHashP h_payto;

    } unavailable_for_legal_reasons;

  } details;

};

/**
 * Function called with the result for a wallet looking
 * up its KYC payment target.
 *
 * @param cls closure
 * @param ks the wallets KYC payment target details
 */
typedef void
(*TALER_EXCHANGE_KycWalletCallback)(
  void *cls,
  const struct TALER_EXCHANGE_WalletKycResponse *ks);


/**
 * Run interaction with exchange to find out the wallet's KYC
 * identifier.
 *
 * @param ctx CURL context
 * @param url exchange base URL
 * @param reserve_priv wallet private key to check
 * @param balance balance (or balance threshold) crossed by the wallet
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return NULL on error
 */
struct TALER_EXCHANGE_KycWalletHandle *
TALER_EXCHANGE_kyc_wallet (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  const struct TALER_Amount *balance,
  TALER_EXCHANGE_KycWalletCallback cb,
  void *cb_cls);


/**
 * Cancel KYC wallet operation
 *
 * @param kwh handle for operation to cancel
 */
void
TALER_EXCHANGE_kyc_wallet_cancel (struct TALER_EXCHANGE_KycWalletHandle *kwh);


/* *********************  /management *********************** */


/**
 * @brief Future Exchange's signature key
 */
struct TALER_EXCHANGE_FutureSigningPublicKey
{
  /**
   * The signing public key
   */
  struct TALER_ExchangePublicKeyP key;

  /**
   * Signature by the security module affirming it owns this key.
   */
  struct TALER_SecurityModuleSignatureP signkey_secmod_sig;

  /**
   * Validity start time
   */
  struct GNUNET_TIME_Timestamp valid_from;

  /**
   * Validity expiration time (how long the exchange may use it).
   */
  struct GNUNET_TIME_Timestamp valid_until;

  /**
   * Validity expiration time for legal disputes.
   */
  struct GNUNET_TIME_Timestamp valid_legal;
};


/**
 * @brief Public information about a future exchange's denomination key
 */
struct TALER_EXCHANGE_FutureDenomPublicKey
{
  /**
   * The public key
   */
  struct TALER_DenominationPublicKey key;

  /**
   * Signature by the security module affirming it owns this key.
   */
  struct TALER_SecurityModuleSignatureP denom_secmod_sig;

  /**
   * Timestamp indicating when the denomination key becomes valid
   */
  struct GNUNET_TIME_Timestamp valid_from;

  /**
   * Timestamp indicating when the denomination key can’t be used anymore to
   * withdraw new coins.
   */
  struct GNUNET_TIME_Timestamp withdraw_valid_until;

  /**
   * Timestamp indicating when coins of this denomination become invalid.
   */
  struct GNUNET_TIME_Timestamp expire_deposit;

  /**
   * When do signatures with this denomination key become invalid?
   * After this point, these signatures cannot be used in (legal)
   * disputes anymore, as the Exchange is then allowed to destroy its side
   * of the evidence.  @e expire_legal is expected to be significantly
   * larger than @e expire_deposit (by a year or more).
   */
  struct GNUNET_TIME_Timestamp expire_legal;

  /**
   * The value of this denomination
   */
  struct TALER_Amount value;

  /**
   * The applicable fee for withdrawing a coin of this denomination
   */
  struct TALER_Amount fee_withdraw;

  /**
   * The applicable fee to spend a coin of this denomination
   */
  struct TALER_Amount fee_deposit;

  /**
   * The applicable fee to melt/refresh a coin of this denomination
   */
  struct TALER_Amount fee_refresh;

  /**
   * The applicable fee to refund a coin of this denomination
   */
  struct TALER_Amount fee_refund;

};


/**
 * @brief Information about future keys from the exchange.
 */
struct TALER_EXCHANGE_FutureKeys
{

  /**
   * Array of the exchange's online signing keys.
   */
  struct TALER_EXCHANGE_FutureSigningPublicKey *sign_keys;

  /**
   * Array of the exchange's denomination keys.
   */
  struct TALER_EXCHANGE_FutureDenomPublicKey *denom_keys;

  /**
   * Public key of the signkey security module.
   */
  struct TALER_SecurityModulePublicKeyP signkey_secmod_public_key;

  /**
   * Public key of the RSA denomination security module.
   */
  struct TALER_SecurityModulePublicKeyP denom_secmod_public_key;

  /**
   * Public key of the CS denomination security module.
   */
  struct TALER_SecurityModulePublicKeyP denom_secmod_cs_public_key;

  /**
   * Offline master public key used by this exchange.
   */
  struct TALER_MasterPublicKeyP master_pub;

  /**
   * Length of the @e sign_keys array (number of valid entries).
   */
  unsigned int num_sign_keys;

  /**
   * Length of the @e denom_keys array.
   */
  unsigned int num_denom_keys;

};


/**
 * Response from a /management/keys request.
 */
struct TALER_EXCHANGE_ManagementGetKeysResponse
{
  /**
   * HTTP response data
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Response details depending on the HTTP status.
   */
  union
  {
    /**
     * Details if HTTP status is #MHD_HTTP_OK.
     */
    struct
    {
      /**
       * information about the various keys used
       * by the exchange
       */
      struct TALER_EXCHANGE_FutureKeys keys;

    } ok;
  } details;

};


/**
 * Function called with information about future keys.
 *
 * @param cls closure
 * @param mgr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementGetKeysCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ManagementGetKeysResponse *mgr);


/**
 * @brief Handle for a GET /management/keys request.
 */
struct TALER_EXCHANGE_ManagementGetKeysHandle;


/**
 * Request future keys from the exchange.  The obtained information will be
 * passed to the @a cb.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param cb function to call with the exchange's future keys result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementGetKeysHandle *
TALER_EXCHANGE_get_management_keys (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  TALER_EXCHANGE_ManagementGetKeysCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_get_management_keys() operation.
 *
 * @param gh handle of the operation to cancel
 */
void
TALER_EXCHANGE_get_management_keys_cancel (
  struct TALER_EXCHANGE_ManagementGetKeysHandle *gh);


/**
 * @brief Public information about a signature on an exchange's online signing key
 */
struct TALER_EXCHANGE_SigningKeySignature
{
  /**
   * The signing public key
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

  /**
   * Signature over this signing key by the exchange's master signature.
   * Of purpose #TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY
   */
  struct TALER_MasterSignatureP master_sig;

};


/**
 * @brief Public information about a signature on an exchange's denomination key
 */
struct TALER_EXCHANGE_DenominationKeySignature
{
  /**
   * The hash of the denomination's public key
   */
  struct TALER_DenominationHashP h_denom_pub;

  /**
   * Signature over this denomination key by the exchange's master signature.
   * Of purpose #TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY.
   */
  struct TALER_MasterSignatureP master_sig;

};


/**
 * Information needed for a POST /management/keys operation.
 */
struct TALER_EXCHANGE_ManagementPostKeysData
{

  /**
   * Array of the master signatures for the exchange's online signing keys.
   */
  struct TALER_EXCHANGE_SigningKeySignature *sign_sigs;

  /**
   * Array of the master signatures for the exchange's denomination keys.
   */
  struct TALER_EXCHANGE_DenominationKeySignature *denom_sigs;

  /**
   * Length of the @e sign_keys array (number of valid entries).
   */
  unsigned int num_sign_sigs;

  /**
   * Length of the @e denom_keys array.
   */
  unsigned int num_denom_sigs;
};


/**
 * Response from a POST /management/keys request.
 */
struct TALER_EXCHANGE_ManagementPostKeysResponse
{
  /**
   * HTTP response data
   */
  struct TALER_EXCHANGE_HttpResponse hr;

};


/**
 * Function called with information about the post keys operation result.
 *
 * @param cls closure
 * @param mr response data
 */
typedef void
(*TALER_EXCHANGE_ManagementPostKeysCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ManagementPostKeysResponse *mr);


/**
 * @brief Handle for a POST /management/keys request.
 */
struct TALER_EXCHANGE_ManagementPostKeysHandle;


/**
 * Provide master-key signatures to the exchange.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param pkd signature data to POST
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementPostKeysHandle *
TALER_EXCHANGE_post_management_keys (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_EXCHANGE_ManagementPostKeysData *pkd,
  TALER_EXCHANGE_ManagementPostKeysCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_post_management_keys() operation.
 *
 * @param ph handle of the operation to cancel
 */
void
TALER_EXCHANGE_post_management_keys_cancel (
  struct TALER_EXCHANGE_ManagementPostKeysHandle *ph);


/**
 * Information needed for a POST /management/extensions operation.
 *
 * It represents the interface ExchangeKeysResponse as defined in
 * https://docs.taler.net/design-documents/006-extensions.html#exchange
 */
struct TALER_EXCHANGE_ManagementPostExtensionsData
{
  const json_t *extensions;
  struct TALER_MasterSignatureP extensions_sig;
};


/**
 * Response from a POST /management/extensions request.
 */
struct TALER_EXCHANGE_ManagementPostExtensionsResponse
{
  /**
   * HTTP response data
   */
  struct TALER_EXCHANGE_HttpResponse hr;

};


/**
 * Function called with information about the post extensions operation result.
 *
 * @param cls closure
 * @param hr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementPostExtensionsCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ManagementPostExtensionsResponse *hr);

/**
 * @brief Handle for a POST /management/extensions request.
 */
struct TALER_EXCHANGE_ManagementPostExtensionsHandle;


/**
 * Uploads the configurations of enabled extensions to the exchange, signed
 * with the master key.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param ped signature data to POST
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementPostExtensionsHandle *
TALER_EXCHANGE_management_post_extensions (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_EXCHANGE_ManagementPostExtensionsData *ped,
  TALER_EXCHANGE_ManagementPostExtensionsCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_management_post_extensions() operation.
 *
 * @param ph handle of the operation to cancel
 */
void
TALER_EXCHANGE_management_post_extensions_cancel (
  struct TALER_EXCHANGE_ManagementPostExtensionsHandle *ph);


/**
 * Response from a POST /management/drain request.
 */
struct TALER_EXCHANGE_ManagementDrainResponse
{
  /**
   * HTTP response data
   */
  struct TALER_EXCHANGE_HttpResponse hr;

};


/**
 * Function called with information about the drain profits result.
 *
 * @param cls closure
 * @param hr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementDrainProfitsCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ManagementDrainResponse *hr);


/**
 * @brief Handle for a POST /management/drain request.
 */
struct TALER_EXCHANGE_ManagementDrainProfitsHandle;


/**
 * Uploads the drain profits request.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param wtid wire transfer identifier to use
 * @param amount total to transfer
 * @param date when was the request created
 * @param account_section configuration section identifying account to debit
 * @param payto_uri RFC 8905 URI of the account to credit
 * @param master_sig signature affirming the operation
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementDrainProfitsHandle *
TALER_EXCHANGE_management_drain_profits (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_Amount *amount,
  struct GNUNET_TIME_Timestamp date,
  const char *account_section,
  const char *payto_uri,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementDrainProfitsCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_management_drain_profits() operation.
 *
 * @param dp handle of the operation to cancel
 */
void
TALER_EXCHANGE_management_drain_profits_cancel (
  struct TALER_EXCHANGE_ManagementDrainProfitsHandle *dp);


/**
 * Response from a POST /management/denominations/$DENOM/revoke request.
 */
struct TALER_EXCHANGE_ManagementRevokeDenominationResponse
{
  /**
   * HTTP response data
   */
  struct TALER_EXCHANGE_HttpResponse hr;

};


/**
 * Function called with information about the post revocation operation result.
 *
 * @param cls closure
 * @param hr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementRevokeDenominationKeyCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ManagementRevokeDenominationResponse *hr);


/**
 * @brief Handle for a POST /management/denominations/$H_DENOM_PUB/revoke request.
 */
struct TALER_EXCHANGE_ManagementRevokeDenominationKeyHandle;


/**
 * Inform the exchange that a denomination key was revoked.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param h_denom_pub hash of the denomination public key that was revoked
 * @param master_sig signature affirming the revocation
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementRevokeDenominationKeyHandle *
TALER_EXCHANGE_management_revoke_denomination_key (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementRevokeDenominationKeyCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_management_revoke_denomination_key() operation.
 *
 * @param rh handle of the operation to cancel
 */
void
TALER_EXCHANGE_management_revoke_denomination_key_cancel (
  struct TALER_EXCHANGE_ManagementRevokeDenominationKeyHandle *rh);


/**
 * Response from a POST /management/signkeys/$SK/revoke request.
 */
struct TALER_EXCHANGE_ManagementRevokeSigningKeyResponse
{
  /**
   * HTTP response data
   */
  struct TALER_EXCHANGE_HttpResponse hr;

};

/**
 * Function called with information about the post revocation operation result.
 *
 * @param cls closure
 * @param hr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementRevokeSigningKeyCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ManagementRevokeSigningKeyResponse *hr);


/**
 * @brief Handle for a POST /management/signkeys/$H_DENOM_PUB/revoke request.
 */
struct TALER_EXCHANGE_ManagementRevokeSigningKeyHandle;


/**
 * Inform the exchange that a signing key was revoked.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param exchange_pub the public signing key that was revoked
 * @param master_sig signature affirming the revocation
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementRevokeSigningKeyHandle *
TALER_EXCHANGE_management_revoke_signing_key (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementRevokeSigningKeyCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_management_revoke_signing_key() operation.
 *
 * @param rh handle of the operation to cancel
 */
void
TALER_EXCHANGE_management_revoke_signing_key_cancel (
  struct TALER_EXCHANGE_ManagementRevokeSigningKeyHandle *rh);


/**
 * Response from a POST /management/aml-officers request.
 */
struct TALER_EXCHANGE_ManagementUpdateAmlOfficerResponse
{
  /**
   * HTTP response data
   */
  struct TALER_EXCHANGE_HttpResponse hr;

};

/**
 * Function called with information about the change to
 * an AML officer status.
 *
 * @param cls closure
 * @param hr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementUpdateAmlOfficerCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ManagementUpdateAmlOfficerResponse *hr);


/**
 * @brief Handle for a POST /management/aml-officers/$OFFICER_PUB request.
 */
struct TALER_EXCHANGE_ManagementUpdateAmlOfficer;


/**
 * Inform the exchange that the status of an AML officer has changed.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param officer_pub the public signing key of the officer
 * @param officer_name name of the officer
 * @param change_date when to affect the status change
 * @param is_active true to enable the officer
 * @param read_only true to only allow read-only access
 * @param master_sig signature affirming the change
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementUpdateAmlOfficer *
TALER_EXCHANGE_management_update_aml_officer (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_AmlOfficerPublicKeyP *officer_pub,
  const char *officer_name,
  struct GNUNET_TIME_Timestamp change_date,
  bool is_active,
  bool read_only,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementUpdateAmlOfficerCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_management_update_aml_officer() operation.
 *
 * @param rh handle of the operation to cancel
 */
void
TALER_EXCHANGE_management_update_aml_officer_cancel (
  struct TALER_EXCHANGE_ManagementUpdateAmlOfficer *rh);


/**
 * Summary data about an AML decision.
 */
struct TALER_EXCHANGE_AmlDecisionSummary
{
  /**
   * What is the current monthly threshold.
   */
  struct TALER_Amount threshold;

  /**
   * Account the decision was made for.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * RowID of this decision.
   */
  uint64_t rowid;

  /**
   * Current decision state.
   */
  enum TALER_AmlDecisionState current_state;
};


/**
 * Information about AML decisions returned by the exchange.
 */
struct TALER_EXCHANGE_AmlDecisionsResponse
{
  /**
   * HTTP response details.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details depending on the HTTP response code.
   */
  union
  {

    /**
     * Information returned on success (#MHD_HTTP_OK).
     */
    struct
    {

      /**
       * Array of AML decision summaries returned by the exchange.
       */
      const struct TALER_EXCHANGE_AmlDecisionSummary *decisions;

      /**
       * Length of the @e decisions array.
       */
      unsigned int decisions_length;

    } ok;

  } details;
};


/**
 * Function called with summary information about
 * AML decisions.
 *
 * @param cls closure
 * @param adr response data
 */
typedef void
(*TALER_EXCHANGE_LookupAmlDecisionsCallback) (
  void *cls,
  const struct TALER_EXCHANGE_AmlDecisionsResponse *adr);


/**
 * @brief Handle for a POST /aml/$OFFICER_PUB/decisions/$STATUS request.
 */
struct TALER_EXCHANGE_LookupAmlDecisions;


/**
 * Inform the exchange that an AML decision has been taken.
 *
 * @param ctx the context
 * @param exchange_url HTTP base URL for the exchange
 * @param start row number starting point (exclusive rowid)
 * @param delta number of records to return, negative for descending, positive for ascending from start
 * @param state type of AML decisions to return
 * @param officer_priv private key of the deciding AML officer
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_LookupAmlDecisions *
TALER_EXCHANGE_lookup_aml_decisions (
  struct GNUNET_CURL_Context *ctx,
  const char *exchange_url,
  uint64_t start,
  int delta,
  enum TALER_AmlDecisionState state,
  const struct TALER_AmlOfficerPrivateKeyP *officer_priv,
  TALER_EXCHANGE_LookupAmlDecisionsCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_lookup_aml_decisions() operation.
 *
 * @param lh handle of the operation to cancel
 */
void
TALER_EXCHANGE_lookup_aml_decisions_cancel (
  struct TALER_EXCHANGE_LookupAmlDecisions *lh);


/**
 * Detailed data about an AML decision.
 */
struct TALER_EXCHANGE_AmlDecisionDetail
{
  /**
   * When was the decision made.
   */
  struct GNUNET_TIME_Timestamp decision_time;

  /**
   * New threshold set by this decision.
   */
  struct TALER_Amount new_threshold;

  /**
   * Who made the decision?
   */
  struct TALER_AmlOfficerPublicKeyP decider_pub;

  /**
   * Justification given for the decision.
   */
  const char *justification;

  /**
   * New decision state.
   */
  enum TALER_AmlDecisionState new_state;
};


/**
 * Detailed data collected during a KYC process for the account.
 */
struct TALER_EXCHANGE_KycHistoryDetail
{
  /**
   * Configuration section name of the KYC provider that contributed the data.
   */
  const char *provider_section;

  /**
   * The collected KYC data.
   */
  const json_t *attributes;

  /**
   * When was the data collection made.
   */
  struct GNUNET_TIME_Timestamp collection_time;

};


/**
 * Information about AML decision details returned by the exchange.
 */
struct TALER_EXCHANGE_AmlDecisionResponse
{
  /**
   * HTTP response details.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details depending on the HTTP response code.
   */
  union
  {

    /**
     * Information returned on success (#MHD_HTTP_OK).
     */
    struct
    {

      /**
       * Array of AML decision details returned by the exchange.
       */
      const struct TALER_EXCHANGE_AmlDecisionDetail *aml_history;

      /**
       * Length of the @e aml_history array.
       */
      unsigned int aml_history_length;

      /**
       * Array of KYC data collections returned by the exchange.
       */
      const struct TALER_EXCHANGE_KycHistoryDetail *kyc_attributes;

      /**
       * Length of the @e kyc_attributes array.
       */
      unsigned int kyc_attributes_length;

    } ok;

  } details;
};


/**
 * Function called with summary information about
 * AML decisions.
 *
 * @param cls closure
 * @param adr response data
 */
typedef void
(*TALER_EXCHANGE_LookupAmlDecisionCallback) (
  void *cls,
  const struct TALER_EXCHANGE_AmlDecisionResponse *adr);


/**
 * @brief Handle for a POST /aml/$OFFICER_PUB/decision/$H_PAYTO request.
 */
struct TALER_EXCHANGE_LookupAmlDecision;


/**
 * Inform the exchange that an AML decision has been taken.
 *
 * @param ctx the context
 * @param exchange_url HTTP base URL for the exchange
 * @param h_payto which account to return the decision history for
 * @param officer_priv private key of the deciding AML officer
 * @param history true to return the full history, otherwise only the last decision
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_LookupAmlDecision *
TALER_EXCHANGE_lookup_aml_decision (
  struct GNUNET_CURL_Context *ctx,
  const char *exchange_url,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_AmlOfficerPrivateKeyP *officer_priv,
  bool history,
  TALER_EXCHANGE_LookupAmlDecisionCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_lookup_aml_decision() operation.
 *
 * @param rh handle of the operation to cancel
 */
void
TALER_EXCHANGE_lookup_aml_decision_cancel (
  struct TALER_EXCHANGE_LookupAmlDecision *rh);


/**
 * @brief Handle for a POST /aml-decision/$OFFICER_PUB request.
 */
struct TALER_EXCHANGE_AddAmlDecision;


/**
 * Response when making an AML decision.
 */
struct TALER_EXCHANGE_AddAmlDecisionResponse
{
  /**
   * HTTP response data.
   */
  struct TALER_EXCHANGE_HttpResponse hr;
};


/**
 * Function called with information about storing an
 * an AML decision.
 *
 * @param cls closure
 * @param adr response data
 */
typedef void
(*TALER_EXCHANGE_AddAmlDecisionCallback) (
  void *cls,
  const struct TALER_EXCHANGE_AddAmlDecisionResponse *adr);

/**
 * Inform the exchange that an AML decision has been taken.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param justification human-readable justification
 * @param decision_time when was the decision made
 * @param new_threshold at what monthly amount threshold
 *                      should a revision be triggered
 * @param h_payto payto URI hash of the account the
 *                      decision is about
 * @param new_state updated AML state
 * @param kyc_requirements JSON array of KYC requirements being imposed, NULL for none
 * @param officer_priv private key of the deciding AML officer
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_AddAmlDecision *
TALER_EXCHANGE_add_aml_decision (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const char *justification,
  struct GNUNET_TIME_Timestamp decision_time,
  const struct TALER_Amount *new_threshold,
  const struct TALER_PaytoHashP *h_payto,
  enum TALER_AmlDecisionState new_state,
  const json_t *kyc_requirements,
  const struct TALER_AmlOfficerPrivateKeyP *officer_priv,
  TALER_EXCHANGE_AddAmlDecisionCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_add_aml_decision() operation.
 *
 * @param rh handle of the operation to cancel
 */
void
TALER_EXCHANGE_add_aml_decision_cancel (
  struct TALER_EXCHANGE_AddAmlDecision *rh);


/**
 * Response when adding a partner exchange.
 */
struct TALER_EXCHANGE_ManagementAddPartnerResponse
{
  /**
   * HTTP response data.
   */
  struct TALER_EXCHANGE_HttpResponse hr;
};

/**
 * Function called with information about the change to
 * an AML officer status.
 *
 * @param cls closure
 * @param apr response data
 */
typedef void
(*TALER_EXCHANGE_ManagementAddPartnerCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ManagementAddPartnerResponse *apr);


/**
 * @brief Handle for a POST /management/partners/$PARTNER_PUB request.
 */
struct TALER_EXCHANGE_ManagementAddPartner;


/**
 * Inform the exchange that the status of a partnering
 * exchange was defined.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param partner_pub the offline signing key of the partner
 * @param start_date validity period start
 * @param end_date validity period end
 * @param wad_frequency how often will we do wad transfers to this partner
 * @param wad_fee what is the wad fee to this partner
 * @param partner_base_url what is the base URL of the @a partner_pub exchange
 * @param master_sig the signature the signature
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementAddPartner *
TALER_EXCHANGE_management_add_partner (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_MasterPublicKeyP *partner_pub,
  struct GNUNET_TIME_Timestamp start_date,
  struct GNUNET_TIME_Timestamp end_date,
  struct GNUNET_TIME_Relative wad_frequency,
  const struct TALER_Amount *wad_fee,
  const char *partner_base_url,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementAddPartnerCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_management_add_partner() operation.
 *
 * @param rh handle of the operation to cancel
 */
void
TALER_EXCHANGE_management_add_partner_cancel (
  struct TALER_EXCHANGE_ManagementAddPartner *rh);


/**
 * Response when enabling an auditor.
 */
struct TALER_EXCHANGE_ManagementAuditorEnableResponse
{
  /**
   * HTTP response data.
   */
  struct TALER_EXCHANGE_HttpResponse hr;
};

/**
 * Function called with information about the auditor setup operation result.
 *
 * @param cls closure
 * @param aer response data
 */
typedef void
(*TALER_EXCHANGE_ManagementAuditorEnableCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ManagementAuditorEnableResponse *aer);


/**
 * @brief Handle for a POST /management/auditors request.
 */
struct TALER_EXCHANGE_ManagementAuditorEnableHandle;


/**
 * Inform the exchange that an auditor should be enable or enabled.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param auditor_pub the public signing key of the auditor
 * @param auditor_url base URL of the auditor
 * @param auditor_name human readable name for the auditor
 * @param validity_start when was this decided?
 * @param master_sig signature affirming the auditor addition
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementAuditorEnableHandle *
TALER_EXCHANGE_management_enable_auditor (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const char *auditor_url,
  const char *auditor_name,
  struct GNUNET_TIME_Timestamp validity_start,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementAuditorEnableCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_management_enable_auditor() operation.
 *
 * @param ah handle of the operation to cancel
 */
void
TALER_EXCHANGE_management_enable_auditor_cancel (
  struct TALER_EXCHANGE_ManagementAuditorEnableHandle *ah);

/**
 * Response when disabling an auditor.
 */
struct TALER_EXCHANGE_ManagementAuditorDisableResponse
{
  /**
   * HTTP response data.
   */
  struct TALER_EXCHANGE_HttpResponse hr;
};

/**
 * Function called with information about the auditor disable operation result.
 *
 * @param cls closure
 * @param adr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementAuditorDisableCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ManagementAuditorDisableResponse *adr);


/**
 * @brief Handle for a POST /management/auditors/$AUDITOR_PUB/disable request.
 */
struct TALER_EXCHANGE_ManagementAuditorDisableHandle;


/**
 * Inform the exchange that an auditor should be disabled.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param auditor_pub the public signing key of the auditor
 * @param validity_end when was this decided?
 * @param master_sig signature affirming the auditor addition
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementAuditorDisableHandle *
TALER_EXCHANGE_management_disable_auditor (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  struct GNUNET_TIME_Timestamp validity_end,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementAuditorDisableCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_management_disable_auditor() operation.
 *
 * @param ah handle of the operation to cancel
 */
void
TALER_EXCHANGE_management_disable_auditor_cancel (
  struct TALER_EXCHANGE_ManagementAuditorDisableHandle *ah);


/**
 * Response from an exchange account/enable operation.
 */
struct TALER_EXCHANGE_ManagementWireEnableResponse
{
  /**
   * HTTP response data.
   */
  struct TALER_EXCHANGE_HttpResponse hr;
};


/**
 * Function called with information about the wire enable operation result.
 *
 * @param cls closure
 * @param wer HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementWireEnableCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ManagementWireEnableResponse *wer);


/**
 * @brief Handle for a POST /management/wire request.
 */
struct TALER_EXCHANGE_ManagementWireEnableHandle;


/**
 * Inform the exchange that a wire account should be enabled.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param payto_uri RFC 8905 URI of the exchange's bank account
 * @param conversion_url URL of the conversion service, or NULL if none
 * @param debit_restrictions JSON encoding of debit restrictions on the account; see AccountRestriction in the spec
 * @param credit_restrictions JSON encoding of credit restrictions on the account; see AccountRestriction in the spec
 * @param validity_start when was this decided?
 * @param master_sig1 signature affirming the wire addition
 *        of purpose #TALER_SIGNATURE_MASTER_ADD_WIRE
 * @param master_sig2 signature affirming the validity of the account for clients;
 *        of purpose #TALER_SIGNATURE_MASTER_WIRE_DETAILS.
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementWireEnableHandle *
TALER_EXCHANGE_management_enable_wire (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const char *payto_uri,
  const char *conversion_url,
  const json_t *debit_restrictions,
  const json_t *credit_restrictions,
  struct GNUNET_TIME_Timestamp validity_start,
  const struct TALER_MasterSignatureP *master_sig1,
  const struct TALER_MasterSignatureP *master_sig2,
  TALER_EXCHANGE_ManagementWireEnableCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_management_enable_wire() operation.
 *
 * @param wh handle of the operation to cancel
 */
void
TALER_EXCHANGE_management_enable_wire_cancel (
  struct TALER_EXCHANGE_ManagementWireEnableHandle *wh);


/**
 * Response from an exchange account/disable operation.
 */
struct TALER_EXCHANGE_ManagementWireDisableResponse
{
  /**
   * HTTP response data.
   */
  struct TALER_EXCHANGE_HttpResponse hr;
};

/**
 * Function called with information about the wire disable operation result.
 *
 * @param cls closure
 * @param wdr response data
 */
typedef void
(*TALER_EXCHANGE_ManagementWireDisableCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ManagementWireDisableResponse *wdr);


/**
 * @brief Handle for a POST /management/wire/disable request.
 */
struct TALER_EXCHANGE_ManagementWireDisableHandle;


/**
 * Inform the exchange that a wire account should be disabled.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param payto_uri RFC 8905 URI of the exchange's bank account
 * @param validity_end when was this decided?
 * @param master_sig signature affirming the wire addition
 *        of purpose #TALER_SIGNATURE_MASTER_DEL_WIRE
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementWireDisableHandle *
TALER_EXCHANGE_management_disable_wire (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const char *payto_uri,
  struct GNUNET_TIME_Timestamp validity_end,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementWireDisableCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_management_disable_wire() operation.
 *
 * @param wh handle of the operation to cancel
 */
void
TALER_EXCHANGE_management_disable_wire_cancel (
  struct TALER_EXCHANGE_ManagementWireDisableHandle *wh);


/**
 * Response when setting wire fees.
 */
struct TALER_EXCHANGE_ManagementSetWireFeeResponse
{
  /**
   * HTTP response data.
   */
  struct TALER_EXCHANGE_HttpResponse hr;
};

/**
 * Function called with information about the wire enable operation result.
 *
 * @param cls closure
 * @param wfr response data
 */
typedef void
(*TALER_EXCHANGE_ManagementSetWireFeeCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ManagementSetWireFeeResponse *wfr);


/**
 * @brief Handle for a POST /management/wire-fees request.
 */
struct TALER_EXCHANGE_ManagementSetWireFeeHandle;


/**
 * Inform the exchange about future wire fees.
 *
 * @param ctx the context
 * @param exchange_base_url HTTP base URL for the exchange
 * @param wire_method for which wire method are fees provided
 * @param validity_start start date for the provided wire fees
 * @param validity_end end date for the provided wire fees
 * @param fees the wire fees for this time period
 * @param master_sig signature affirming the wire fees;
 *        of purpose #TALER_SIGNATURE_MASTER_WIRE_FEES
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementSetWireFeeHandle *
TALER_EXCHANGE_management_set_wire_fees (
  struct GNUNET_CURL_Context *ctx,
  const char *exchange_base_url,
  const char *wire_method,
  struct GNUNET_TIME_Timestamp validity_start,
  struct GNUNET_TIME_Timestamp validity_end,
  const struct TALER_WireFeeSet *fees,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementSetWireFeeCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_management_enable_wire() operation.
 *
 * @param swfh handle of the operation to cancel
 */
void
TALER_EXCHANGE_management_set_wire_fees_cancel (
  struct TALER_EXCHANGE_ManagementSetWireFeeHandle *swfh);


/**
 * Response when setting global fees.
 */
struct TALER_EXCHANGE_ManagementSetGlobalFeeResponse
{
  /**
   * HTTP response data.
   */
  struct TALER_EXCHANGE_HttpResponse hr;
};


/**
 * Function called with information about the global fee setting operation result.
 *
 * @param cls closure
 * @param gfr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementSetGlobalFeeCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ManagementSetGlobalFeeResponse *gfr);


/**
 * @brief Handle for a POST /management/global-fees request.
 */
struct TALER_EXCHANGE_ManagementSetGlobalFeeHandle;


/**
 * Inform the exchange about global fees.
 *
 * @param ctx the context
 * @param exchange_base_url HTTP base URL for the exchange
 * @param validity_start start date for the provided wire fees
 * @param validity_end end date for the provided wire fees
 * @param fees the wire fees for this time period
 * @param purse_timeout when do purses time out
 * @param history_expiration how long are account histories preserved
 * @param purse_account_limit how many purses are free per account
 * @param master_sig signature affirming the wire fees;
 *        of purpose #TALER_SIGNATURE_MASTER_GLOBAL_FEES
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementSetGlobalFeeHandle *
TALER_EXCHANGE_management_set_global_fees (
  struct GNUNET_CURL_Context *ctx,
  const char *exchange_base_url,
  struct GNUNET_TIME_Timestamp validity_start,
  struct GNUNET_TIME_Timestamp validity_end,
  const struct TALER_GlobalFeeSet *fees,
  struct GNUNET_TIME_Relative purse_timeout,
  struct GNUNET_TIME_Relative history_expiration,
  uint32_t purse_account_limit,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementSetGlobalFeeCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_management_enable_wire() operation.
 *
 * @param sgfh handle of the operation to cancel
 */
void
TALER_EXCHANGE_management_set_global_fees_cancel (
  struct TALER_EXCHANGE_ManagementSetGlobalFeeHandle *sgfh);


/**
 * Response when adding denomination signature by auditor.
 */
struct TALER_EXCHANGE_AuditorAddDenominationResponse
{
  /**
   * HTTP response data.
   */
  struct TALER_EXCHANGE_HttpResponse hr;
};


/**
 * Function called with information about the POST
 * /auditor/$AUDITOR_PUB/$H_DENOM_PUB operation result.
 *
 * @param cls closure
 * @param adr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_AuditorAddDenominationCallback) (
  void *cls,
  const struct TALER_EXCHANGE_AuditorAddDenominationResponse *adr);


/**
 * @brief Handle for a POST /auditor/$AUDITOR_PUB/$H_DENOM_PUB request.
 */
struct TALER_EXCHANGE_AuditorAddDenominationHandle;


/**
 * Provide auditor signatures for a denomination to the exchange.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param h_denom_pub hash of the public key of the denomination
 * @param auditor_pub public key of the auditor
 * @param auditor_sig signature of the auditor, of
 *         purpose #TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_AuditorAddDenominationHandle *
TALER_EXCHANGE_add_auditor_denomination (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const struct TALER_AuditorSignatureP *auditor_sig,
  TALER_EXCHANGE_AuditorAddDenominationCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_add_auditor_denomination() operation.
 *
 * @param ah handle of the operation to cancel
 */
void
TALER_EXCHANGE_add_auditor_denomination_cancel (
  struct TALER_EXCHANGE_AuditorAddDenominationHandle *ah);


/* ********************* W2W API ****************** */


/**
 * Response generated for a contract get request.
 */
struct TALER_EXCHANGE_ContractGetResponse
{
  /**
   * Full HTTP response.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details depending on the HTTP status code.
   */
  union
  {
    /**
     * Information returned on #MHD_HTTP_OK.
     */
    struct
    {

      /**
       * Public key of the purse.
       */
      struct TALER_PurseContractPublicKeyP purse_pub;

      /**
       * Encrypted contract.
       */
      const void *econtract;

      /**
       * Number of bytes in @e econtract.
       */
      size_t econtract_size;

    } ok;

  } details;

};

/**
 * Function called with information about the a purse.
 *
 * @param cls closure
 * @param cgr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ContractGetCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ContractGetResponse *cgr);


/**
 * @brief Handle for a GET /contracts/$CPUB request.
 */
struct TALER_EXCHANGE_ContractsGetHandle;


/**
 * Request information about a contract from the exchange.
 *
 * @param ctx CURL context
 * @param url exchange base URL
 * @param contract_priv private key of the contract
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ContractsGetHandle *
TALER_EXCHANGE_contract_get (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_ContractDiffiePrivateP *contract_priv,
  TALER_EXCHANGE_ContractGetCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_contract_get() operation.
 *
 * @param cgh handle of the operation to cancel
 */
void
TALER_EXCHANGE_contract_get_cancel (
  struct TALER_EXCHANGE_ContractsGetHandle *cgh);


/**
 * Response generated for a purse get request.
 */
struct TALER_EXCHANGE_PurseGetResponse
{
  /**
   * Full HTTP response.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details depending on the HTTP status.
   */
  union
  {
    /**
     * Response on #MHD_HTTP_OK.
     */
    struct
    {

      /**
       * Time when the purse was merged (or zero if it
       * was not merged).
       */
      struct GNUNET_TIME_Timestamp merge_timestamp;

      /**
       * Time when the full amount was deposited into
       * the purse (or zero if a sufficient amount
       * was not yet deposited).
       */
      struct GNUNET_TIME_Timestamp deposit_timestamp;

      /**
       * Reserve balance (how much was deposited in
       * total into the reserve, minus deposit fees).
       */
      struct TALER_Amount balance;

      /**
       * Time when the purse will expire.
       */
      struct GNUNET_TIME_Timestamp purse_expiration;

    } ok;

  } details;

};


/**
 * Function called with information about the a purse.
 *
 * @param cls closure
 * @param pgr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_PurseGetCallback) (
  void *cls,
  const struct TALER_EXCHANGE_PurseGetResponse *pgr);


/**
 * @brief Handle for a GET /purses/$PPUB request.
 */
struct TALER_EXCHANGE_PurseGetHandle;


/**
 * Request information about a purse from the exchange.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param keys exchange keys
 * @param purse_pub public key of the purse
 * @param timeout how long to wait for a change to happen
 * @param wait_for_merge true to wait for a merge event, otherwise wait for a deposit event
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_PurseGetHandle *
TALER_EXCHANGE_purse_get (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct GNUNET_TIME_Relative timeout,
  bool wait_for_merge,
  TALER_EXCHANGE_PurseGetCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_purse_get() operation.
 *
 * @param pgh handle of the operation to cancel
 */
void
TALER_EXCHANGE_purse_get_cancel (
  struct TALER_EXCHANGE_PurseGetHandle *pgh);


/**
 * Response generated for a purse creation request.
 */
struct TALER_EXCHANGE_PurseCreateDepositResponse
{
  /**
   * Full HTTP response.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details depending on the HTTP status.
   */
  union
  {

    /**
     * Detailed returned on #MHD_HTTP_OK.
     */
    struct
    {
      /**
       * Signing key used by the exchange to sign the
       * purse create with deposit confirmation.
       */
      struct TALER_ExchangePublicKeyP exchange_pub;

      /**
       * Signature from the exchange on the
       * purse create with deposit confirmation.
       */
      struct TALER_ExchangeSignatureP exchange_sig;


    } ok;

  } details;

};

/**
 * Function called with information about the creation
 * of a new purse.
 *
 * @param cls closure
 * @param pcr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_PurseCreateDepositCallback) (
  void *cls,
  const struct TALER_EXCHANGE_PurseCreateDepositResponse *pcr);


/**
 * @brief Handle for a POST /purses/$PID/create request.
 */
struct TALER_EXCHANGE_PurseCreateDepositHandle;


/**
 * Information about a coin to be deposited into a purse or reserve.
 */
struct TALER_EXCHANGE_PurseDeposit
{
  /**
   * Age commitment data, might be NULL.
   */
  const struct TALER_AgeCommitmentProof *age_commitment_proof;

  /**
   * Private key of the coin.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Signature proving the validity of the coin.
   */
  struct TALER_DenominationSignature denom_sig;

  /**
   * Hash of the denomination's public key.
   */
  struct TALER_DenominationHashP h_denom_pub;

  /**
   * Amount of the coin to transfer into the purse.
   */
  struct TALER_Amount amount;

};


/**
 * Inform the exchange that a purse should be created
 * and coins deposited into it.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param keys exchange keys
 * @param purse_priv private key of the purse
 * @param merge_priv the merge credential
 * @param contract_priv key needed to obtain and decrypt the contract
 * @param contract_terms contract the purse is about
 * @param num_deposits length of the @a deposits array
 * @param deposits array of deposits to make into the purse
 * @param upload_contract true to upload the contract; must
 *        be FALSE for repeated calls to this API for the
 *        same purse (i.e. when adding more deposits).
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_PurseCreateDepositHandle *
TALER_EXCHANGE_purse_create_with_deposit (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_PurseContractPrivateKeyP *purse_priv,
  const struct TALER_PurseMergePrivateKeyP *merge_priv,
  const struct TALER_ContractDiffiePrivateP *contract_priv,
  const json_t *contract_terms,
  unsigned int num_deposits,
  const struct TALER_EXCHANGE_PurseDeposit deposits[static num_deposits],
  bool upload_contract,
  TALER_EXCHANGE_PurseCreateDepositCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_purse_create_with_deposit() operation.
 *
 * @param pch handle of the operation to cancel
 */
void
TALER_EXCHANGE_purse_create_with_deposit_cancel (
  struct TALER_EXCHANGE_PurseCreateDepositHandle *pch);


/**
 * Response generated for a purse deletion request.
 */
struct TALER_EXCHANGE_PurseDeleteResponse
{
  /**
   * Full HTTP response.
   */
  struct TALER_EXCHANGE_HttpResponse hr;
};


/**
 * Function called with information about the deletion
 * of a purse.
 *
 * @param cls closure
 * @param pdr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_PurseDeleteCallback) (
  void *cls,
  const struct TALER_EXCHANGE_PurseDeleteResponse *pdr);


/**
 * @brief Handle for a DELETE /purses/$PID request.
 */
struct TALER_EXCHANGE_PurseDeleteHandle;


/**
 * Asks the exchange to delete a purse. Will only succeed if
 * the purse was not yet merged and did not yet time out.
 *
 * @param ctx CURL context
 * @param url exchange base URL
 * @param purse_priv private key of the purse
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_PurseDeleteHandle *
TALER_EXCHANGE_purse_delete (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_PurseContractPrivateKeyP *purse_priv,
  TALER_EXCHANGE_PurseDeleteCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_purse_delete() operation.
 *
 * @param pdh handle of the operation to cancel
 */
void
TALER_EXCHANGE_purse_delete_cancel (
  struct TALER_EXCHANGE_PurseDeleteHandle *pdh);


/**
 * Response generated for an account merge request.
 */
struct TALER_EXCHANGE_AccountMergeResponse
{
  /**
   * Full HTTP response.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Reserve signature affirming the merge.
   */
  const struct TALER_ReserveSignatureP *reserve_sig;

  /**
   * Details depending on the HTTP status.
   */
  union
  {
    /**
     * Detailed returned on #MHD_HTTP_OK.
     */
    struct
    {
      /**
       * Signature by the exchange affirming the merge.
       */
      struct TALER_ExchangeSignatureP exchange_sig;

      /**
       * Online signing key used by the exchange.
       */
      struct TALER_ExchangePublicKeyP exchange_pub;

      /**
       * Timestamp of the exchange for @e exchange_sig.
       */
      struct GNUNET_TIME_Timestamp etime;

    } ok;

    /**
     * Details if the status is #MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS.
     */
    struct
    {
      /**
       * Requirement row target that the merchant should use
       * to check for its KYC status.
       */
      uint64_t requirement_row;
    } unavailable_for_legal_reasons;

  } details;

};

/**
 * Function called with information about an account merge
 * operation.
 *
 * @param cls closure
 * @param amr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_AccountMergeCallback) (
  void *cls,
  const struct TALER_EXCHANGE_AccountMergeResponse *amr);


/**
 * @brief Handle for a POST /purses/$PID/merge request.
 */
struct TALER_EXCHANGE_AccountMergeHandle;


/**
 * Inform the exchange that a purse should be merged
 * with a reserve.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param keys exchange keys
 * @param reserve_exchange_url base URL of the exchange with the reserve
 * @param reserve_priv private key of the reserve to merge into
 * @param purse_pub public key of the purse to merge
 * @param merge_priv private key granting us the right to merge
 * @param h_contract_terms hash of the purses' contract
 * @param min_age minimum age of deposits into the purse
 * @param purse_value_after_fees amount that should be in the purse
 * @param purse_expiration when will the purse expire
 * @param merge_timestamp when is the merge happening (current time)
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_AccountMergeHandle *
TALER_EXCHANGE_account_merge (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const char *reserve_exchange_url,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergePrivateKeyP *merge_priv,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  uint8_t min_age,
  const struct TALER_Amount *purse_value_after_fees,
  struct GNUNET_TIME_Timestamp purse_expiration,
  struct GNUNET_TIME_Timestamp merge_timestamp,
  TALER_EXCHANGE_AccountMergeCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_account_merge() operation.
 *
 * @param amh handle of the operation to cancel
 */
void
TALER_EXCHANGE_account_merge_cancel (
  struct TALER_EXCHANGE_AccountMergeHandle *amh);


/**
 * Response generated for a purse creation request.
 */
struct TALER_EXCHANGE_PurseCreateMergeResponse
{
  /**
   * Full HTTP response.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Reserve signature generated for the request
   * (client-side).
   */
  const struct TALER_ReserveSignatureP *reserve_sig;

  /**
   * Details depending on the HTTP status.
   */
  union
  {
    /**
     * Details returned on #MHD_HTTP_OK.
     */
    struct
    {

    } ok;

    /**
   * Details if the status is #MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS.
   */
    struct
    {
      /**
       * Requirement row that the merchant should use
       * to check for its KYC status.
       */
      uint64_t requirement_row;
    } unavailable_for_legal_reasons;

  } details;

};

/**
 * Function called with information about the creation
 * of a new purse.
 *
 * @param cls closure
 * @param pcr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_PurseCreateMergeCallback) (
  void *cls,
  const struct TALER_EXCHANGE_PurseCreateMergeResponse *pcr);


/**
 * @brief Handle for a POST /reserves/$RID/purse request.
 */
struct TALER_EXCHANGE_PurseCreateMergeHandle;


/**
 * Inform the exchange that a purse should be created
 * and merged with a reserve.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param keys exchange keys
 * @param reserve_priv private key of the reserve
 * @param purse_priv private key of the purse
 * @param merge_priv private key of the merge capability
 * @param contract_priv private key to get the contract
 * @param contract_terms contract the purse is about
 * @param upload_contract true to upload the contract
 * @param pay_for_purse true to pay for purse creation
 * @param merge_timestamp when should the merge happen (use current time)
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_PurseCreateMergeHandle *
TALER_EXCHANGE_purse_create_with_merge (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  const struct TALER_PurseContractPrivateKeyP *purse_priv,
  const struct TALER_PurseMergePrivateKeyP *merge_priv,
  const struct TALER_ContractDiffiePrivateP *contract_priv,
  const json_t *contract_terms,
  bool upload_contract,
  bool pay_for_purse,
  struct GNUNET_TIME_Timestamp merge_timestamp,
  TALER_EXCHANGE_PurseCreateMergeCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_purse_create_with_merge() operation.
 *
 * @param pcm handle of the operation to cancel
 */
void
TALER_EXCHANGE_purse_create_with_merge_cancel (
  struct TALER_EXCHANGE_PurseCreateMergeHandle *pcm);


/**
 * Response generated for purse deposit request.
 */
struct TALER_EXCHANGE_PurseDepositResponse
{
  /**
   * Full HTTP response.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details depending on the HTTP status.
   */
  union
  {
    /**
     * Detailed returned on #MHD_HTTP_OK.
     */
    struct
    {

      /**
       * When does the purse expire.
       */
      struct GNUNET_TIME_Timestamp purse_expiration;

      /**
       * How much was actually deposited into the purse.
       */
      struct TALER_Amount total_deposited;

      /**
       * How much should be in the purse in total in the end.
       */
      struct TALER_Amount purse_value_after_fees;

      /**
       * Hash of the contract (needed to verify signature).
       */
      struct TALER_PrivateContractHashP h_contract_terms;

    } ok;
  } details;

};

/**
 * Function called with information about a purse-deposit
 * operation.
 *
 * @param cls closure
 * @param pdr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_PurseDepositCallback) (
  void *cls,
  const struct TALER_EXCHANGE_PurseDepositResponse *pdr);


/**
 * @brief Handle for a POST /purses/$PID/deposit request.
 */
struct TALER_EXCHANGE_PurseDepositHandle;


/**
 * Inform the exchange that a deposit should be made into
 * a purse.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param keys exchange keys
 * @param purse_exchange_url base URL of the exchange hosting the purse
 * @param purse_pub public key of the purse to merge
 * @param min_age minimum age we need to prove for the purse
 * @param num_deposits length of the @a deposits array
 * @param deposits array of deposits to make into the purse
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_PurseDepositHandle *
TALER_EXCHANGE_purse_deposit (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const char *purse_exchange_url,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  uint8_t min_age,
  unsigned int num_deposits,
  const struct TALER_EXCHANGE_PurseDeposit deposits[static num_deposits],
  TALER_EXCHANGE_PurseDepositCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_purse_deposit() operation.
 *
 * @param amh handle of the operation to cancel
 */
void
TALER_EXCHANGE_purse_deposit_cancel (
  struct TALER_EXCHANGE_PurseDepositHandle *amh);


/* *********************  /reserves/$RID/open *********************** */


/**
 * @brief A /reserves/$RID/open Handle
 */
struct TALER_EXCHANGE_ReservesOpenHandle;


/**
 * @brief Reserve open result details.
 */
struct TALER_EXCHANGE_ReserveOpenResult
{

  /**
   * High-level HTTP response details.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details depending on @e hr.http_status.
   */
  union
  {

    /**
     * Information returned on success, if
     * @e hr.http_status is #MHD_HTTP_OK
     */
    struct
    {
      /**
       * New expiration time
       */
      struct GNUNET_TIME_Timestamp expiration_time;

      /**
       * Actual cost of the open operation.
       */
      struct TALER_Amount open_cost;

    } ok;


    /**
     * Information returned if the payment provided is insufficient, if
     * @e hr.http_status is #MHD_HTTP_PAYMENT_REQUIRED
     */
    struct
    {
      /**
       * Current expiration time of the reserve.
       */
      struct GNUNET_TIME_Timestamp expiration_time;

      /**
       * Actual cost of the open operation that should have been paid.
       */
      struct TALER_Amount open_cost;

    } payment_required;


    /**
     * Information returned if KYC is required to proceed, set if
     * @e hr.http_status is #MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS.
     */
    struct
    {
      /**
       * Requirement row that the merchant should use
       * to check for its KYC status.
       */
      uint64_t requirement_row;

      /**
       * Hash of the payto-URI of the account to KYC;
       */
      struct TALER_PaytoHashP h_payto;

    } unavailable_for_legal_reasons;

  } details;

};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * reserve open request to a exchange.
 *
 * @param cls closure
 * @param ror HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ReservesOpenCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ReserveOpenResult *ror);


/**
 * Submit a request to open a reserve.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param keys exchange keys
 * @param reserve_priv private key of the reserve to open
 * @param reserve_contribution amount to pay from the reserve's balance for the operation
 * @param coin_payments_length length of the @a coin_payments array
 * @param coin_payments array of coin payments to use for opening the reserve
 * @param expiration_time desired new expiration time for the reserve
 * @param min_purses minimum number of purses to allow being concurrently opened per reserve
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_EXCHANGE_ReservesOpenHandle *
TALER_EXCHANGE_reserves_open (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  const struct TALER_Amount *reserve_contribution,
  unsigned int coin_payments_length,
  const struct TALER_EXCHANGE_PurseDeposit coin_payments[
    static coin_payments_length],
  struct GNUNET_TIME_Timestamp expiration_time,
  uint32_t min_purses,
  TALER_EXCHANGE_ReservesOpenCallback cb,
  void *cb_cls);


/**
 * Cancel a reserve status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param[in] roh the reserve open request handle
 */
void
TALER_EXCHANGE_reserves_open_cancel (
  struct TALER_EXCHANGE_ReservesOpenHandle *roh);


/* *********************  /reserves/$RID/attest *********************** */


/**
 * @brief A Get /reserves/$RID/attest Handle
 */
struct TALER_EXCHANGE_ReservesGetAttestHandle;


/**
 * @brief Reserve GET attest result details.
 */
struct TALER_EXCHANGE_ReserveGetAttestResult
{

  /**
   * High-level HTTP response details.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details depending on @e hr.http_status.
   */
  union
  {

    /**
     * Information returned on success, if
     * @e hr.http_status is #MHD_HTTP_OK
     */
    struct
    {

      /**
       * Length of the @e attributes array.
       */
      unsigned int attributes_length;

      /**
       * Array of attributes available about the user.
       */
      const char **attributes;

    } ok;

  } details;

};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * reserve attest request to a exchange.
 *
 * @param cls closure
 * @param ror HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ReservesGetAttestCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ReserveGetAttestResult *ror);


/**
 * Submit a request to get the list of attestable attributes for a reserve.
 *
 * @param ctx CURL context
 * @param url exchange base URL
 * @param reserve_pub public key of the reserve to get available attributes for
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_EXCHANGE_ReservesGetAttestHandle *
TALER_EXCHANGE_reserves_get_attestable (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  TALER_EXCHANGE_ReservesGetAttestCallback cb,
  void *cb_cls);


/**
 * Cancel a request to get attestable attributes.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param rgah the reserve get attestable request handle
 */
void
TALER_EXCHANGE_reserves_get_attestable_cancel (
  struct TALER_EXCHANGE_ReservesGetAttestHandle *rgah);


/**
 * @brief A POST /reserves/$RID/attest Handle
 */
struct TALER_EXCHANGE_ReservesPostAttestHandle;


/**
 * @brief Reserve attest result details.
 */
struct TALER_EXCHANGE_ReservePostAttestResult
{

  /**
   * High-level HTTP response details.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details depending on @e hr.http_status.
   */
  union
  {

    /**
     * Information returned on success, if
     * @e hr.http_status is #MHD_HTTP_OK
     */
    struct
    {
      /**
       * Time when the exchange made the signature.
       */
      struct GNUNET_TIME_Timestamp exchange_time;

      /**
       * Expiration time of the attested attributes.
       */
      struct GNUNET_TIME_Timestamp expiration_time;

      /**
       * Signature by the exchange affirming the attributes.
       */
      struct TALER_ExchangeSignatureP exchange_sig;

      /**
       * Online signing key used by the exchange.
       */
      struct TALER_ExchangePublicKeyP exchange_pub;

      /**
       * Attributes being confirmed by the exchange.
       */
      const json_t *attributes;

    } ok;

  } details;

};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * reserve attest request to a exchange.
 *
 * @param cls closure
 * @param ror HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ReservesPostAttestCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ReservePostAttestResult *ror);


/**
 * Submit a request to attest attributes about the owner of a reserve.
 *
 * @param ctx CURL context
 * @param url exchange base URL
 * @param reserve_priv private key of the reserve to attest
 * @param attributes_length length of the @a attributes array
 * @param attributes array of names of attributes to get attestations for
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_EXCHANGE_ReservesAttestHandle *
TALER_EXCHANGE_reserves_attest (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  unsigned int attributes_length,
  const char *attributes[const static attributes_length],
  TALER_EXCHANGE_ReservesPostAttestCallback cb,
  void *cb_cls);


/**
 * Cancel a reserve attestation request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param rah the reserve attest request handle
 */
void
TALER_EXCHANGE_reserves_attest_cancel (
  struct TALER_EXCHANGE_ReservesAttestHandle *rah);


/* *********************  /reserves/$RID/close *********************** */


/**
 * @brief A /reserves/$RID/close Handle
 */
struct TALER_EXCHANGE_ReservesCloseHandle;


/**
 * @brief Reserve close result details.
 */
struct TALER_EXCHANGE_ReserveCloseResult
{

  /**
   * High-level HTTP response details.
   */
  struct TALER_EXCHANGE_HttpResponse hr;

  /**
   * Details depending on @e hr.http_status.
   */
  union
  {

    /**
     * Information returned on success, if
     * @e hr.http_status is #MHD_HTTP_OK
     */
    struct
    {

      /**
       * Amount wired to the target account.
       */
      struct TALER_Amount wire_amount;
    } ok;

    /**
     * Information returned if KYC is required to proceed, set if
     * @e hr.http_status is #MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS.
     */
    struct
    {
      /**
       * Requirement row that the merchant should use
       * to check for its KYC status.
       */
      uint64_t requirement_row;

      /**
       * Hash of the payto-URI of the account to KYC;
       */
      struct TALER_PaytoHashP h_payto;

    } unavailable_for_legal_reasons;

  } details;

};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * reserve close request to a exchange.
 *
 * @param cls closure
 * @param ror HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ReservesCloseCallback) (
  void *cls,
  const struct TALER_EXCHANGE_ReserveCloseResult *ror);


/**
 * Submit a request to close a reserve.
 *
 * @param ctx curl context
 * @param url exchange base URL
 * @param reserve_priv private key of the reserve to close
 * @param target_payto_uri where to send the payment, NULL to send to reserve origin
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_EXCHANGE_ReservesCloseHandle *
TALER_EXCHANGE_reserves_close (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  const char *target_payto_uri,
  TALER_EXCHANGE_ReservesCloseCallback cb,
  void *cb_cls);


/**
 * Cancel a reserve status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param rch the reserve request handle
 */
void
TALER_EXCHANGE_reserves_close_cancel (
  struct TALER_EXCHANGE_ReservesCloseHandle *rch);

#endif  /* _TALER_EXCHANGE_SERVICE_H */
