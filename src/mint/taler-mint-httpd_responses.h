/*
  This file is part of TALER
  (C) 2014 GNUnet e.V.

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
 *        functions are called TALER_MINT_reply_ and they generate
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
#include <libpq-fe.h>
#include <pthread.h>
#include "taler-mint-httpd.h"
#include "taler-mint-httpd_db.h"
#include "taler-mint-httpd_mhd.h"


/**
 * Send JSON object as response.  Decreases the reference count of the
 * JSON object.
 *
 * @param connection the MHD connection
 * @param json the json object
 * @param response_code the http response code
 * @return MHD result code
 */
int
TALER_MINT_reply_json (struct MHD_Connection *connection,
                       json_t *json,
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
TALER_MINT_reply_json_pack (struct MHD_Connection *connection,
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
TALER_MINT_reply_arg_invalid (struct MHD_Connection *connection,
                              const char *param_name);


/**
 * Send a response indicating a missing argument.
 *
 * @param connection the MHD connection to use
 * @param param_name the parameter that is missing
 * @return a MHD result code
 */
int
TALER_MINT_reply_arg_missing (struct MHD_Connection *connection,
                              const char *param_name);


/**
 * Send a response indicating an internal error.
 *
 * @param connection the MHD connection to use
 * @param hint hint about the internal error's nature
 * @return a MHD result code
 */
int
TALER_MINT_reply_internal_error (struct MHD_Connection *connection,
                                 const char *hint);


/**
 * Send a response indicating a failure to talk to the Mint's
 * database.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TALER_MINT_reply_internal_db_error (struct MHD_Connection *connection);


/**
 * Send a response indicating that the request was too big.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TALER_MINT_reply_request_too_large (struct MHD_Connection *connection);


/**
 * Send a response indicating that the JSON was malformed.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TALER_MINT_reply_invalid_json (struct MHD_Connection *connection);


/**
 * Send confirmation of deposit success to client.
 *
 * @param connection connection to the client
 * @param deposit deposit request to confirm
 * @return MHD result code
 */
int
TALER_MINT_reply_deposit_success (struct MHD_Connection *connection,
                                  const struct Deposit *deposit);


/**
 * Send reserve status information to client.
 *
 * @param connection connection to the client
 * @param reserve reserve status information to return
 * @return MHD result code
 */
int
TALER_MINT_reply_withdraw_status_success (struct MHD_Connection *connection,
                                          const struct Reserve *reserve);


/**
 * Send blinded coin information to client.
 *
 * @param connection connection to the client
 * @param collectable blinded coin to return
 * @return MHD result code
 */
int
TALER_MINT_reply_withdraw_sign_success (struct MHD_Connection *connection,
                                        const struct CollectableBlindcoin *collectable);


/**
 * Send a response to a "/refresh/commit" request.
 *
 * FIXME: maybe not the ideal argument type for @a refresh_session here.
 *
 * @param connection the connection to send the response to
 * @param refresh_session the refresh session
 * @return a MHD status code
 */
int
TALER_MINT_reply_refresh_commit_success (struct MHD_Connection *connection,
                                         struct RefreshSession *refresh_session);


/**
 * Send a response for "/refresh/melt".
 *
 * @param connection the connection to send the response to
 * @param session session data to generate reply from
 * @param session_pub the refresh session public key.
 * @return a MHD result code
 */
int
TALER_MINT_reply_refresh_melt_success (struct MHD_Connection *connection,
                                       const struct RefreshSession *session,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub);


/**
 * Send a response for "/refresh/reveal".
 *
 * @param connection the connection to send the response to
 * @param num_newcoins number of new coins for which we reveal data
 * @param sigs array of @a num_newcoins signatures revealed
 * @return a MHD result code
 */
int
TALER_MINT_reply_refresh_reveal_success (struct MHD_Connection *connection,
                                         unsigned int num_newcoins,
                                         const struct TALER_RSA_Signature *sigs);



#endif
