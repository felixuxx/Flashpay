/*
   This file is part of TALER
   Copyright (C) 2014-2021 Taler Systems SA

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
 */
#ifndef _TALER_EXCHANGE_SERVICE_H
#define _TALER_EXCHANGE_SERVICE_H

#include <jansson.h>
#include "taler_util.h"
#include "taler_error_codes.h"
#include <gnunet/gnunet_curl_lib.h>


/* *********************  /keys *********************** */

/**
 * List of possible options to be passed to
 * #TALER_EXCHANGE_connect().
 */
enum TALER_EXCHANGE_Option
{
  /**
   * Terminator (end of option list).
   */
  TALER_EXCHANGE_OPTION_END = 0,

  /**
   * Followed by a "const json_t *" that was previously returned for
   * this exchange URL by #TALER_EXCHANGE_serialize_data().  Used to
   * resume a connection to an exchange without having to re-download
   * /keys data (or at least only download the deltas).
   */
  TALER_EXCHANGE_OPTION_DATA

};


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
  struct TALER_DenominationHash h_key;

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

  /**
   * Set to true if this denomination key has been
   * revoked by the exchange.
   */
  bool revoked;

  /**
   * Is the denomination age-restricted?
   */
  bool age_restricted;
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
 * @brief Information about keys from the exchange.
 */
struct TALER_EXCHANGE_Keys
{

  /**
   * Long-term offline signing key of the exchange.
   */
  struct TALER_MasterPublicKeyP master_pub;

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
   * How long after a reserve went idle will the exchange close it?
   * This is an approximate number, not cryptographically signed by
   * the exchange (advisory-only, may change anytime).
   */
  struct GNUNET_TIME_Relative reserve_closing_delay;

  /**
   * Maximum amount a wallet is allowed to hold from
   * this exchange before it must undergo a KYC check.
   */
  struct TALER_Amount wallet_balance_limit_without_kyc;

  /**
   * Timestamp indicating the /keys generation.
   */
  struct GNUNET_TIME_Timestamp list_issue_date;

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
 * Function called with information about who is auditing
 * a particular exchange and what keys the exchange is using.
 *
 * @param cls closure
 * @param hr HTTP response data
 * @param keys information about the various keys used
 *        by the exchange, NULL if /keys failed
 * @param compat protocol compatibility information
 */
typedef void
(*TALER_EXCHANGE_CertificationCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr,
  const struct TALER_EXCHANGE_Keys *keys,
  enum TALER_EXCHANGE_VersionCompatibility compat);


/**
 * @brief Handle to the exchange.  This is where we interact with
 * a particular exchange and keep the per-exchange information.
 */
struct TALER_EXCHANGE_Handle;


/**
 * Initialise a connection to the exchange.  Will connect to the
 * exchange and obtain information about the exchange's master public
 * key and the exchange's auditor.  The respective information will
 * be passed to the @a cert_cb once available, and all future
 * interactions with the exchange will be checked to be signed
 * (where appropriate) by the respective master key.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param cert_cb function to call with the exchange's certification information,
 *                possibly called repeatedly if the information changes
 * @param cert_cb_cls closure for @a cert_cb
 * @param ... list of additional arguments, terminated by #TALER_EXCHANGE_OPTION_END.
 * @return the exchange handle; NULL upon error
 */
struct TALER_EXCHANGE_Handle *
TALER_EXCHANGE_connect (struct GNUNET_CURL_Context *ctx,
                        const char *url,
                        TALER_EXCHANGE_CertificationCallback cert_cb,
                        void *cert_cb_cls,
                        ...);


/**
 * Serialize the latest key data from @a exchange to be persisted
 * on disk (to be used with #TALER_EXCHANGE_OPTION_DATA to more
 * efficiently recover the state).
 *
 * @param exchange which exchange's key and wire data should be serialized
 * @return NULL on error (i.e. no current data available); otherwise
 *         json object owned by the caller
 */
json_t *
TALER_EXCHANGE_serialize_data (struct TALER_EXCHANGE_Handle *exchange);


/**
 * Disconnect from the exchange.
 *
 * @param exchange the exchange handle
 */
void
TALER_EXCHANGE_disconnect (struct TALER_EXCHANGE_Handle *exchange);


/**
 * Obtain the keys from the exchange.
 *
 * @param exchange the exchange handle
 * @return the exchange's key set
 */
const struct TALER_EXCHANGE_Keys *
TALER_EXCHANGE_get_keys (struct TALER_EXCHANGE_Handle *exchange);


/**
 * Let the user set the last valid denomination time manually.
 *
 * @param exchange the exchange handle.
 * @param last_denom_new new last denomination time.
 */
void
TALER_EXCHANGE_set_last_denom (struct TALER_EXCHANGE_Handle *exchange,
                               struct GNUNET_TIME_Timestamp last_denom_new);


/**
 * Flags for #TALER_EXCHANGE_check_keys_current().
 */
enum TALER_EXCHANGE_CheckKeysFlags
{
  /**
   * No special options.
   */
  TALER_EXCHANGE_CKF_NONE,

