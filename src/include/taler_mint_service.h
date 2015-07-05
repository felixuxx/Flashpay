/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file include/taler_mint_service.h
 * @brief C interface of libtalermint, a C library to use mint's HTTP API
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#ifndef _TALER_MINT_SERVICE_H
#define _TALER_MINT_SERVICE_H

#include "taler_util.h"

/* ********************* event loop *********************** */

/**
 * @brief Handle to this library context.  This is where the
 * main event loop logic lives.
 */
struct TALER_MINT_Context;


/**
 * Initialise a context.  A context should be used for each thread and should
 * not be shared among multiple threads.
 *
 * @return the context, NULL on error (failure to initialize)
 */
struct TALER_MINT_Context *
TALER_MINT_init (void);


/**
 * Obtain the information for a select() call to wait until
 * #TALER_MINT_perform() is ready again.  Note that calling
 * any other TALER_MINT-API may also imply that the library
 * is again ready for #TALER_MINT_perform().
 *
 * Basically, a client should use this API to prepare for select(),
 * then block on select(), then call #TALER_MINT_perform() and then
 * start again until the work with the context is done.
 *
 * This function will NOT zero out the sets and assumes that @a max_fd
 * and @a timeout are already set to minimal applicable values.  It is
 * safe to give this API FD-sets and @a max_fd and @a timeout that are
 * already initialized to some other descriptors that need to go into
 * the select() call.
 *
 * @param ctx context to get the event loop information for
 * @param read_fd_set will be set for any pending read operations
 * @param write_fd_set will be set for any pending write operations
 * @param except_fd_set is here because curl_multi_fdset() has this argument
 * @param max_fd set to the highest FD included in any set;
 *        if the existing sets have no FDs in it, the initial
 *        value should be "-1". (Note that `max_fd + 1` will need
 *        to be passed to select().)
 * @param timeout set to the timeout in milliseconds (!); -1 means
 *        no timeout (NULL, blocking forever is OK), 0 means to
 *        proceed immediately with #TALER_MINT_perform().
 */
void
TALER_MINT_get_select_info (struct TALER_MINT_Context *ctx,
                            fd_set *read_fd_set,
                            fd_set *write_fd_set,
                            fd_set *except_fd_set,
                            int *max_fd,
                            long *timeout);


/**
 * Run the main event loop for the Taler interaction.
 *
 * @param ctx the library context
 */
void
TALER_MINT_perform (struct TALER_MINT_Context *ctx);


/**
 * Cleanup library initialisation resources.  This function should be called
 * after using this library to cleanup the resources occupied during library's
 * initialisation.
 *
 * @param ctx the library context
 */
void
TALER_MINT_fini (struct TALER_MINT_Context *ctx);


/* *********************  /keys *********************** */


/**
 * List of possible options to be passed to
 * #TALER_MINT_connect().
 */
enum TALER_MINT_Option
{
  /**
   * Terminator (end of option list).
   */
  TALER_MINT_OPTION_END = 0

};


/**
 * Information we get from the mint about auditors.
 */
struct TALER_MINT_AuditorInformation
{
  /**
   * Public key of the auditing institution.
   */
  struct TALER_AuditorPublicKeyP auditor_pub;

  /**
   * URL of the auditing institution.  The application must check that
   * this is an acceptable auditor for its purpose and also verify
   * that the @a auditor_pub matches the auditor's public key given at
   * that website.  We expect that in practice software is going to
   * often ship with an initial list of accepted auditors, just like
   * browsers ship with a CA root store.
   */
  const char *auditor_url;
};


/**
 * @brief Mint's signature key
 */
struct TALER_MINT_SigningPublicKey
{
  /**
   * The signing public key
   */
  struct TALER_MintPublicKeyP key;

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
 * @brief Public information about a mint's denomination key
 */
struct TALER_MINT_DenomPublicKey
{
  /**
   * The public key
   */
  struct TALER_DenominationPublicKey key;

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
  struct GNUNET_TIME_Absolute deposit_valid_until;

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
   *The applicable fee to refresh a coin of this denomination
   */
  struct TALER_Amount fee_refresh;
};


/**
 * Information about keys from the mint.
 */
struct TALER_MINT_Keys
{

