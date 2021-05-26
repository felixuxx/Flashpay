/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file taler-exchange-httpd_keys.h
 * @brief management of our various keys
 * @author Christian Grothoff
 */
#include "platform.h"
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_responses.h"


#ifndef TALER_EXCHANGE_HTTPD_KEYS_H
#define TALER_EXCHANGE_HTTPD_KEYS_H

/**
 * Signatures of an auditor over a denomination key of this exchange.
 */
struct TEH_AuditorSignature;


/**
 * @brief All information about a denomination key (which is used to
 * sign coins into existence).
 */
struct TEH_DenominationKey
{

  /**
   * Decoded denomination public key (the hash of it is in
   * @e issue, but we sometimes need the full public key as well).
   */
  struct TALER_DenominationPublicKey denom_pub;

  /**
   * Hash code of the denomination public key.
   */
  struct GNUNET_HashCode h_denom_pub;

  /**
   * Meta data about the type of the denomination, such as fees and validity
   * periods.
   */
  struct TALER_EXCHANGEDB_DenominationKeyMetaData meta;

  /**
   * The long-term offline master key's signature for this denomination.
   * Signs over @e h_denom_pub and @e meta.
   */
  struct TALER_MasterSignatureP master_sig;

  /**
   * We store the auditor signatures for this denomination in a DLL.
   */
  struct TEH_AuditorSignature *as_head;

  /**
   * We store the auditor signatures for this denomination in a DLL.
   */
  struct TEH_AuditorSignature *as_tail;

  /**
   * Set to 'true' if this denomination has been revoked and recoup is
   * thus supported right now.
   */
  bool recoup_possible;

};


/**
 * Snapshot of the (coin and signing) keys (including private keys) of
 * the exchange.  There can be multiple instances of this struct, as it is
 * reference counted and only destroyed once the last user is done
 * with it.  The current instance is acquired using
 * #TEH_KS_acquire().  Using this function increases the
 * reference count.  The contents of this structure (except for the
 * reference counter) should be considered READ-ONLY until it is
 * ultimately destroyed (as there can be many concurrent users).
 */
struct TEH_KeyStateHandle;


/**
 * Return the current key state for this thread.  Possibly re-builds the key
 * state if we have reason to believe that something changed.
 *
 * The result is ONLY valid until the next call to
 * #TEH_keys_denomination_by_hash() or #TEH_keys_get_state()
 * or #TEH_keys_exchange_sign().
 *
 * @return NULL on error
 */
struct TEH_KeyStateHandle *
TEH_keys_get_state (void);


/**
 * Something changed in the database. Rebuild all key states.  This function
 * should be called if the exchange learns about a new signature from an
 * auditor or our master key.
 *
 * (We do not do so immediately, but merely signal to all threads that they
 * need to rebuild their key state upon the next call to
 * #TEH_keys_get_state()).
 */
void
TEH_keys_update_states (void);


/**
 * Look up the issue for a denom public key.  Note that the result
 * must only be used in this thread and only until another key or
 * key state is resolved.
 *
 * @param h_denom_pub hash of denomination public key
 * @param[in,out] conn used to return status message if NULL is returned
 * @param[out] mret set to the MHD status if NULL is returned
 * @return the denomination key issue,
 *         or NULL if @a h_denom_pub could not be found
 */
struct TEH_DenominationKey *
TEH_keys_denomination_by_hash (const struct GNUNET_HashCode *h_denom_pub,
                               struct MHD_Connection *conn,
                               MHD_RESULT *mret);


/**
 * Look up the issue for a denom public key using a given @a ksh.  This allows
 * requesting multiple denominations with the same @a ksh which thus will
 * remain valid until the next call to #TEH_keys_denomination_by_hash() or
 * #TEH_keys_get_state() or #TEH_keys_exchange_sign().
 *
 * @param ksh key state state to look in
 * @param h_denom_pub hash of denomination public key
 * @param[in,out] conn connection used to return status message if NULL is returned
 * @param[out] mret set to the MHD status if NULL is returned
 * @return the denomination key issue,
 *         or NULL if @a h_denom_pub could not be found
 */
struct TEH_DenominationKey *
TEH_keys_denomination_by_hash2 (struct TEH_KeyStateHandle *ksh,
                                const struct GNUNET_HashCode *h_denom_pub,
                                struct MHD_Connection *conn,
                                MHD_RESULT *mret);

/**
 * Request to sign @a msg using the public key corresponding to
 * @a h_denom_pub.
 *
 * @param h_denom_pub hash of the public key to use to sign
 * @param msg message to sign
 * @param msg_size number of bytes in @a msg
 * @param[out] ec set to the error code (or #TALER_EC_NONE on success)
 * @return signature, the value inside the structure will be NULL on failure,
 *         see @a ec for details about the failure
 */
struct TALER_DenominationSignature
TEH_keys_denomination_sign (const struct GNUNET_HashCode *h_denom_pub,
                            const void *msg,
                            size_t msg_size,
                            enum TALER_ErrorCode *ec);


/**
 * Revoke the public key associated with @param h_denom_pub .
 * This function should be called AFTER the database was
 * updated, as it also triggers #TEH_keys_update_states().
 *
 * Note that the actual revocation happens asynchronously and
 * may thus fail silently. To verify that the revocation succeeded,
 * clients must watch for the associated change to the key state.
 *
 * @param h_denom_pub hash of the public key to revoke
 */
void
TEH_keys_denomination_revoke (const struct GNUNET_HashCode *h_denom_pub);


/**
 * Resumse all suspended /keys requests, we may now have key material
 * (or are shutting down).
 *
 * @param do_shutdown are we shutting down?
 */