  /**
   * Force downloading /keys now, even if /keys is still valid
   * (that is, the period advertised by the exchange for re-downloads
   * has not yet expired).
   */
  TALER_EXCHANGE_CKF_FORCE_DOWNLOAD = 1,

  /**
   * Pull all keys again, resetting the client state to the original state.
   * Using this flag disables the incremental download, and also prevents using
   * the context until the re-download has completed.
   */
  TALER_EXCHANGE_CKF_PULL_ALL_KEYS = 2,

  /**
   * Force downloading all keys now.
   */
  TALER_EXCHANGE_CKF_FORCE_ALL_NOW = TALER_EXCHANGE_CKF_FORCE_DOWNLOAD
                                     | TALER_EXCHANGE_CKF_PULL_ALL_KEYS

};


/**
 * Check if our current response for /keys is valid, and if
 * not, trigger /keys download.
 *
 * @param exchange exchange to check keys for
 * @param flags options controlling when to download what
 * @return until when the existing response is current, 0 if we are re-downloading now
 */
struct GNUNET_TIME_Timestamp
TALER_EXCHANGE_check_keys_current (struct TALER_EXCHANGE_Handle *exchange,
                                   enum TALER_EXCHANGE_CheckKeysFlags flags);


/**
 * Obtain the keys from the exchange in the raw JSON format.
 *
 * @param exchange the exchange handle
 * @return the exchange's keys in raw JSON
 */
json_t *
TALER_EXCHANGE_get_keys_raw (struct TALER_EXCHANGE_Handle *exchange);


/**
 * Test if the given @a pub is a the current signing key from the exchange
 * according to @a keys.
 *
 * @param keys the exchange's key set
 * @param pub claimed current online signing key for the exchange
 * @return #GNUNET_OK if @a pub is (according to /keys) a current signing key
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_test_signing_key (const struct TALER_EXCHANGE_Keys *keys,
                                 const struct TALER_ExchangePublicKeyP *pub);


/**
 * Get exchange's base URL.
 *
 * @param exchange exchange handle.
 * @return the base URL from the handle.
 */
const char *
TALER_EXCHANGE_get_base_url (const struct TALER_EXCHANGE_Handle *exchange);


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
 * Create a copy of a denomination public key.
 *
 * @param key key to copy
 * @returns a copy, must be freed with #TALER_EXCHANGE_destroy_denomination_key
 */
struct TALER_EXCHANGE_DenomPublicKey *
TALER_EXCHANGE_copy_denomination_key (
  const struct TALER_EXCHANGE_DenomPublicKey *key);


/**
 * Destroy a denomination public key.
 * Should only be called with keys created by #TALER_EXCHANGE_copy_denomination_key.
 *
 * @param key key to destroy.
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
  const struct TALER_DenominationHash *hc);


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
 * Sorted list of fees to be paid for aggregate wire transfers.
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
  struct TALER_Amount wire_fee;

  /**
   * Fee to be paid when the exchange closes a reserve and wires funds
   * back to a customer.
   */
  struct TALER_Amount closing_fee;

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
 * Information about a wire account of the exchange.
 */
struct TALER_EXCHANGE_WireAccount
{
  /**
   * payto://-URI of the exchange.
   */
  const char *payto_uri;

  /**
   * Signature of the exchange over the account (was checked by the API).
   */
  struct TALER_MasterSignatureP master_sig;

