/*
  This file is part of TALER
  Copyright (C) 2014-2017 GNUnet e.V.

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
  TALER_EXCHANGE_OPTION_END = 0

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
   * Validity start time
   */
  struct GNUNET_TIME_Absolute valid_from;

  /**
   * Validity expiration time
   */
  struct GNUNET_TIME_Absolute valid_until;
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
  struct GNUNET_HashCode h_key;

  /**
   * Timestamp indicating when the denomination key becomes valid
   */
  struct GNUNET_TIME_Absolute valid_from;

  /**
   * Timestamp indicating when the denomination key can’t be used anymore to
   * withdraw new coins.
   */
  struct GNUNET_TIME_Absolute withdraw_valid_until;

  /**
   * Timestamp indicating when coins of this denomination become invalid.
   */
  struct GNUNET_TIME_Absolute expire_deposit;

  /**
   * When do signatures with this denomination key become invalid?
   * After this point, these signatures cannot be used in (legal)
   * disputes anymore, as the Exchange is then allowed to destroy its side
   * of the evidence.  @e expire_legal is expected to be significantly
   * larger than @e expire_deposit (by a year or more).
   */
  struct GNUNET_TIME_Absolute expire_legal;

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
  const char *auditor_url;

  /**
   * Number of denomination keys audited by this auditor.
   */
  unsigned int num_denom_keys;

  /**
   * Array of length @a num_denom_keys with the denomination
   * keys audited by this auditor.  Note that the array
   * elements point to the same locations as the entries
   * in the key's main `denom_keys` array.
   */
  const struct TALER_EXCHANGE_DenomPublicKey **denom_keys;
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
   * Length of the @e sign_keys array.
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

};


/**
 * Function called with information about who is auditing
 * a particular exchange and what key the exchange is using.
 *
 * @param cls closure
 * @param keys information about the various keys used
 *        by the exchange, NULL if /keys failed
 */
typedef void
(*TALER_EXCHANGE_CertificationCallback) (void *cls,
                                         const struct TALER_EXCHANGE_Keys *keys);


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
 * Check if our current response for /keys is valid, and if
 * not, trigger /keys download.
 *
 * @param exchange exchange to check keys for
 * @return until when the response is current, 0 if we are re-downloading
 */
struct GNUNET_TIME_Absolute
TALER_EXCHANGE_check_keys_current (struct TALER_EXCHANGE_Handle *exchange);


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
int
TALER_EXCHANGE_test_signing_key (const struct TALER_EXCHANGE_Keys *keys,
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
TALER_EXCHANGE_get_denomination_key (const struct TALER_EXCHANGE_Keys *keys,
                                     const struct TALER_DenominationPublicKey *pk);


/**
 * Obtain the denomination key details from the exchange.
 *
 * @param keys the exchange's key set
 * @param hc hash of the public key of the denomination to lookup
 * @return details about the given denomination key
 */
const struct TALER_EXCHANGE_DenomPublicKey *
TALER_EXCHANGE_get_denomination_key_by_hash (const struct TALER_EXCHANGE_Keys *keys,
                                             const struct GNUNET_HashCode *hc);


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
  struct GNUNET_TIME_Absolute start_date;

  /**
   * Time when this fee stops being in effect (exclusive).
   */
  struct GNUNET_TIME_Absolute end_date;

  /**
   * Signature affirming the above fee structure.
   */
  struct TALER_MasterSignatureP master_sig;
};


/**
 * Function called with information about the wire fees
 * for each wire method.
 *
 * @param cls closure
 * @param wire_method name of the wire method (i.e. "sepa")
 * @param fees fee structure for this method
 */
typedef void
(*TALER_EXCHANGE_WireFeeCallback)(void *cls,
                                  const char *wire_method,
                                  const struct TALER_EXCHANGE_WireAggregateFees *fees);


/**
 * Obtain information about wire fees encoded in @a obj
 * by wire method.
 *
 * @param master_pub public key to use to verify signatures, NULL to not verify
 * @param obj wire information as encoded in the #TALER_EXCHANGE_WireResultCallback
 * @param cb callback to invoke for the fees
 * @param cb_cls closure for @a cb
 * @return #GNUNET_OK in success, #GNUNET_SYSERR if @a obj is ill-formed
 */