  /**
   * Long-term offline signing key of the mint.
   */
  struct TALER_MasterPublicKeyP master_pub;

  /**
   * Array of the mint's online signing keys.
   */
  struct TALER_MINT_SigningPublicKey *sign_keys;

  /**
   * Array of the mint's denomination keys.
   */
  struct TALER_MINT_DenomPublicKey *denom_keys;

  /**
   * Array of the keys of the auditors of the mint.
   */
  struct TALER_AuditorPublicKeyP *auditors;

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
 * a particular mint and what key the mint is using.
 *
 * @param cls closure
 * @param keys information about the various keys used
 *        by the mint
 */
typedef void
(*TALER_MINT_CertificationCallback) (void *cls,
                                     const struct TALER_MINT_Keys *keys);


/**
 * @brief Handle to the mint.  This is where we interact with
 * a particular mint and keep the per-mint information.
 */
struct TALER_MINT_Handle;


/**
 * Initialise a connection to the mint.  Will connect to the
 * mint and obtain information about the mint's master public
 * key and the mint's auditor.  The respective information will
 * be passed to the @a cert_cb once available, and all future
 * interactions with the mint will be checked to be signed
 * (where appropriate) by the respective master key.
 *
 * @param ctx the context
 * @param url HTTP base URL for the mint
 * @param cert_cb function to call with the mint's certification information
 * @param cert_cb_cls closure for @a cert_cb
 * @param ... list of additional arguments, terminated by #TALER_MINT_OPTION_END.
 * @return the mint handle; NULL upon error
 */
struct TALER_MINT_Handle *
TALER_MINT_connect (struct TALER_MINT_Context *ctx,
                    const char *url,
                    TALER_MINT_CertificationCallback cert_cb,
                    void *cert_cb_cls,
                    ...);


/**
 * Disconnect from the mint.
 *
 * @param mint the mint handle
 */
void
TALER_MINT_disconnect (struct TALER_MINT_Handle *mint);


/**
 * Obtain the keys from the mint.
 *
 * @param mint the mint handle
 * @return the mint's key set
 */
const struct TALER_MINT_Keys *
TALER_MINT_get_keys (const struct TALER_MINT_Handle *mint);


/**
 * Test if the given @a pub is a the current signing key from the mint
 * according to @a keys.
 *
 * @param keys the mint's key set
 * @param pub claimed current online signing key for the mint
 * @return #GNUNET_OK if @a pub is (according to /keys) a current signing key
 */
int
TALER_MINT_test_signing_key (const struct TALER_MINT_Keys *keys,
                             const struct TALER_MintPublicKeyP *pub);


/**
 * Obtain the denomination key details from the mint.
 *
 * @param keys the mint's key set
 * @param pk public key of the denomination to lookup
 * @return details about the given denomination key
 */
const struct TALER_MINT_DenomPublicKey *
TALER_MINT_get_denomination_key (const struct TALER_MINT_Keys *keys,
                                 const struct TALER_DenominationPublicKey *pk);


/* *********************  /deposit *********************** */


/**
 * @brief A Deposit Handle
 */
struct TALER_MINT_DepositHandle;


/**
 * Callbacks of this type are used to serve the result of submitting a
 * deposit permission request to a mint.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful deposit;
 *                    0 if the mint's reply is bogus (fails to follow the protocol)
 * @param obj the received JSON reply, should be kept as proof (and, in case of errors,
 *            be forwarded to the customer)
 */
typedef void
(*TALER_MINT_DepositResultCallback) (void *cls,
                                     unsigned int http_status,
                                     json_t *obj);


/**
 * Submit a deposit permission to the mint and get the mint's
 * response.  This API is typically used by a merchant.  Note that
 * while we return the response verbatim to the caller for further
 * processing, we do already verify that the response is well-formed
 * (i.e. that signatures included in the response are all valid).  If
 * the mint's reply is not well-formed, we return an HTTP status code
 * of zero to @a cb.
 *
 * We also verify that the @a coin_sig is valid for this deposit
 * request, and that the @a ub_sig is a valid signature for @a
 * coin_pub.  Also, the @a mint must be ready to operate (i.e.  have
 * finished processing the /keys reply).  If either check fails, we do
 * NOT initiate the transaction with the mint and instead return NULL.
 *
 * @param mint the mint handle; the mint must be ready to operate
 * @param amount the amount to be deposited
 * @param wire the merchant’s account details, in a format supported by the mint
 * @param h_contract hash of the contact of the merchant with the customer (further details are never disclosed to the mint)
 * @param coin_pub coin’s public key
 * @param denom_pub denomination key with which the coin is signed
 * @param ub_sig mint’s unblinded signature of the coin
 * @param timestamp timestamp when the contract was finalized, must match approximately the current time of the mint
 * @param transaction_id transaction id for the transaction between merchant and customer
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the mint (can be zero if refunds are not allowed)
 * @param coin_sig the signature made with purpose #TALER_SIGNATURE_WALLET_COIN_DEPOSIT made by the customer with the coin’s private key.
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_MINT_DepositHandle *
TALER_MINT_deposit (struct TALER_MINT_Handle *mint,
                    const struct TALER_Amount *amount,
                    json_t *wire_details,
                    const struct GNUNET_HashCode *h_contract,
                    const struct TALER_CoinSpendPublicKeyP *coin_pub,
                    const struct TALER_DenominationSignature *denom_sig,
                    const struct TALER_DenominationPublicKey *denom_pub,
                    struct GNUNET_TIME_Absolute timestamp,
                    uint64_t transaction_id,
                    const struct TALER_MerchantPublicKeyP *merchant_pub,
                    struct GNUNET_TIME_Absolute refund_deadline,
                    const struct TALER_CoinSpendSignatureP *coin_sig,
                    TALER_MINT_DepositResultCallback cb,
                    void *cb_cls);


/**
 * Cancel a deposit permission request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param deposit the deposit permission request handle
 */
void
TALER_MINT_deposit_cancel (struct TALER_MINT_DepositHandle *deposit);


/* ********************* /withdraw/status *********************** */


/**
 * @brief A /withdraw/status Handle
 */
struct TALER_MINT_WithdrawStatusHandle;


/**
 * Ways how a reserve's balance may change.
 */
enum TALER_MINT_ReserveTransactionType {

