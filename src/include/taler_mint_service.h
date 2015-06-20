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
 * Obtain the current signing key from the mint.
 *
 * @param keys the mint's key set
 * @return sk current online signing key for the mint, NULL on error
 */
const struct TALER_MintPublicKeyP *
TALER_MINT_get_signing_key (struct TALER_MINT_Keys *keys);



#if 0

// FIXME: API below with json-crap is too low-level...
/**
 * @brief A Deposit Handle
 */
struct TALER_MINT_DepositHandle;


/**
 * Callbacks of this type are used to serve the result of submitting a deposit
 * permission object to a mint.
 *
 * @param cls closure
 * @param status 1 for successful deposit, 2 for retry, 0 for failure
 * @param obj the received JSON object; can be NULL if it cannot be constructed
 *        from the reply
 * @param emsg in case of unsuccessful deposit, this contains a human readable
 *        explanation.
 */
typedef void
(*TALER_MINT_DepositResultCallback) (void *cls,
                                     int status,
                                     json_t *obj,
                                     char *emsg);


/**
 * Submit a deposit permission to the mint and get the mint's response
 *
 * @param mint the mint handle
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @param deposit_obj the deposit permission received from the customer along
 *         with the wireformat JSON object
 * @return a handle for this request; NULL if the JSON object could not be
 *         parsed or is of incorrect format or any other error.  In this case,
 *         the callback is not called.
 */
struct TALER_MINT_DepositHandle *
TALER_MINT_deposit_submit_json (struct TALER_MINT_Handle *mint,
                                TALER_MINT_DepositResultCallback cb,
                                void *cb_cls,
                                json_t *deposit_obj);


/**
 * Submit a deposit permission to the mint and get the mint's response.
 *
 * @param mint the mint handle
 * @param cb the callback to call when a reply for this request is available
 * @param cls closure for the above callback
 * @param coin the public key of the coin
 * @param denom_key denomination key of the mint which is used to blind-sign the
 *         coin
 * @param ubsig the mint's unblinded signature
 * @param transaction_id transaction identifier
 * @param amount the amount to deposit
 * @param merchant_pub the public key of the merchant
 * @param h_contract hash of the contract
 * @param h_wire hash of the wire format used
 * @param csig signature of the coin over the transaction_id, amount,
 *         merchant_pub, h_contract and, h_wire
 * @param wire_obj the wireformat object corresponding to h_wire
 * @return a handle for this request
 */
struct TALER_MINT_DepositHandle *
TALER_MINT_deposit_submit_json_ (struct TALER_MINT_Handle *mint,
                                 TALER_MINT_DepositResultCallback *cb,
                                 void *cls,
                                 const struct TALER_CoinPublicKey *coin_pub,
                                 const struct TALER_BLIND_SigningPublicKey *denom_pub,
                                 struct TALER_BLIND_Signature *ubsig,
                                 uint64_t transaction_id,
                                 struct TALER_Amount *amount,
                                 const struct TALER_MerchantPublicKeyP *merchant_pub,
                                 const struct GNUNET_HashCode *h_contract,
                                 const struct GNUNET_HashCode *h_wire,
                                 const struct TALER_CoinSignature *csig,
                                 json_t *wire_obj);


/**
 * Cancel a deposit permission request.  This function cannot be used on a
 * request handle if a response is already served for it.
 *
 * @param deposit the deposit permission request handle
 */
void
TALER_MINT_deposit_submit_cancel (struct TALER_MINT_DepositHandle *deposit);

#endif


#endif  /* _TALER_MINT_SERVICE_H */