int
TALER_EXCHANGE_wire_get_fees (const struct TALER_MasterPublicKeyP *master_pub,
                              const json_t *obj,
                              TALER_EXCHANGE_WireFeeCallback cb,
                              void *cb_cls);


/**
 * @brief A Wire format inquiry handle
 */
struct TALER_EXCHANGE_WireHandle;


/**
 * Callbacks of this type are used to serve the result of submitting a
 * wire format inquiry request to a exchange.
 *
 * If the request fails to generate a valid response from the
 * exchange, @a http_status will also be zero.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful request;
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param obj the received JSON reply, if successful this should be the wire
 *            format details as provided by /wire, or NULL if the
 *            reply was not in JSON format.
 */
typedef void
(*TALER_EXCHANGE_WireResultCallback) (void *cls,
                                      unsigned int http_status,
				      enum TALER_ErrorCode ec,
                                      const json_t *obj);


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
                     TALER_EXCHANGE_WireResultCallback wire_cb,
                     void *wire_cb_cls);


/**
 * Cancel a wire information request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param wh the wire information request handle
 */
void
TALER_EXCHANGE_wire_cancel (struct TALER_EXCHANGE_WireHandle *wh);


/* *********************  /deposit *********************** */


/**
 * @brief A Deposit Handle
 */
struct TALER_EXCHANGE_DepositHandle;


/**
 * Callbacks of this type are used to serve the result of submitting a
 * deposit permission request to a exchange.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful deposit;
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param sign_key exchange key used to sign @a obj, or NULL
 * @param obj the received JSON reply, should be kept as proof (and, in case of errors,
 *            be forwarded to the customer)
 */
typedef void
(*TALER_EXCHANGE_DepositResultCallback) (void *cls,
                                         unsigned int http_status,
					 enum TALER_ErrorCode ec,
                                         const struct TALER_ExchangePublicKeyP *sign_key,
                                         const json_t *obj);


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
 * @param wire_details the merchant’s account details, in a format supported by the exchange
 * @param h_proposal_data hash of the contact of the merchant with the customer (further details are never disclosed to the exchange)
 * @param coin_pub coin’s public key
 * @param denom_pub denomination key with which the coin is signed
 * @param denom_sig exchange’s unblinded signature of the coin
 * @param timestamp timestamp when the contract was finalized, must match approximately the current time of the exchange
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the exchange (can be zero if refunds are not allowed); must not be after the @a wire_deadline
 * @param coin_sig the signature made with purpose #TALER_SIGNATURE_WALLET_COIN_DEPOSIT made by the customer with the coin’s private key.
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_EXCHANGE_DepositHandle *
TALER_EXCHANGE_deposit (struct TALER_EXCHANGE_Handle *exchange,
                        const struct TALER_Amount *amount,
                        struct GNUNET_TIME_Absolute wire_deadline,
                        json_t *wire_details,
                        const struct GNUNET_HashCode *h_proposal_data,
                        const struct TALER_CoinSpendPublicKeyP *coin_pub,
                        const struct TALER_DenominationSignature *denom_sig,
                        const struct TALER_DenominationPublicKey *denom_pub,
                        struct GNUNET_TIME_Absolute timestamp,
                        const struct TALER_MerchantPublicKeyP *merchant_pub,
                        struct GNUNET_TIME_Absolute refund_deadline,
                        const struct TALER_CoinSpendSignatureP *coin_sig,
                        TALER_EXCHANGE_DepositResultCallback cb,
                        void *cb_cls);


/**
 * Cancel a deposit permission request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param deposit the deposit permission request handle
 */
void
TALER_EXCHANGE_deposit_cancel (struct TALER_EXCHANGE_DepositHandle *deposit);


/* *********************  /refund *********************** */

/**
 * @brief A Refund Handle
 */
struct TALER_EXCHANGE_RefundHandle;


/**
 * Callbacks of this type are used to serve the result of submitting a
 * refund request to an exchange.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful deposit;
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param sign_key exchange key used to sign @a obj, or NULL
 * @param obj the received JSON reply, should be kept as proof (and, in particular,
 *            be forwarded to the customer)
 */
