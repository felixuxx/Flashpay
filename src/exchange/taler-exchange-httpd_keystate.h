/*
  This file is part of TALER
  Copyright (C) 2014, 2015 GNUnet e.V.

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
 * @file exchange/taler-exchange-httpd_keystate.h
 * @brief management of our private signing keys (denomination keys)
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_KEYSTATE_H
#define TALER_EXCHANGE_HTTPD_KEYSTATE_H

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler-exchange-httpd.h"
#include "taler_error_codes.h"
#include "taler_exchangedb_lib.h"


/**
 * Snapshot of the (coin and signing)
 * keys (including private keys) of the exchange.
 */
struct TEH_KS_StateHandle;


/**
 * Acquire the key state of the exchange.  Updates keys if necessary.
 * For every call to #TEH_KS_acquire(), a matching call
 * to #TEH_KS_release() must be made.
 *
 * @param now for what timestamp should we acquire the key state
 * @param location name of the function in which the lock is acquired
 * @return the key state, NULL on error (usually pretty fatal)
 */
struct TEH_KS_StateHandle *
TEH_KS_acquire_ (struct GNUNET_TIME_Absolute now,
                 const char *location);


/**
 * Release key state, free if necessary (if reference count gets to zero).
 *
 * @param location name of the function in which the lock is acquired
 * @param key_state the key state to release
 */
void
TEH_KS_release_ (const char *location,
                 struct TEH_KS_StateHandle *key_state);


/**
 * Acquire the key state of the exchange.  Updates keys if necessary.
 * For every call to #TEH_KS_acquire(), a matching call
 * to #TEH_KS_release() must be made.
 *
 * @param now current time snapshot; either true, or given by the
 *        client via the "now" URL parameter of "/keys".
 * @return the key state
 */
#define TEH_KS_acquire(now) TEH_KS_acquire_ (now, __FUNCTION__)


/**
 * Release key state, free if necessary (if reference count gets to zero).
 *
 * @param key_state the key state to release
 */
#define TEH_KS_release(key_state) TEH_KS_release_ (__FUNCTION__, key_state)


/**
 * Finally, release #internal_key_state.
 */
void
TEH_KS_free (void);


/**
 * Denomination key lookups can be for signing of fresh coins
 * or to validate signatures on existing coins.  As the validity
 * periods for a key differ, the caller must specify which
 * use is relevant for the current operation.
 */
enum TEH_KS_DenominationKeyUse
{

  /**
   * The key is to be used for a /reserve/withdraw or /refresh (exchange)
   * operation.
   */
  TEH_KS_DKU_WITHDRAW,

  /**
   * The key is to be used for a /deposit or /refresh (melt) operation.
   */
  TEH_KS_DKU_DEPOSIT,

  /**
   * The key is to be used for a /payback operation.
   */
  TEH_KS_DKU_PAYBACK,

  /**
   * The key is to be used for a /refresh/payback operation,
   * i.e. it is an old coin that regained value from a
   * payback on a new coin derived from the old coin.
   */
  TEH_KS_DKU_ZOMBIE

};


/**
 * Look up the issue for a denom public key.  Note that the result
 * is only valid while the @a key_state is not released!
 *
 * @param key_state state to look in
 * @param denom_pub_hash hash of denomination public key
 * @param use purpose for which the key is being located
 * @param[out] ec set to the error code, in case the operation failed
 * @param[out] hc set to the HTTP status code to use
 * @return the denomination key issue,
 *         or NULL if denom_pub could not be found (or is not valid at this time for the given @a use)
 */
struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *
TEH_KS_denomination_key_lookup_by_hash (const struct
                                        TEH_KS_StateHandle *key_state,
                                        const struct
                                        GNUNET_HashCode *denom_pub_hash,
                                        enum TEH_KS_DenominationKeyUse use,
                                        enum TALER_ErrorCode *ec,
                                        unsigned int *hc);


/**
 * Read signals from a pipe in a loop, and reload keys from disk if
 * SIGUSR1 is received, terminate if SIGTERM/SIGINT is received, and
 * restart if SIGHUP is received.
 *
 * @return #GNUNET_SYSERR on errors,
 *         #GNUNET_OK to terminate normally
 *         #GNUNET_NO to restart an update version of the binary
 */
int
TEH_KS_loop (void);


/**
 * Sign the message in @a purpose with the exchange's signing
 * key.
 *
 * @param purpose the message to sign
 * @param[out] pub set to the current public signing key of the exchange
 * @param[out] sig signature over purpose using current signing key
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if we lack key material
 */
int
TEH_KS_sign (const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
             struct TALER_ExchangePublicKeyP *pub,
             struct TALER_ExchangeSignatureP *sig);


/**
 * Handle a "/keys" request
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TEH_KS_handler_keys (struct TEH_RequestHandler *rh,
                     struct MHD_Connection *connection,
                     void **connection_cls,
                     const char *upload_data,
                     size_t *upload_data_size);


#endif