  /**
   * Deposit into the reserve.
   */
  TALER_MINT_RTT_DEPOSIT,

  /**
   * Withdrawal from the reserve.
   */
  TALER_MINT_RTT_WITHDRAWAL

};


/**
 * Entry in the reserve's transaction history.
 */
struct TALER_MINT_ReserveHistory
{

  /**
   * Type of the transaction.
   */
  enum TALER_MINT_ReserveTransactionType type;

  /**
   * Amount transferred (in or out).
   */
  struct TALER_Amount amount;

  /**
   * Details depending on @e type.
   */
  union {

    /**
     * Transaction details for the incoming transaction.
     */
    json_t *wire_in_details;

    /**
     * Signature authorizing the withdrawal for outgoing transaction.
     */
    json_t *out_authorization_sig;

  } details;

};


/**
 * Callbacks of this type are used to serve the result of submitting a
 * deposit permission request to a mint.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the mint's reply is bogus (fails to follow the protocol)
 * @param[in] json original response in JSON format (useful only for diagnostics)
 * @param balance current balance in the reserve, NULL on error
 * @param history_length number of entries in the transaction history, 0 on error
 * @param history detailed transaction history, NULL on error
 */
typedef void
(*TALER_MINT_WithdrawStatusResultCallback) (void *cls,
                                            unsigned int http_status,
                                            json_t *json,
                                            const struct TALER_Amount *balance,
                                            unsigned int history_length,
                                            const struct TALER_MINT_ReserveHistory *history);


/**
 * Submit a request to obtain the transaction history of a reserve
 * from the mint.  Note that while we return the full response to the
 * caller for further processing, we do already verify that the
 * response is well-formed (i.e. that signatures included in the
 * response are all valid and add up to the balance).  If the mint's
 * reply is not well-formed, we return an HTTP status code of zero to
 * @a cb.
 *
 * @param mint the mint handle; the mint must be ready to operate
 * @param reserve_pub public key of the reserve to inspect
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_MINT_WithdrawStatusHandle *
TALER_MINT_withdraw_status (struct TALER_MINT_Handle *mint,
                            const struct TALER_ReservePublicKeyP *reserve_pub,
                            TALER_MINT_WithdrawStatusResultCallback cb,
                            void *cb_cls);


/**
 * Cancel a withdraw status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param wsh the withdraw status request handle
 */
void
TALER_MINT_withdraw_status_cancel (struct TALER_MINT_WithdrawStatusHandle *wsh);


/* ********************* /withdraw/sign *********************** */


/**
 * @brief A /withdraw/sign Handle
 */
struct TALER_MINT_WithdrawSignHandle;


/**
 * Callbacks of this type are used to serve the result of submitting a
 * deposit permission request to a mint.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the mint's reply is bogus (fails to follow the protocol)
 * @param sig signature over the coin, NULL on error
 * @param full_response full response from the mint (for logging, in case of errors)
 */
typedef void
(*TALER_MINT_WithdrawSignResultCallback) (void *cls,
                                          unsigned int http_status,
                                          const struct TALER_DenominationSignature *sig,
                                          json_t *full_response);


/**
 * Withdraw a coin from the mint using a /withdraw/sign request.  This
 * API is typically used by a wallet.  Note that to ensure that no
 * money is lost in case of hardware failures, the caller must have
 * committed (most of) the arguments to disk before calling, and be
 * ready to repeat the request with the same arguments in case of
 * failures.
 *
 * @param mint the mint handle; the mint must be ready to operate
 * @param pk kind of coin to create
 * @param reserve_priv private key of the reserve to withdraw from
 * @param coin_priv where to store the coin's private key,
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param blinding_key where to store the coin's blinding key
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for @a res_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this mint).
 *         In this case, the callback is not called.
 */
struct TALER_MINT_WithdrawSignHandle *
TALER_MINT_withdraw_sign (struct TALER_MINT_Handle *mint,
                          const struct TALER_MINT_DenomPublicKey *pk,
                          const struct TALER_ReservePrivateKeyP *reserve_priv,
                          const struct TALER_CoinSpendPrivateKeyP *coin_priv,
                          const struct TALER_DenominationBlindingKey *blinding_key,
                          TALER_MINT_WithdrawSignResultCallback res_cb,
                          void *res_cb_cls);


/**
 * Cancel a withdraw status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param sign the withdraw sign request handle
 */
void
TALER_MINT_withdraw_sign_cancel (struct TALER_MINT_WithdrawSignHandle *sign);


/* ********************* /admin/add/incoming *********************** */



/**
 * @brief A /admin/add/incoming Handle
 */
struct TALER_MINT_AdminAddIncomingHandle;


/**
 * Callbacks of this type are used to serve the result of submitting
 * information about an incoming transaction to a mint.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the mint's reply is bogus (fails to follow the protocol)
 * @param full_response full response from the mint (for logging, in case of errors)
 */
typedef void
(*TALER_MINT_AdminAddIncomingResultCallback) (void *cls,
                                              unsigned int http_status,
                                              json_t *full_response);


/**
 * Notify the mint that we have received an incoming transaction
 * which fills a reserve.  Note that this API is an administrative
 * API and thus not accessible to typical mint clients, but only
 * to the operators of the mint.
 *
 * @param mint the mint handle; the mint must be ready to operate
 * @param reserve_pub public key of the reserve
 * @param amount amount that was deposited
 * @param execution_date when did we receive the amount
 * @param wire wire details
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return NULL
 *         if the inputs are invalid (i.e. invalid amount).
 *         In this case, the callback is not called.
 */
struct TALER_MINT_AdminAddIncomingHandle *
TALER_MINT_admin_add_incoming (struct TALER_MINT_Handle *mint,
                               const struct TALER_ReservePublicKeyP *reserve_pub,
                               const struct TALER_Amount *amount,
                               struct GNUNET_TIME_Absolute execution_date,
                               const json_t *wire,
                               TALER_MINT_AdminAddIncomingResultCallback res_cb,
                               void *res_cb_cls);


/**
 * Cancel an add incoming.  This function cannot be used on a request
 * handle if a response is already served for it.
 *
 * @param aai the admin add incoming request handle
 */
void
TALER_MINT_admin_add_incoming_cancel (struct TALER_MINT_AdminAddIncomingHandle *aai);



#endif  /* _TALER_MINT_SERVICE_H */