typedef void
(*TALER_EXCHANGE_RefundResultCallback) (void *cls,
					unsigned int http_status,
					enum TALER_ErrorCode ec,
                                        const struct TALER_ExchangePublicKeyP *sign_key,
					const json_t *obj);


/**
 * Submit a refund request to the exchange and get the exchange's
 * response.  This API is used by a merchant.  Note that
 * while we return the response verbatim to the caller for further
 * processing, we do already verify that the response is well-formed
 * (i.e. that signatures included in the response are all valid).  If
 * the exchange's reply is not well-formed, we return an HTTP status code
 * of zero to @a cb.
 *
 * The @a exchange must be ready to operate (i.e.  have
 * finished processing the /keys reply).  If this check fails, we do
 * NOT initiate the transaction with the exchange and instead return NULL.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param amount the amount to be refunded; must be larger than the refund fee
 *        (as that fee is still being subtracted), and smaller than the amount
 *        (with deposit fee) of the original deposit contribution of this coin
 * @param refund_fee fee applicable to this coin for the refund
 * @param h_proposal_data hash of the contact of the merchant with the customer that is being refunded
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
		       const struct TALER_Amount *refund_fee,
		       const struct GNUNET_HashCode *h_proposal_data,
		       const struct TALER_CoinSpendPublicKeyP *coin_pub,
		       uint64_t rtransaction_id,
		       const struct TALER_MerchantPrivateKeyP *merchant_priv,
		       TALER_EXCHANGE_RefundResultCallback cb,
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


/* ********************* /reserve/status *********************** */


/**
 * @brief A /reserve/status Handle
 */
struct TALER_EXCHANGE_ReserveStatusHandle;


/**
 * Ways how a reserve's balance may change.
 */
enum TALER_EXCHANGE_ReserveTransactionType {

  /**
   * Deposit into the reserve.
   */
  TALER_EXCHANGE_RTT_DEPOSIT,

  /**
   * Withdrawal from the reserve.
   */
  TALER_EXCHANGE_RTT_WITHDRAWAL,

  /**
   * /payback operation.
   */
  TALER_EXCHANGE_RTT_PAYBACK,

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
  union {

    /**
     * Information about a deposit that filled this reserve.
     * @e type is #TALER_EXCHANGE_RTT_DEPOSIT.
     */
    struct {
      /**
       * Sender account information for the incoming transfer.
       */
      json_t *sender_account_details;

      /**
       * Wire transfer details for the incoming transfer.
       */
      json_t *transfer_details;

    } in_details;

    /**
     * Signature authorizing the withdrawal for outgoing transaction.
     * @e type is #TALER_EXCHANGE_RTT_WITHDRAWAL.
     */
    json_t *out_authorization_sig;

    /**
     * Information provided if the reserve was filled via /payback.
     * @e type is #TALER_EXCHANGE_RTT_PAYBACK.
     */
    struct {

      /**
       * Public key of the coin that was paid back.
       */
      struct TALER_CoinSpendPublicKeyP coin_pub;

      /**
       * Signature of the coin of type
       * #TALER_SIGNATURE_EXCHANGE_CONFIRM_PAYBACK.
       */
      struct TALER_ExchangeSignatureP exchange_sig;

      /**
       * Public key of the exchange that was used for @e exchange_sig.
       */
      struct TALER_ExchangePublicKeyP exchange_pub;

      /**
       * When did the /payback operation happen?
       */
      struct GNUNET_TIME_Absolute timestamp;

    } payback_details;

    /**
     * Information about a close operation of the reserve.
     * @e type is #TALER_EXCHANGE_RTT_CLOSE.
     */
    struct {
      /**
       * Receiver account information for the outgoing wire transfer.
       */
      json_t *receiver_account_details;

      /**
       * Wire transfer details for the outgoing wire transfer.
       */
      json_t *transfer_details;

    } close_details;

  } details;

};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * reserve status request to a exchange.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param[in] json original response in JSON format (useful only for diagnostics)
 * @param balance current balance in the reserve, NULL on error
 * @param history_length number of entries in the transaction history, 0 on error
 * @param history detailed transaction history, NULL on error
 */
