/*
  This file is part of TALER
  Copyright (C) 2014 GNUnet e.V.

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
 * @file taler-mint-httpd_responses.h
 * @brief API for generating the various replies of the mint; these
 *        functions are called TMH_RESPONSE_reply_ and they generate
 *        and queue MHD response objects for a given connection.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_MINT_HTTPD_RESPONSES_H
#define TALER_MINT_HTTPD_RESPONSES_H
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler-mint-httpd.h"
#include "taler-mint-httpd_db.h"


/**
 * Send JSON object as response.
 *
 * @param connection the MHD connection
 * @param json the json object
 * @param response_code the http response code
 * @return MHD result code
 */
int
TMH_RESPONSE_reply_json (struct MHD_Connection *connection,
                         const json_t *json,
                         unsigned int response_code);


/**
 * Function to call to handle the request by building a JSON
 * reply from a format string and varargs.
 *
 * @param connection the MHD connection to handle
 * @param response_code HTTP response code to use
 * @param fmt format string for pack
 * @param ... varargs
 * @return MHD result code
 */
int
TMH_RESPONSE_reply_json_pack (struct MHD_Connection *connection,
                              unsigned int response_code,
                              const char *fmt,
                              ...);


/**
 * Send a response indicating an invalid argument.
 *
 * @param connection the MHD connection to use
 * @param param_name the parameter that is invalid
 * @return MHD result code
 */
int
TMH_RESPONSE_reply_arg_invalid (struct MHD_Connection *connection,
                                const char *param_name);


/**
 * Send a response indicating an invalid coin.  (I.e. the signature
 * over the public key of the coin does not match a valid signing key
 * of this mint).
 *
 * @param connection the MHD connection to use
 * @return MHD result code
 */
int
TMH_RESPONSE_reply_coin_invalid (struct MHD_Connection *connection);


/**
 * Send a response indicating a missing argument.
 *
 * @param connection the MHD connection to use
 * @param param_name the parameter that is missing
 * @return a MHD result code
 */
int
TMH_RESPONSE_reply_arg_missing (struct MHD_Connection *connection,
                                const char *param_name);


/**
 * Send a response indicating an internal error.
 *
 * @param connection the MHD connection to use
 * @param hint hint about the internal error's nature
 * @return a MHD result code
 */
int
TMH_RESPONSE_reply_internal_error (struct MHD_Connection *connection,
                                   const char *hint);


/**
 * Send a response indicating an external error.
 *
 * @param connection the MHD connection to use
 * @param hint hint about the error's nature
 * @return a MHD result code
 */
int
TMH_RESPONSE_reply_external_error (struct MHD_Connection *connection,
                                   const char *hint);


/**
 * Send a response indicating an error committing a
 * transaction (concurrent interference).
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TMH_RESPONSE_reply_commit_error (struct MHD_Connection *connection);


/**
 * Send a response indicating a failure to talk to the Mint's
 * database.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TMH_RESPONSE_reply_internal_db_error (struct MHD_Connection *connection);


/**
 * Send a response indicating that the request was too big.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TMH_RESPONSE_reply_request_too_large (struct MHD_Connection *connection);


/**
 * Send a response indicating that the JSON was malformed.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TMH_RESPONSE_reply_invalid_json (struct MHD_Connection *connection);


/**
 * Send confirmation of deposit success to client. This function
 * will create a signed message affirming the given information
 * and return it to the client.  By this, the mint affirms that
 * the coin had sufficient (residual) value for the specified
 * transaction and that it will execute the requested deposit
 * operation with the given wiring details.
 *
 * @param connection connection to the client
 * @param coin_pub public key of the coin
 * @param h_wire hash of wire details
 * @param h_contract hash of contract details
 * @param transaction_id transaction ID
 * @param merchant merchant public key
 * @param amount_without_fee fraction of coin value to deposit (without fee)
 * @return MHD result code
 */
int
TMH_RESPONSE_reply_deposit_success (struct MHD_Connection *connection,
                                    const union TALER_CoinSpendPublicKeyP *coin_pub,
                                    const struct GNUNET_HashCode *h_wire,
                                    const struct GNUNET_HashCode *h_contract,
                                    uint64_t transaction_id,
                                    const struct TALER_MerchantPublicKeyP *merchant,
                                    const struct TALER_Amount *amount_without_fee);


/**
 * Send proof that a /deposit request is invalid to client.  This
 * function will create a message with all of the operations affecting
 * the coin that demonstrate that the coin has insufficient value.
 *
 * @param connection connection to the client
 * @param tl transaction list to use to build reply
 * @return MHD result code
 */
