/*
  This file is part of TALER
  (C) 2014 Christian Grothoff (and other contributing authors)

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
 */
#ifndef _TALER_MINT_SERVICE_H
#define _TALER_MINT_SERVICE_H

#include "taler_rsa.h"
#include "taler_util.h"
#include <jansson.h>

/**
 * Handle to this library context
 */
struct TALER_MINT_Context;

/**
 * Handle to the mint
 */
struct TALER_MINT_Handle;

/**
 * Mint's signature key
 */
struct TALER_MINT_SigningPublicKey
{
  /**
   * The signing public key
   */
  struct GNUNET_CRYPTO_EddsaPublicKey key;

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
 * Mint's denomination key
 */
struct TALER_MINT_DenomPublicKey
{
  /**
   * The public key
   */
  struct GNUNET_CRYPTO_rsa_PublicKey *key;

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
 * Initialise a context.  A context should be used for each thread and should
 * not be shared among multiple threads.
 *
 * @return the context
 */
struct TALER_MINT_Context *
TALER_MINT_init (void);


/**
 * Cleanup library initialisation resources.  This function should be called
 * after using this library to cleanup the resources occupied during library's
 * initialisation.
 *
 * @param ctx the library context
 */
void
TALER_MINT_cleanup (struct TALER_MINT_Context *ctx);


/**
 * Initialise a connection to the mint.
 *
 * @param ctx the context
 * @param hostname the hostname of the mint
 * @param port the point where the mint's HTTP service is running.  If port is
 *             given as 0, ports 80 or 443 are chosen depending on @a url.
 * @param mint_key the public key of the mint.  This is used to verify the
 *                 responses of the mint.
 * @return the mint handle; NULL upon error
 */
struct TALER_MINT_Handle *
TALER_MINT_connect (struct TALER_MINT_Context *ctx,
                    const char *hostname,
                    uint16_t port,
                    struct GNUNET_CRYPTO_EddsaPublicKey *mint_key);

/**
 * Disconnect from the mint
 *
 * @param mint the mint handle
 */
void
TALER_MINT_disconnect (struct TALER_MINT_Handle *mint);


/**
 * A handle to get the keys of a mint
 */
struct TALER_MINT_KeysGetHandle;

/**
 * Functions of this type are called to signal completion of an asynchronous call.
 *
 * @param cls closure
 * @param emsg if the asynchronous call could not be completed due to an error,
 *        this parameter contains a human readable error message
 */
typedef void
(*TALER_MINT_ContinuationCallback) (void *cls,
                                    const char *emsg);

/**
 * Functions of this type are called to provide the retrieved signing and
 * denomination keys of the mint.  No TALER_MINT_*() functions should be called
 * in this callback.
 *
 * @param cls closure passed to TALER_MINT_keys_get()
 * @param sign_keys NULL-terminated array of pointers to the mint's signing
 *          keys.  NULL if no signing keys are retrieved.
 * @param denom_keys NULL-terminated array of pointers to the mint's
 *          denomination keys; will be NULL if no signing keys are retrieved.
 */
typedef void
(*TALER_MINT_KeysGetCallback) (void *cls,
                               struct TALER_MINT_SigningPublicKey **sign_keys,
                               struct TALER_MINT_DenomPublicKey **denom_keys);


/**
 * Get the signing and denomination key of the mint.
 *
 * @param mint handle to the mint
 * @param cb the callback to call with the keys
 * @param cb_cls closure for the @a cb callback
 * @param cont_cb the callback to call after completing this asynchronous call
 * @param cont_cls the closure for the @a cont_cb callback
 * @return a handle to this asynchronous call; NULL upon eror
 */
struct TALER_MINT_KeysGetHandle *
TALER_MINT_keys_get (struct TALER_MINT_Handle *mint,
                     TALER_MINT_KeysGetCallback cb,
                     void *cb_cls,
                     TALER_MINT_ContinuationCallback cont_cb,
                     void *cont_cls);


/**
 * Cancel the asynchronous call initiated by TALER_MINT_keys_get().  This should
 * not be called if either of the @a TALER_MINT_KeysGetCallback or @a
 * TALER_MINT_ContinuationCallback passed to TALER_MINT_keys_get() have been
 * called.
 *
 * @param get the handle for retrieving the keys
 */
void
TALER_MINT_keys_get_cancel (struct TALER_MINT_KeysGetHandle *get);


/**
 * A Deposit Handle
 */
struct TALER_MINT_DepositHandle;


/**
 * Callbacks of this type are used to serve the result of submitting a deposit
 * permission object to a mint
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
 * @param cls closure for the above callback
 * @param deposit_obj the deposit permission received from the customer along
 *         with the wireformat JSON object
 * @return a handle for this request; NULL if the JSON object could not be
 *         parsed or is of incorrect format or any other error.  In this case,
 *         the callback is not called.
 */
struct TALER_MINT_DepositHandle *
TALER_MINT_deposit_submit_json (struct TALER_MINT_Handle *mint,
                                TALER_MINT_DepositResultCallback cb,
                                void *cls,
                                json_t *deposit_obj);


#if 0
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
                                 struct GNUNET_CRYPTO_EddsaPublicKey *coin_pub,
                                 struct TALER_BLIND_SigningPublicKey *denom_pub,
                                 struct TALER_BLIND_Signature *ubsig,
                                 uint64_t transaction_id,
                                 struct TALER_Amount *amount,
                                 struct GNUNET_CRYPTO_EddsaPublicKey *merchant_pub,
                                 struct GNUNET_HashCode *h_contract,
                                 struct GNUNET_HashCode *h_wire,
                                 struct GNUNET_CRYPTO_EddsaSignature *csig,
                                 json_t *wire_obj);
#endif


/**
 * Cancel a deposit permission request.  This function cannot be used on a
 * request handle if a response is already served for it.
 *
 * @param the deposit permission request handle
 */
void
TALER_MINT_deposit_submit_cancel (struct TALER_MINT_DepositHandle *deposit);

#endif  /* _TALER_MINT_SERVICE_H */