  /**
   * Linked list of wire fees the exchange charges for
   * accounts of the wire method matching @e payto_uri.
   */
  const struct TALER_EXCHANGE_WireAggregateFees *fees;

};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * wire format inquiry request to a exchange.
 *
 * If the request fails to generate a valid response from the
 * exchange, @a http_status will also be zero.
 *
 * @param cls closure
 * @param hr HTTP response data
 * @param accounts_len length of the @a accounts array
 * @param accounts list of wire accounts of the exchange, NULL on error
 */
typedef void
(*TALER_EXCHANGE_WireCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr,
  unsigned int accounts_len,
  const struct TALER_EXCHANGE_WireAccount *accounts);


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
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param wire_cb the callback to call when a reply for this request is available
 * @param wire_cb_cls closure for the above callback
 * @return a handle for this request
 */
struct TALER_EXCHANGE_WireHandle *
TALER_EXCHANGE_wire (struct TALER_EXCHANGE_Handle *exchange,
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
 * Sign a deposit permission.  Function for wallets.
 *
 * @param amount the amount to be deposited
 * @param deposit_fee the deposit fee we expect to pay
 * @param h_wire hash of the merchant’s account details
 * @param h_contract_terms hash of the contact of the merchant with the customer (further details are never disclosed to the exchange)
 * @param h_extensions hash over the extensions
 * @param h_denom_pub hash of the coin denomination's public key
 * @param coin_priv coin’s private key
 * @param wallet_timestamp timestamp when the contract was finalized, must not be too far in the future
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the exchange (can be zero if refunds are not allowed); must not be after the @a wire_deadline
 * @param[out] coin_sig set to the signature made with purpose #TALER_SIGNATURE_WALLET_COIN_DEPOSIT
 */
void
TALER_EXCHANGE_deposit_permission_sign (
  const struct TALER_Amount *amount,
  const struct TALER_Amount *deposit_fee,
  const struct TALER_MerchantWireHash *h_wire,
  const struct TALER_PrivateContractHash *h_contract_terms,
  const struct TALER_ExtensionContractHash *h_extensions,
  const struct TALER_DenominationHash *h_denom_pub,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct GNUNET_TIME_Timestamp wallet_timestamp,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  struct GNUNET_TIME_Timestamp refund_deadline,
  struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * @brief A Deposit Handle
 */
struct TALER_EXCHANGE_DepositHandle;


/**
 * Structure with information about a deposit
 * operation's result.
 */
struct TALER_EXCHANGE_DepositResult
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
       * Time when the exchange generated the deposit confirmation
       */
      struct GNUNET_TIME_Timestamp deposit_timestamp;

      /**
       * signature provided by the exchange
       */
      const struct TALER_ExchangeSignatureP *exchange_sig;

      /**
       * exchange key used to sign @a exchange_sig.
       */
      const struct TALER_ExchangePublicKeyP *exchange_pub;

      /**
       * Base URL for looking up wire transfers, or
       * NULL to use the default base URL.
       */
      const char *transaction_base_url;

    } success;

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
(*TALER_EXCHANGE_DepositResultCallback) (
  void *cls,
  const struct TALER_EXCHANGE_DepositResult *dr);


/**
 * Submit a deposit permission to the exchange and get the exchange's
 * response.  This API is typically used by a merchant.  Note that
 * while we return the response verbatim to the caller for further
 * processing, we do already verify that the response is well-formed
 * (i.e. that signatures included in the response are all valid).  If
 * the exchange's reply is not well-formed, we return an HTTP status code
 * of zero to @a cb.
 *
 * We also verify that the @a coin_sig is valid for this deposit
 * request, and that the @a ub_sig is a valid signature for @a
 * coin_pub.  Also, the @a exchange must be ready to operate (i.e.  have
 * finished processing the /keys reply).  If either check fails, we do
 * NOT initiate the transaction with the exchange and instead return NULL.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param amount the amount to be deposited
 * @param wire_deadline execution date, until which the merchant would like the exchange to settle the balance (advisory, the exchange cannot be
 *        forced to settle in the past or upon very short notice, but of course a well-behaved exchange will limit aggregation based on the advice received)
 * @param merchant_payto_uri the merchant’s account details, in the payto://-format supported by the exchange
 * @param wire_salt salt used to hash the @a merchant_payto_uri
 * @param h_contract_terms hash of the contact of the merchant with the customer (further details are never disclosed to the exchange)
 * @param extension_details extension-specific details about the deposit relevant to the exchange
 * @param coin_pub coin’s public key
 * @param denom_pub denomination key with which the coin is signed
 * @param denom_sig exchange’s unblinded signature of the coin
 * @param timestamp timestamp when the contract was finalized, must match approximately the current time of the exchange
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the exchange (can be zero if refunds are not allowed); must not be after the @a wire_deadline
 * @param coin_sig the signature made with purpose #TALER_SIGNATURE_WALLET_COIN_DEPOSIT made by the customer with the coin’s private key.
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @param[out] ec if NULL is returned, set to the error code explaining why the operation failed
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_EXCHANGE_DepositHandle *
TALER_EXCHANGE_deposit (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_Amount *amount,
  struct GNUNET_TIME_Timestamp wire_deadline,
  const char *merchant_payto_uri,
  const struct TALER_WireSalt *wire_salt,
  const struct TALER_PrivateContractHash *h_contract_terms,
  const json_t *extension_details,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_DenominationSignature *denom_sig,
  const struct TALER_DenominationPublicKey *denom_pub,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  struct GNUNET_TIME_Timestamp refund_deadline,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  TALER_EXCHANGE_DepositResultCallback cb,
  void *cb_cls,
  enum TALER_ErrorCode *ec);


/**
 * Change the chance that our deposit confirmation will be given to the
 * auditor to 100%.
 *
 * @param deposit the deposit permission request handle
 */
void
TALER_EXCHANGE_deposit_force_dc (struct TALER_EXCHANGE_DepositHandle *deposit);


/**
 * Cancel a deposit permission request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param deposit the deposit permission request handle
 */
void
TALER_EXCHANGE_deposit_cancel (struct TALER_EXCHANGE_DepositHandle *deposit);


/* *********************  /coins/$COIN_PUB/refund *********************** */

/**
 * @brief A Refund Handle
 */
struct TALER_EXCHANGE_RefundHandle;


/**
 * Callbacks of this type are used to serve the result of submitting a
 * refund request to an exchange.
 *
 * @param cls closure
 * @param hr HTTP response data
 * @param sign_key exchange key used to sign @a obj, or NULL
 * @param signature the actual signature, or NULL on error
 */
typedef void
(*TALER_EXCHANGE_RefundCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr,
  const struct TALER_ExchangePublicKeyP *sign_key,
  const struct TALER_ExchangeSignatureP *signature);


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
 * @param exchange the exchange handle; the exchange must be ready to operate
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
TALER_EXCHANGE_refund (struct TALER_EXCHANGE_Handle *exchange,
                       const struct TALER_Amount *amount,
                       const struct TALER_PrivateContractHash *h_contract_terms,
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


/* ********************* GET /reserves/$RESERVE_PUB *********************** */


/**
 * @brief A /reserves/ GET Handle
 */
struct TALER_EXCHANGE_ReservesGetHandle;


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
  TALER_EXCHANGE_RTT_CLOSE

};


/**
 * @brief Entry in the reserve's transaction history.
 */
struct TALER_EXCHANGE_ReserveHistory
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

  } details;

};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * reserve status request to a exchange.
 *
 * @param cls closure
 * @param hr HTTP response data
 * @param balance current balance in the reserve, NULL on error
 * @param history_length number of entries in the transaction history, 0 on error
 * @param history detailed transaction history, NULL on error
 */