typedef void
(*TALER_EXCHANGE_ReserveStatusResultCallback) (void *cls,
                                               unsigned int http_status,
					       enum TALER_ErrorCode ec,
                                               const json_t *json,
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
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_EXCHANGE_ReserveStatusHandle *
TALER_EXCHANGE_reserve_status (struct TALER_EXCHANGE_Handle *exchange,
                               const struct TALER_ReservePublicKeyP *reserve_pub,
                               TALER_EXCHANGE_ReserveStatusResultCallback cb,
                               void *cb_cls);


/**
 * Cancel a withdraw status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param wsh the withdraw status request handle
 */
void
TALER_EXCHANGE_reserve_status_cancel (struct TALER_EXCHANGE_ReserveStatusHandle *wsh);


/* ********************* /reserve/withdraw *********************** */


/**
 * @brief A /reserve/withdraw Handle
 */
struct TALER_EXCHANGE_ReserveWithdrawHandle;


/**
 * Callbacks of this type are used to serve the result of submitting a
 * withdraw request to a exchange.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param sig signature over the coin, NULL on error
 * @param full_response full response from the exchange (for logging, in case of errors)
 */
typedef void
(*TALER_EXCHANGE_ReserveWithdrawResultCallback) (void *cls,
                                                 unsigned int http_status,
						 enum TALER_ErrorCode ec,
                                                 const struct TALER_DenominationSignature *sig,
                                                 const json_t *full_response);


/**
 * Withdraw a coin from the exchange using a /reserve/withdraw request.  This
 * API is typically used by a wallet.  Note that to ensure that no
 * money is lost in case of hardware failures, the caller must have
 * committed (most of) the arguments to disk before calling, and be
 * ready to repeat the request with the same arguments in case of
 * failures.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param pk kind of coin to create
 * @param reserve_priv private key of the reserve to withdraw from
 * @param coin_priv where to fetch the coin's private key,
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param blinding_key where to fetch the coin's blinding key
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for @a res_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_ReserveWithdrawHandle *
TALER_EXCHANGE_reserve_withdraw (struct TALER_EXCHANGE_Handle *exchange,
                                 const struct TALER_EXCHANGE_DenomPublicKey *pk,
                                 const struct TALER_ReservePrivateKeyP *reserve_priv,
                                 const struct TALER_CoinSpendPrivateKeyP *coin_priv,
                                 const struct TALER_DenominationBlindingKeyP *blinding_key,
                                 TALER_EXCHANGE_ReserveWithdrawResultCallback res_cb,
                                 void *res_cb_cls);


/**
 * Cancel a withdraw status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param sign the withdraw sign request handle
 */
void
TALER_EXCHANGE_reserve_withdraw_cancel (struct TALER_EXCHANGE_ReserveWithdrawHandle *sign);


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
 * to #TALER_EXCHANGE_refresh_melt() that will generate the request.
 *
 * This function does verify that the given request data is internally
 * consistent.  However, the @a melts_sig is only verified if @a
 * check_sig is set to #GNUNET_YES, as this may be relatively
 * expensive and should be redundant.
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
 * @param check_sig verify the validity of the signatures of @a melt_sig
 * @param fresh_pks_len length of the @a pks array
 * @param fresh_pks array of @a pks_len denominations of fresh coins to create
 * @param[out] res_size set to the size of the return value, or 0 on error
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         Otherwise, pointer to a buffer of @a res_size to store persistently
 *         before proceeding to #TALER_EXCHANGE_refresh_melt().
 *         Non-null results should be freed using #GNUNET_free().
 */
char *
TALER_EXCHANGE_refresh_prepare (const struct TALER_CoinSpendPrivateKeyP *melt_priv,
                                const struct TALER_Amount *melt_amount,
                                const struct TALER_DenominationSignature *melt_sig,
                                const struct TALER_EXCHANGE_DenomPublicKey *melt_pk,
                                int check_sig,
                                unsigned int fresh_pks_len,
                                const struct TALER_EXCHANGE_DenomPublicKey *fresh_pks,
                                size_t *res_size);


/* ********************* /refresh/melt ***************************** */

/**
 * @brief A /refresh/melt Handle
 */
struct TALER_EXCHANGE_RefreshMeltHandle;


/**
 * Callbacks of this type are used to notify the application about the
 * result of the /refresh/melt stage.  If successful, the @a noreveal_index
 * should be committed to disk prior to proceeding #TALER_EXCHANGE_refresh_reveal().
 *
 * @param cls closure
 * @param http_status HTTP response code, never #MHD_HTTP_OK (200) as for successful intermediate response this callback is skipped.
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param noreveal_index choice by the exchange in the cut-and-choose protocol,
 *                    UINT16_MAX on error
 * @param sign_key exchange key used to sign @a full_response, or NULL
 * @param full_response full response from the exchange (for logging, in case of errors)
 */
typedef void
(*TALER_EXCHANGE_RefreshMeltCallback) (void *cls,
                                       unsigned int http_status,
				       enum TALER_ErrorCode ec,
				       uint16_t noreveal_index,
                                       const struct TALER_ExchangePublicKeyP *sign_key,
                                       const json_t *full_response);


/**
 * Submit a refresh melt request to the exchange and get the exchange's
 * response.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, the provided
 * argument should have been constructed using
 * #TALER_EXCHANGE_refresh_prepare and committed to persistent storage
 * prior to calling this function.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param refresh_data_length size of the @a refresh_data (returned
 *        in the `res_size` argument from #TALER_EXCHANGE_refresh_prepare())
 * @param refresh_data the refresh data as returned from
          #TALER_EXCHANGE_refresh_prepare())
 * @param melt_cb the callback to call with the result
 * @param melt_cb_cls closure for @a melt_cb
 * @return a handle for this request; NULL if the argument was invalid.
 *         In this case, neither callback will be called.
 */
struct TALER_EXCHANGE_RefreshMeltHandle *
TALER_EXCHANGE_refresh_melt (struct TALER_EXCHANGE_Handle *exchange,
                             size_t refresh_data_length,
                             const char *refresh_data,
                             TALER_EXCHANGE_RefreshMeltCallback melt_cb,
                             void *melt_cb_cls);


/**
 * Cancel a refresh melt request.  This function cannot be used
 * on a request handle if the callback was already invoked.
 *
 * @param rmh the refresh handle
 */
void
TALER_EXCHANGE_refresh_melt_cancel (struct TALER_EXCHANGE_RefreshMeltHandle *rmh);


/* ********************* /refresh/reveal ***************************** */


/**
 * Callbacks of this type are used to return the final result of
 * submitting a refresh request to a exchange.  If the operation was
 * successful, this function returns the signatures over the coins
 * that were remelted.  The @a coin_privs and @a sigs arrays give the
 * coins in the same order (and should have the same length) in which
 * the original request specified the respective denomination keys.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param num_coins number of fresh coins created, length of the @a sigs and @a coin_privs arrays, 0 if the operation failed
 * @param coin_privs array of @a num_coins private keys for the coins that were created, NULL on error
 * @param sigs array of signature over @a num_coins coins, NULL on error
 * @param full_response full response from the exchange (for logging, in case of errors)
 */
typedef void
(*TALER_EXCHANGE_RefreshRevealCallback) (void *cls,
                                         unsigned int http_status,
					 enum TALER_ErrorCode ec,
                                         unsigned int num_coins,
                                         const struct TALER_CoinSpendPrivateKeyP *coin_privs,
                                         const struct TALER_DenominationSignature *sigs,
                                         const json_t *full_response);


/**
 * @brief A /refresh/reveal Handle
 */
struct TALER_EXCHANGE_RefreshRevealHandle;


/**
 * Submit a /refresh/reval request to the exchange and get the exchange's
 * response.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, the provided
 * arguments should have been committed to persistent storage
 * prior to calling this function.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param refresh_data_length size of the @a refresh_data (returned
 *        in the `res_size` argument from #TALER_EXCHANGE_refresh_prepare())
 * @param refresh_data the refresh data as returned from
          #TALER_EXCHANGE_refresh_prepare())
 * @param noreveal_index response from the exchange to the
 *        #TALER_EXCHANGE_refresh_melt() invocation
 * @param reveal_cb the callback to call with the final result of the
 *        refresh operation
 * @param reveal_cb_cls closure for the above callback
 * @return a handle for this request; NULL if the argument was invalid.
 *         In this case, neither callback will be called.
 */
struct TALER_EXCHANGE_RefreshRevealHandle *
TALER_EXCHANGE_refresh_reveal (struct TALER_EXCHANGE_Handle *exchange,
                               size_t refresh_data_length,
                               const char *refresh_data,
                               uint16_t noreveal_index,
                               TALER_EXCHANGE_RefreshRevealCallback reveal_cb,
                               void *reveal_cb_cls);


/**
 * Cancel a refresh reveal request.  This function cannot be used
 * on a request handle if the callback was already invoked.
 *
 * @param rrh the refresh reval handle
 */
void
TALER_EXCHANGE_refresh_reveal_cancel (struct TALER_EXCHANGE_RefreshRevealHandle *rrh);


/* ********************* /refresh/link ***************************** */


/**
 * @brief A /refresh/link Handle
 */
struct TALER_EXCHANGE_RefreshLinkHandle;


/**
 * Callbacks of this type are used to return the final result of
 * submitting a /refresh/link request to a exchange.  If the operation was
 * successful, this function returns the signatures over the coins
 * that were created when the original coin was melted.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param num_coins number of fresh coins created, length of the @a sigs and @a coin_privs arrays, 0 if the operation failed
 * @param coin_privs array of @a num_coins private keys for the coins that were created, NULL on error
 * @param sigs array of signature over @a num_coins coins, NULL on error
 * @param pubs array of public keys for the @a sigs, NULL on error
 * @param full_response full response from the exchange (for logging, in case of errors)
 */
typedef void
(*TALER_EXCHANGE_RefreshLinkCallback) (void *cls,
                                       unsigned int http_status,
				       enum TALER_ErrorCode ec,
                                       unsigned int num_coins,
                                       const struct TALER_CoinSpendPrivateKeyP *coin_privs,
                                       const struct TALER_DenominationSignature *sigs,
                                       const struct TALER_DenominationPublicKey *pubs,
                                       const json_t *full_response);


/**
 * Submit a refresh link request to the exchange and get the
 * exchange's response.
 *
 * This API is typically not used by anyone, it is more a threat
 * against those trying to receive a funds transfer by abusing the
 * /refresh protocol.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param coin_priv private key to request link data for
 * @param link_cb the callback to call with the useful result of the
 *        refresh operation the @a coin_priv was involved in (if any)
 * @param link_cb_cls closure for @a link_cb
 * @return a handle for this request
 */
struct TALER_EXCHANGE_RefreshLinkHandle *
TALER_EXCHANGE_refresh_link (struct TALER_EXCHANGE_Handle *exchange,
                             const struct TALER_CoinSpendPrivateKeyP *coin_priv,
                             TALER_EXCHANGE_RefreshLinkCallback link_cb,
                             void *link_cb_cls);


/**
 * Cancel a refresh link request.  This function cannot be used
 * on a request handle if the callback was already invoked.
 *
 * @param rlh the refresh link handle
 */
void
TALER_EXCHANGE_refresh_link_cancel (struct TALER_EXCHANGE_RefreshLinkHandle *rlh);


/* ********************* /admin/add/incoming *********************** */


/**
 * @brief A /admin/add/incoming Handle
 */
struct TALER_EXCHANGE_AdminAddIncomingHandle;


/**
 * Callbacks of this type are used to serve the result of submitting
 * information about an incoming transaction to a exchange.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param full_response full response from the exchange (for logging, in case of errors)
 */
typedef void
(*TALER_EXCHANGE_AdminAddIncomingResultCallback) (void *cls,
                                                  unsigned int http_status,
						  enum TALER_ErrorCode ec,
                                                  const json_t *full_response);


/**
 * Notify the exchange that we have received an incoming transaction
 * which fills a reserve.  Note that this API is an administrative
 * API and thus not accessible to typical exchange clients, but only
 * to the operators of the exchange.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param admin_url URL of the administrative interface of the exchange
 * @param reserve_pub public key of the reserve
 * @param amount amount that was deposited
 * @param execution_date when did we receive the amount
 * @param sender_account_details account information of the sender of the money;
 *        the receiver is always the exchange.
 * @param transfer_details details that uniquely identify the transfer;
 *        used to check for duplicate operations by the exchange
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return NULL
 *         if the inputs are invalid (i.e. invalid amount).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_AdminAddIncomingHandle *
TALER_EXCHANGE_admin_add_incoming (struct TALER_EXCHANGE_Handle *exchange,
                                   const char *admin_url,
                                   const struct TALER_ReservePublicKeyP *reserve_pub,
                                   const struct TALER_Amount *amount,
                                   struct GNUNET_TIME_Absolute execution_date,
                                   const json_t *sender_account_details,
                                   const json_t *transfer_details,
                                   TALER_EXCHANGE_AdminAddIncomingResultCallback res_cb,
                                   void *res_cb_cls);


/**
 * Cancel an add incoming.  This function cannot be used on a request
 * handle if a response is already served for it.
 *
 * @param aai the admin add incoming request handle
 */
void
TALER_EXCHANGE_admin_add_incoming_cancel (struct TALER_EXCHANGE_AdminAddIncomingHandle *aai);


/* ********************* /track/transfer *********************** */

/**
 * @brief A /track/transfer Handle
 */
struct TALER_EXCHANGE_TrackTransferHandle;


/**
 * Function called with detailed wire transfer data, including all
 * of the coin transactions that were combined into the wire transfer.
 *
 * @param cls closure
 * @param http_status HTTP status code we got, 0 on exchange protocol violation
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param sign_key exchange key used to sign @a json, or NULL
 * @param json original json reply (may include signatures, those have then been
 *        validated already)
 * @param h_wire hash of the wire transfer address the transfer went to, or NULL on error
 * @param execution_time time when the exchange claims to have performed the wire transfer
 * @param total_amount total amount of the wire transfer, or NULL if the exchange could
 *             not provide any @a wtid (set only if @a http_status is #MHD_HTTP_OK)
 * @param wire_fee wire fee that was charged by the exchange
 * @param details_length length of the @a details array
 * @param details array with details about the combined transactions
 */
typedef void
(*TALER_EXCHANGE_TrackTransferCallback)(void *cls,
                                        unsigned int http_status,
					enum TALER_ErrorCode ec,
                                        const struct TALER_ExchangePublicKeyP *sign_key,
                                        const json_t *json,
                                        const struct GNUNET_HashCode *h_wire,
                                        struct GNUNET_TIME_Absolute execution_time,
                                        const struct TALER_Amount *total_amount,
                                        const struct TALER_Amount *wire_fee,
                                        unsigned int details_length,
                                        const struct TALER_TrackTransferDetails *details);


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
struct TALER_EXCHANGE_TrackTransferHandle *
TALER_EXCHANGE_track_transfer (struct TALER_EXCHANGE_Handle *exchange,
                               const struct TALER_WireTransferIdentifierRawP *wtid,
                               TALER_EXCHANGE_TrackTransferCallback cb,
                               void *cb_cls);


/**
 * Cancel wire deposits request.  This function cannot be used on a request
 * handle if a response is already served for it.
 *
 * @param wdh the wire deposits request handle
 */
void
TALER_EXCHANGE_track_transfer_cancel (struct TALER_EXCHANGE_TrackTransferHandle *wdh);


/* ********************* /track/transaction *********************** */


/**
 * @brief A /track/transaction Handle
 */
struct TALER_EXCHANGE_TrackTransactionHandle;


/**
 * Function called with detailed wire transfer data.
 *
 * @param cls closure
 * @param http_status HTTP status code we got, 0 on exchange protocol violation
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param sign_key exchange key used to sign @a json, or NULL
 * @param json original json reply (may include signatures, those have then been
 *        validated already)
 * @param wtid wire transfer identifier used by the exchange, NULL if exchange did not
 *                  yet execute the transaction
 * @param execution_time actual or planned execution time for the wire transfer
 * @param coin_contribution contribution to the @a total_amount of the deposited coin (may be NULL)
 */
typedef void
(*TALER_EXCHANGE_TrackTransactionCallback)(void *cls,
                                           unsigned int http_status,
					   enum TALER_ErrorCode ec,
                                           const struct TALER_ExchangePublicKeyP *sign_key,
                                           const json_t *json,
                                           const struct TALER_WireTransferIdentifierRawP *wtid,
                                           struct GNUNET_TIME_Absolute execution_time,
                                           const struct TALER_Amount *coin_contribution);


/**
 * Obtain the wire transfer details for a given transaction.
 *
 * @param exchange the exchange to query
 * @param merchant_priv the merchant's private key
 * @param h_wire hash of merchant's wire transfer details
 * @param h_proposal_data hash of the proposal data
 * @param coin_pub public key of the coin
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to abort request
 */
struct TALER_EXCHANGE_TrackTransactionHandle *
TALER_EXCHANGE_track_transaction (struct TALER_EXCHANGE_Handle *exchange,
                                  const struct TALER_MerchantPrivateKeyP *merchant_priv,
                                  const struct GNUNET_HashCode *h_wire,
                                  const struct GNUNET_HashCode *h_proposal_data,
                                  const struct TALER_CoinSpendPublicKeyP *coin_pub,
                                  TALER_EXCHANGE_TrackTransactionCallback cb,
                                  void *cb_cls);


/**
 * Cancel deposit wtid request.  This function cannot be used on a request
 * handle if a response is already served for it.
 *
 * @param dwh the wire deposits request handle
 */
void
TALER_EXCHANGE_track_transaction_cancel (struct TALER_EXCHANGE_TrackTransactionHandle *dwh);



/**
 * Convenience function.  Verifies a coin's transaction history as
 * returned by the exchange.
 *
 * @param currency expected currency for the coin
 * @param coin_pub public key of the coin
 * @param history history of the coin in json encoding
 * @param[out] total how much of the coin has been spent according to @a history
 * @return #GNUNET_OK if @a history is valid, #GNUNET_SYSERR if not
 */
int
TALER_EXCHANGE_verify_coin_history (const char *currency,
                                    const struct TALER_CoinSpendPublicKeyP *coin_pub,
                                    json_t *history,
                                    struct TALER_Amount *total);


/* ********************* /payback *********************** */


/**
 * @brief A /payback Handle
 */
struct TALER_EXCHANGE_PaybackHandle;


/**
 * Callbacks of this type are used to return the final result of
 * submitting a refresh request to a exchange.  If the operation was
 * successful, this function returns the signatures over the coins
 * that were remelted.  The @a coin_privs and @a sigs arrays give the
 * coins in the same order (and should have the same length) in which
 * the original request specified the respective denomination keys.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param amount amount the exchange will wire back for this coin,
 *        on error the total balance remaining, or NULL
 * @param timestamp what time did the exchange receive the /payback request
 * @param reserve_pub public key of the reserve receiving the payback
 * @param full_response full response from the exchange (for logging, in case of errors)
 */
typedef void
(*TALER_EXCHANGE_PaybackResultCallback) (void *cls,
                                         unsigned int http_status,
                                         enum TALER_ErrorCode ec,
                                         const struct TALER_Amount *amount,
                                         struct GNUNET_TIME_Absolute timestamp,
                                         const struct TALER_ReservePublicKeyP *reserve_pub,
                                         const json_t *full_response);


/**
 * Ask the exchange to pay back a coin due to the exchange triggering
 * the emergency payback protocol for a given denomination.  The value
 * of the coin will be refunded to the original customer (without fees).
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param pk kind of coin to pay back
 * @param denom_sig signature over the coin by the exchange using @a pk
 * @param coin_priv the coin's private key,
 * @param blinding_key where to fetch the coin's blinding key
 * @param payback_cb the callback to call when the final result for this request is available
 * @param payback_cb_cls closure for @a payback_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_PaybackHandle *
TALER_EXCHANGE_payback (struct TALER_EXCHANGE_Handle *exchange,
                        const struct TALER_EXCHANGE_DenomPublicKey *pk,
                        const struct TALER_DenominationSignature *denom_sig,
                        const struct TALER_CoinSpendPrivateKeyP *coin_priv,
                        const struct TALER_DenominationBlindingKeyP *blinding_key,
                        TALER_EXCHANGE_PaybackResultCallback payback_cb,
                        void *payback_cb_cls);


/**
 * Cancel a payback request.  This function cannot be used on a
 * request handle if the callback was already invoked.
 *
 * @param ph the payback handle
 */
void
TALER_EXCHANGE_payback_cancel (struct TALER_EXCHANGE_PaybackHandle *ph);



#endif  /* _TALER_EXCHANGE_SERVICE_H */