int
TMH_RESPONSE_reply_deposit_insufficient_funds (struct MHD_Connection *connection,
                                               const struct TALER_MINTDB_TransactionList *tl);


/**
 * Send reserve status information to client.
 *
 * @param connection connection to the client
 * @param rh reserve history to return
 * @return MHD result code
 */
int
TMH_RESPONSE_reply_withdraw_status_success (struct MHD_Connection *connection,
                                            const struct TALER_MINTDB_ReserveHistory *rh);


/**
 * Send reserve status information to client with the
 * message that we have insufficient funds for the
 * requested /withdraw/sign operation.
 *
 * @param connection connection to the client
 * @param rh reserve history to return
 * @return MHD result code
 */
int
TMH_RESPONSE_reply_withdraw_sign_insufficient_funds (struct MHD_Connection *connection,
                                                     const struct TALER_MINTDB_ReserveHistory *rh);


/**
 * Send blinded coin information to client.
 *
 * @param connection connection to the client
 * @param collectable blinded coin to return
 * @return MHD result code
 */
int
TMH_RESPONSE_reply_withdraw_sign_success (struct MHD_Connection *connection,
                                          const struct TALER_MINTDB_CollectableBlindcoin *collectable);


/**
 * Send a confirmation response to a "/refresh/melt" request.
 *
 * @param connection the connection to send the response to
 * @param session_hash hash of the refresh session
 * @param noreveal_index which index will the client not have to reveal
 * @return a MHD status code
 */
int
TMH_RESPONSE_reply_refresh_melt_success (struct MHD_Connection *connection,
                                         const struct GNUNET_HashCode *session_hash,
                                         uint16_t noreveal_index);


/**
 * Send a response for a failed "/refresh/melt" request.  The
 * transaction history of the given coin demonstrates that the
 * @a residual value of the coin is below the @a requested
 * contribution of the coin for the melt.  Thus, the mint
 * refuses the melt operation.
 *
 * @param connection the connection to send the response to
 * @param coin_pub public key of the coin
 * @param coin_value original value of the coin
 * @param tl transaction history for the coin
 * @param requested how much this coin was supposed to contribute
 * @param residual remaining value of the coin (after subtracting @a tl)
 * @return a MHD result code
 */
int
TMH_RESPONSE_reply_refresh_melt_insufficient_funds (struct MHD_Connection *connection,
                                                    const union TALER_CoinSpendPublicKeyP *coin_pub,
                                                    struct TALER_Amount coin_value,
                                                    struct TALER_MINTDB_TransactionList *tl,
                                                    struct TALER_Amount requested,
                                                    struct TALER_Amount residual);


/**
 * Send a response for "/refresh/reveal".
 *
 * @param connection the connection to send the response to
 * @param num_newcoins number of new coins for which we reveal data
 * @param sigs array of @a num_newcoins signatures revealed
 * @return a MHD result code
 */
int
TMH_RESPONSE_reply_refresh_reveal_success (struct MHD_Connection *connection,
                                           unsigned int num_newcoins,
                                           const struct TALER_DenominationSignature *sigs);


/**
 * Send a response for a failed "/refresh/reveal", where the
 * revealed value(s) do not match the original commitment.
 *
 * FIXME: should also include the client's signature over
 * the original reveal operation and the data that was signed
 * over eventually... (#3712)
 *
 * @param connection the connection to send the response to
 * @param off offset in the array of kappa-commitments where
 *            the missmatch was detected
 * @param j index of the coin for which the missmatch was
 *            detected
 * @param missmatch_object name of the object that was
 *            bogus (i.e. "transfer key").
 * @return a MHD result code
 */
int
TMH_RESPONSE_reply_refresh_reveal_missmatch (struct MHD_Connection *connection,
                                             unsigned int off,
                                             unsigned int j,
                                             const char *missmatch_object);


/**
 * Send a response for "/refresh/link".
 *
 * @param connection the connection to send the response to
 * @param transfer_pub transfer public key
 * @param shared_secret_enc encrypted shared secret
 * @param ldl linked list with link data
 * @return a MHD result code
 */
int
TMH_RESPONSE_reply_refresh_link_success (struct MHD_Connection *connection,
                                         const struct TALER_TransferPublicKeyP *transfer_pub,
                                         const struct TALER_EncryptedLinkSecretP *shared_secret_enc,
                                         const struct TALER_MINTDB_LinkDataList *ldl);


#endif