typedef void
(*TALER_EXCHANGE_ReservesGetCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr,
  const struct TALER_Amount *balance,
  unsigned int history_length,
  const struct TALER_EXCHANGE_ReserveHistory *history);


/**
 * Submit a request to obtain the transaction history of a reserve
 * from the exchange.  Note that while we return the full response to the
 * caller for further processing, we do already verify that the
 * response is well-formed (i.e. that signatures included in the
 * response are all valid and add up to the balance).  If the exchange's
 * reply is not well-formed, we return an HTTP status code of zero to
 * @a cb.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
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
  struct TALER_EXCHANGE_Handle *exchange,
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


/* ********************* POST /reserves/$RESERVE_PUB/withdraw *********************** */


/**
 * @brief A /reserves/$RESERVE_PUB/withdraw Handle
 */
struct TALER_EXCHANGE_WithdrawHandle;


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
    struct
    {
      /**
       * Signature over the coin.
       */
      struct TALER_DenominationSignature sig;
    } success;

    /**
     * Details if the status is #MHD_HTTP_ACCEPTED.
     */
    struct
    {
      /**
       * Payment target that the merchant should use
       * to check for its KYC status.
       */
      uint64_t payment_target_uuid;
    } accepted;

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
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param pk kind of coin to create
 * @param reserve_priv private key of the reserve to withdraw from
 * @param ps secrets of the planchet
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for @a res_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_WithdrawHandle *
TALER_EXCHANGE_withdraw (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_EXCHANGE_DenomPublicKey *pk,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  const struct TALER_PlanchetSecretsP *ps,
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
 * Callbacks of this type are used to serve the result of submitting a
 * withdraw request to a exchange without the (un)blinding factor.
 *
 * @param cls closure
 * @param hr HTTP response data
 * @param blind_sig blind signature over the coin, NULL on error
 */
typedef void
(*TALER_EXCHANGE_Withdraw2Callback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr,
  const struct TALER_BlindedDenominationSignature *blind_sig);


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
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param pd planchet details of the planchet to withdraw
 * @param reserve_priv private key of the reserve to withdraw from
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for @a res_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_Withdraw2Handle *
TALER_EXCHANGE_withdraw2 (struct TALER_EXCHANGE_Handle *exchange,
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


/* ********************* /refresh/melt+reveal ***************************** */


/**
 * Melt (partially spent) coins to obtain fresh coins that are
 * unlinkable to the original coin(s).  Note that melting more
 * than one coin in a single request will make those coins linkable,
 * so the safest operation only melts one coin at a time.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, is operation does
 * not actually initiate the request. Instead, it generates a buffer
 * which the caller must store before proceeding with the actual call
 * to #TALER_EXCHANGE_melt() that will generate the request.
 *
 * This function does verify that the given request data is internally
 * consistent.  However, the @a melts_sigs are NOT verified.
 *
 * Aside from some non-trivial cryptographic operations that might
 * take a bit of CPU time to complete, this function returns
 * its result immediately and does not start any asynchronous
 * processing.  This function is also thread-safe.
 *
 * @param melt_priv private keys of the coin to melt
 * @param melt_amount amount specifying how much
 *                     the coin will contribute to the melt (including fee)
 * @param melt_sig signatures affirming the
 *                   validity of the public keys corresponding to the
 *                   @a melt_priv private key
 * @param melt_pk denomination key information
 *                   record corresponding to the @a melt_sig
 *                   validity of the keys
 * @param fresh_pks_len length of the @a pks array
 * @param fresh_pks array of @a pks_len denominations of fresh coins to create
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         Otherwise, JSON data structure to store persistently
 *         before proceeding to #TALER_EXCHANGE_melt().
 *         Non-null results should be freed using GNUNET_free().
 */
json_t *
TALER_EXCHANGE_refresh_prepare (
  const struct TALER_CoinSpendPrivateKeyP *melt_priv,
  const struct TALER_Amount *melt_amount,
  const struct TALER_DenominationSignature *melt_sig,
  const struct TALER_EXCHANGE_DenomPublicKey *melt_pk,
  unsigned int fresh_pks_len,
  const struct TALER_EXCHANGE_DenomPublicKey *fresh_pks);


/* ********************* /coins/$COIN_PUB/melt ***************************** */

/**
 * @brief A /coins/$COIN_PUB/melt Handle
 */
struct TALER_EXCHANGE_MeltHandle;


/**
 * Callbacks of this type are used to notify the application about the result
 * of the /coins/$COIN_PUB/melt stage.  If successful, the @a noreveal_index
 * should be committed to disk prior to proceeding
 * #TALER_EXCHANGE_refreshes_reveal().
 *
 * @param cls closure
 * @param hr HTTP response data
 * @param noreveal_index choice by the exchange in the cut-and-choose protocol,
 *                    UINT32_MAX on error
 * @param sign_key exchange key used to sign @a full_response, or NULL
 */
typedef void
(*TALER_EXCHANGE_MeltCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr,
  uint32_t noreveal_index,
  const struct TALER_ExchangePublicKeyP *sign_key);


/**
 * Submit a melt request to the exchange and get the exchange's
 * response.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, the provided
 * argument should have been constructed using
 * #TALER_EXCHANGE_refresh_prepare and committed to persistent storage
 * prior to calling this function.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param refresh_data the refresh data as returned from
 #TALER_EXCHANGE_refresh_prepare())
 * @param melt_cb the callback to call with the result
 * @param melt_cb_cls closure for @a melt_cb
 * @return a handle for this request; NULL if the argument was invalid.
 *         In this case, neither callback will be called.
 */
struct TALER_EXCHANGE_MeltHandle *
TALER_EXCHANGE_melt (struct TALER_EXCHANGE_Handle *exchange,
                     const json_t *refresh_data,
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
 * Callbacks of this type are used to return the final result of
 * submitting a refresh request to a exchange.  If the operation was
 * successful, this function returns the signatures over the coins
 * that were remelted.  The @a coin_privs and @a sigs arrays give the
 * coins in the same order (and should have the same length) in which
 * the original request specified the respective denomination keys.
 *
 * @param cls closure
 * @param hr HTTP response data
 * @param num_coins number of fresh coins created, length of the @a sigs and @a coin_privs arrays, 0 if the operation failed
 * @param coin_privs array of @a num_coins private keys for the coins that were created, NULL on error
 * @param sigs array of signature over @a num_coins coins, NULL on error
 */
typedef void
(*TALER_EXCHANGE_RefreshesRevealCallback)(
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr,
  unsigned int num_coins,
  const struct TALER_PlanchetSecretsP *coin_privs,
  const struct TALER_DenominationSignature *sigs);


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
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param refresh_data the refresh data as returned from
 #TALER_EXCHANGE_refresh_prepare())
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
  struct TALER_EXCHANGE_Handle *exchange,
  const json_t *refresh_data,
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
 * Callbacks of this type are used to return the final result of submitting a
 * /coins/$COIN_PUB/link request to a exchange.  If the operation was
 * successful, this function returns the signatures over the coins that were
 * created when the original coin was melted.
 *
 * @param cls closure
 * @param hr HTTP response data
 * @param num_coins number of fresh coins created, length of the @a sigs and @a coin_privs arrays, 0 if the operation failed
 * @param coin_privs array of @a num_coins private keys for the coins that were created, NULL on error
 * @param sigs array of signature over @a num_coins coins, NULL on error
 * @param pubs array of public keys for the @a sigs, NULL on error
 */
typedef void
(*TALER_EXCHANGE_LinkCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr,
  unsigned int num_coins,
  const struct TALER_CoinSpendPrivateKeyP *coin_privs,
  const struct TALER_DenominationSignature *sigs,
  const struct TALER_DenominationPublicKey *pubs);


/**
 * Submit a link request to the exchange and get the exchange's response.
 *
 * This API is typically not used by anyone, it is more a threat against those
 * trying to receive a funds transfer by abusing the refresh protocol.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param coin_priv private key to request link data for
 * @param link_cb the callback to call with the useful result of the
 *        refresh operation the @a coin_priv was involved in (if any)
 * @param link_cb_cls closure for @a link_cb
 * @return a handle for this request
 */
struct TALER_EXCHANGE_LinkHandle *
TALER_EXCHANGE_link (struct TALER_EXCHANGE_Handle *exchange,
                     const struct TALER_CoinSpendPrivateKeyP *coin_priv,
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
  struct TALER_PaytoHash h_payto;

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
 * Function called with detailed wire transfer data, including all
 * of the coin transactions that were combined into the wire transfer.
 *
 * @param cls closure
 * @param hr HTTP response data
 * @param ta transfer data, (set only if @a http_status is #MHD_HTTP_OK, otherwise NULL)
 */
typedef void
(*TALER_EXCHANGE_TransfersGetCallback)(
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr,
  const struct TALER_EXCHANGE_TransferData *ta);


/**
 * Query the exchange about which transactions were combined
 * to create a wire transfer.
 *
 * @param exchange exchange to query
 * @param wtid raw wire transfer identifier to get information about
 * @param cb callback to call
 * @param cb_cls closure for @a cb
 * @return handle to cancel operation
 */
struct TALER_EXCHANGE_TransfersGetHandle *
TALER_EXCHANGE_transfers_get (
  struct TALER_EXCHANGE_Handle *exchange,
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

      /**
       * Payment target that the merchant should use
       * to check for its KYC status.
       */
      uint64_t payment_target_uuid;
    } success;

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
       * Payment target that the merchant should use
       * to check for its KYC status.
       */
      uint64_t payment_target_uuid;

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
 * @param hr HTTP response data
 * @param dd details about the deposit (NULL on errors)
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
 * @param exchange the exchange to query
 * @param merchant_priv the merchant's private key
 * @param h_wire hash of merchant's wire transfer details
 * @param h_contract_terms hash of the proposal data
 * @param coin_pub public key of the coin
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to abort request
 */
struct TALER_EXCHANGE_DepositGetHandle *
TALER_EXCHANGE_deposits_get (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_MerchantPrivateKeyP *merchant_priv,
  const struct TALER_MerchantWireHash *h_wire,
  const struct TALER_PrivateContractHash *h_contract_terms,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
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
 * @param dk fee structure for the coin, NULL to skip verifying fees
 * @param currency expected currency for the coin
 * @param coin_pub public key of the coin
 * @param history history of the coin in json encoding
 * @param[out] h_denom_pub set to the hash of the coin's denomination (if available)
 * @param[out] total how much of the coin has been spent according to @a history
 * @return #GNUNET_OK if @a history is valid, #GNUNET_SYSERR if not
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_verify_coin_history (
  const struct TALER_EXCHANGE_DenomPublicKey *dk,
  const char *currency,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  json_t *history,
  struct TALER_DenominationHash *h_denom_pub,
  struct TALER_Amount *total);


/**
 * Parse history given in JSON format and return it in binary
 * format.
 *
 * @param exchange connection to the exchange we can use
 * @param history JSON array with the history
 * @param reserve_pub public key of the reserve to inspect
 * @param currency currency we expect the balance to be in
 * @param[out] balance final balance
 * @param history_length number of entries in @a history
 * @param[out] rhistory array of length @a history_length, set to the
 *             parsed history entries
 * @return #GNUNET_OK if history was valid and @a rhistory and @a balance
 *         were set,
 *         #GNUNET_SYSERR if there was a protocol violation in @a history
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_parse_reserve_history (
  struct TALER_EXCHANGE_Handle *exchange,
  const json_t *history,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const char *currency,
  struct TALER_Amount *balance,
  unsigned int history_length,
  struct TALER_EXCHANGE_ReserveHistory *rhistory);


/**
 * Free memory (potentially) allocated by #TALER_EXCHANGE_parse_reserve_history().
 *
 * @param rhistory result to free
 * @param len number of entries in @a rhistory
 */
void
TALER_EXCHANGE_free_reserve_history (
  struct TALER_EXCHANGE_ReserveHistory *rhistory,
  unsigned int len);


/* ********************* /recoup *********************** */


/**
 * @brief A /recoup Handle
 */
struct TALER_EXCHANGE_RecoupHandle;


/**
 * Callbacks of this type are used to return the final result of
 * submitting a recoup request to a exchange.  If the operation was
 * successful, this function returns the @a reserve_pub of the
 * reserve that was credited.
 *
 * @param cls closure
 * @param hr HTTP response data
 * @param reserve_pub public key of the reserve receiving the recoup
 */
typedef void
(*TALER_EXCHANGE_RecoupResultCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr,
  const struct TALER_ReservePublicKeyP *reserve_pub);


/**
 * Ask the exchange to pay back a coin due to the exchange triggering
 * the emergency recoup protocol for a given denomination.  The value
 * of the coin will be refunded to the original customer (without fees).
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param pk kind of coin to pay back
 * @param denom_sig signature over the coin by the exchange using @a pk
 * @param ps secret internals of the original planchet
 * @param amount value remaining on the coin that is being recouped
 * @param recoup_cb the callback to call when the final result for this request is available
 * @param recoup_cb_cls closure for @a recoup_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_RecoupHandle *
TALER_EXCHANGE_recoup (struct TALER_EXCHANGE_Handle *exchange,
                       const struct TALER_EXCHANGE_DenomPublicKey *pk,
                       const struct TALER_DenominationSignature *denom_sig,
                       const struct TALER_PlanchetSecretsP *ps,
                       const struct TALER_Amount *amount,
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
 * Callbacks of this type are used to return the final result of
 * submitting a recoup-refresh request to a exchange.
 *
 * @param cls closure
 * @param hr HTTP response data
 * @param old_coin_pub public key of the dirty coin that was credited
 */
typedef void
(*TALER_EXCHANGE_RecoupRefreshResultCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr,
  const struct TALER_CoinSpendPublicKeyP *old_coin_pub);


/**
 * Ask the exchange to pay back a coin due to the exchange triggering
 * the emergency recoup protocol for a given denomination.  The value
 * of the coin will be refunded to the original coin that the
 * revoked coin was refreshed from. The original coin is then
 * considered a zombie.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param pk kind of coin to pay back
 * @param denom_sig signature over the coin by the exchange using @a pk
 * @param ps secret internals of the original planchet
 * @param amount value remaining on the coin that is being recouped
 * @param recoup_cb the callback to call when the final result for this request is available
 * @param recoup_cb_cls closure for @a recoup_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_RecoupRefreshHandle *
TALER_EXCHANGE_recoup_refresh (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_EXCHANGE_DenomPublicKey *pk,
  const struct TALER_DenominationSignature *denom_sig,
  const struct TALER_PlanchetSecretsP *ps,
  const struct TALER_Amount *amount,
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
       * Time of the affirmation.
       */
      struct GNUNET_TIME_Timestamp timestamp;

      /**
       * The signing public key used for @e exchange_sig.
       */
      struct TALER_ExchangePublicKeyP exchange_pub;

      /**
       * Signature of purpose
       * #TALER_SIGNATURE_ACCOUNT_SETUP_SUCCESS affirming
       * the successful KYC process.
       */
      struct TALER_ExchangeSignatureP exchange_sig;

    } kyc_ok;

    /**
     * URL the user should open in a browser if
     * the KYC process is to be run. Returned if
     * @e http_status is #MHD_HTTP_ACCEPTED.
     */
    const char *kyc_url;

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
 * @param eh exchange handle to use
 * @param payment_target number identifying the target
 * @param h_payto hash of the payto:// URI at @a payment_target
 * @param timeout how long to wait for a positive KYC status
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return NULL on error
 */
struct TALER_EXCHANGE_KycCheckHandle *
TALER_EXCHANGE_kyc_check (struct TALER_EXCHANGE_Handle *eh,
                          uint64_t payment_target,
                          const struct TALER_PaytoHash *h_payto,
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
 * @param ks the account's KYC status details
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
 * @param eh exchange handle to use
 * @param payment_target number identifying the target
 * @param code OAuth 2.0 code argument
 * @param state OAuth 2.0 state argument
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return NULL on error
 */
struct TALER_EXCHANGE_KycProofHandle *
TALER_EXCHANGE_kyc_proof (struct TALER_EXCHANGE_Handle *eh,
                          uint64_t payment_target,
                          const char *code,
                          const char *state,
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
   * Wallet's payment target UUID. Only valid if
   * @e http_status is #MHD_HTTP_OK
   */
  uint64_t payment_target_uuid;

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
 * @param eh exchange handle to use
 * @param reserve_priv wallet private key to check
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return NULL on error
 */
struct TALER_EXCHANGE_KycWalletHandle *
TALER_EXCHANGE_kyc_wallet (struct TALER_EXCHANGE_Handle *eh,
                           const struct TALER_ReservePrivateKeyP *reserve_priv,
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
   * Public key of the denomination security module.
   */
  struct TALER_SecurityModulePublicKeyP denom_secmod_public_key;

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
 * Function called with information about future keys.
 *
 * @param cls closure
 * @param hr HTTP response data
 * @param keys information about the various keys used
 *        by the exchange, NULL if /management/keys failed
 */
typedef void
(*TALER_EXCHANGE_ManagementGetKeysCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr,
  const struct TALER_EXCHANGE_FutureKeys *keys);


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
TALER_EXCHANGE_get_management_keys (struct GNUNET_CURL_Context *ctx,
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
  struct TALER_DenominationHash h_denom_pub;

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
 * Function called with information about the post keys operation result.
 *
 * @param cls closure
 * @param hr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementPostKeysCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr);


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
 */
struct TALER_EXCHANGE_ManagementPostExtensionsData
{
  struct TALER_Extension *extensions;
  struct TALER_MasterSignatureP *extensions_sigs;
  uint32_t num_extensions;
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
  const struct TALER_EXCHANGE_HttpResponse *hr);

/**
 * @brief Handle for a POST /management/extensions request.
 */
struct TALER_EXCHANGE_ManagementPostExtensionsHandle;


/**
 * FIXME-oec: Provide correct explanation of this function.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param pkd signature data to POST
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementPostExtensionsHandle *
TALER_EXCHANGE_management_post_extensions (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_EXCHANGE_ManagementPostExtensionsData *pkd,
  TALER_EXCHANGE_ManagementPostExtensionsCallback cb,
  void *cb_cls);

/**
 * Cancel #TALER_EXCHANGE_post_management_extensions() operation.
 *
 * @param ph handle of the operation to cancel
 */
void
TALER_EXCHANGE_post_management_extensions_cancel (
  struct TALER_EXCHANGE_ManagementPostExtensionsHandle *ph);


/**
 * Function called with information about the post revocation operation result.
 *
 * @param cls closure
 * @param hr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementRevokeDenominationKeyCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr);


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
  const struct TALER_DenominationHash *h_denom_pub,
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
 * Function called with information about the post revocation operation result.
 *
 * @param cls closure
 * @param hr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementRevokeSigningKeyCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr);


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
 * Function called with information about the auditor setup operation result.
 *
 * @param cls closure
 * @param hr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementAuditorEnableCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr);


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
 * Function called with information about the auditor disable operation result.
 *
 * @param cls closure
 * @param hr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementAuditorDisableCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr);


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
 * Function called with information about the wire enable operation result.
 *
 * @param cls closure
 * @param hr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementWireEnableCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr);


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
 * Function called with information about the wire disable operation result.
 *
 * @param cls closure
 * @param hr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementWireDisableCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr);


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
 * Function called with information about the wire enable operation result.
 *
 * @param cls closure
 * @param hr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_ManagementSetWireFeeCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr);


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
 * @param wire_fee the wire fee for this time period
 * @param closing_fee the closing fee for this time period
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
  const struct TALER_Amount *wire_fee,
  const struct TALER_Amount *closing_fee,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementWireEnableCallback cb,
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
 * Function called with information about the POST
 * /auditor/$AUDITOR_PUB/$H_DENOM_PUB operation result.
 *
 * @param cls closure
 * @param hr HTTP response data
 */
typedef void
(*TALER_EXCHANGE_AuditorAddDenominationCallback) (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr);


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
  const struct TALER_DenominationHash *h_denom_pub,
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


#endif  /* _TALER_EXCHANGE_SERVICE_H */