void
TEH_resume_keys_requests (bool do_shutdown);


/**
 * Sign the message in @a purpose with the exchange's signing key.
 *
 * The @a purpose data is the beginning of the data of which the signature is
 * to be created. The `size` field in @a purpose must correctly indicate the
 * number of bytes of the data structure, including its header.  Use
 * #TEH_keys_exchange_sign() instead of calling this function directly!
 *
 * @param purpose the message to sign
 * @param[out] pub set to the current public signing key of the exchange
 * @param[out] sig signature over purpose using current signing key
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TEH_keys_exchange_sign_ (
  const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Sign the message in @a purpose with the exchange's signing key.
 *
 * The @a purpose data is the beginning of the data of which the signature is
 * to be created. The `size` field in @a purpose must correctly indicate the
 * number of bytes of the data structure, including its header.  Use
 * #TEH_keys_exchange_sign() instead of calling this function directly!
 *
 * @param ksh key state state to look in
 * @param purpose the message to sign
 * @param[out] pub set to the current public signing key of the exchange
 * @param[out] sig signature over purpose using current signing key
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TEH_keys_exchange_sign2_ (
  struct TEH_KeyStateHandle *ksh,
  const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * @ingroup crypto
 * @brief EdDSA sign a given block.
 *
 * The @a ps data must be a fixed-size struct for which the signature is to be
 * created. The `size` field in @a ps->purpose must correctly indicate the
 * number of bytes of the data structure, including its header.
 *
 * @param ps packed struct with what to sign, MUST begin with a purpose
 * @param[out] pub where to store the public key to use for the signing
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
#define TEH_keys_exchange_sign(ps,pub,sig) \
  ({                                                  \
    /* check size is set correctly */                 \
    GNUNET_assert (htonl ((ps)->purpose.size) ==      \
                   sizeof (*ps));                     \
    /* check 'ps' begins with the purpose */          \
    GNUNET_static_assert (((void*) (ps)) ==           \
                          ((void*) &(ps)->purpose));  \
    TEH_keys_exchange_sign_ (&(ps)->purpose,          \
                             pub,                     \
                             sig);                    \
  })


/**
 * @ingroup crypto
 * @brief EdDSA sign a given block.
 *
 * The @a ps data must be a fixed-size struct for which the signature is to be
 * created. The `size` field in @a ps->purpose must correctly indicate the
 * number of bytes of the data structure, including its header.
 *
 * This allows requesting multiple denominations with the same @a ksh which
 * thus will remain valid until the next call to
 * #TEH_keys_denomination_by_hash() or #TEH_keys_get_state() or
 * #TEH_keys_exchange_sign().
 *
 * @param ksh key state to use
 * @param ps packed struct with what to sign, MUST begin with a purpose
 * @param[out] pub where to store the public key to use for the signing
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
#define TEH_keys_exchange_sign2(ksh,ps,pub,sig)       \
  ({                                                  \
    /* check size is set correctly */                 \
    GNUNET_assert (htonl ((ps)->purpose.size) ==      \
                   sizeof (*ps));                     \
    /* check 'ps' begins with the purpose */          \
    GNUNET_static_assert (((void*) (ps)) ==           \
                          ((void*) &(ps)->purpose));  \
    TEH_keys_exchange_sign2_ (ksh,                    \
                              &(ps)->purpose,         \
                              pub,                     \
                              sig);                    \
  })


/**
 * Revoke the given exchange's signing key.
 * This function should be called AFTER the database was
 * updated, as it also triggers #TEH_keys_update_states().
 *
 * Note that the actual revocation happens asynchronously and
 * may thus fail silently. To verify that the revocation succeeded,
 * clients must watch for the associated change to the key state.
 *
 * @param exchange_pub key to revoke
 */
void
TEH_keys_exchange_revoke (const struct TALER_ExchangePublicKeyP *exchange_pub);


/**
 * Function to call to handle requests to "/keys" by sending
 * back our current key material.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param args array of additional options (must be empty for this function)
 * @return MHD result code
 */
MHD_RESULT
TEH_keys_get_handler (const struct TEH_RequestHandler *rh,
                      struct MHD_Connection *connection,
                      const char *const args[]);


/**
 * Function to call to handle requests to "/management/keys" by sending
 * back our future key material.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @return MHD result code
 */
MHD_RESULT
TEH_keys_management_get_handler (const struct TEH_RequestHandler *rh,
                                 struct MHD_Connection *connection);


/**
 * Load fees and expiration times (!) for the denomination type configured for
 * the denomination matching @a h_denom_pub.
 *
 * @param h_denom_pub hash of the denomination public key
 *        to use to derive the section name of the configuration to use
 * @param[out] denom_pub set to the denomination public key (to be freed by caller!)
 * @param[out] meta denomination type data to complete
 * @return #GNUNET_OK on success
 */
int
TEH_keys_load_fees (const struct GNUNET_HashCode *h_denom_pub,
                    struct TALER_DenominationPublicKey *denom_pub,
                    struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta);


/**
 * Load expiration times for the given onling signing key.
 *
 * @param exchange_pub the online signing key
 * @param[out] meta set to meta data about the key
 * @return #GNUNET_OK on success
 */
int
TEH_keys_get_timing (const struct TALER_ExchangePublicKeyP *exchange_pub,
                     struct TALER_EXCHANGEDB_SignkeyMetaData *meta);


/**
 * Initialize keys submodule.
 *
 * @return #GNUNET_OK on success
 */
int
TEH_keys_init (void);


#endif
