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
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file taler-exchange-httpd_responses.h
 * @brief API for generating the various replies of the exchange; these
 *        functions are called TEH_RESPONSE_reply_ and they generate
 *        and queue MHD response objects for a given connection.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_RESPONSES_H
#define TALER_EXCHANGE_HTTPD_RESPONSES_H
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_error_codes.h"
#include "taler-exchange-httpd.h"
#include "taler-exchange-httpd_db.h"


/**
 * Add headers we want to return in every response.
 * Useful for testing, like if we want to always close
 * connections.
 *
 * @param response response to modify
 */
void
TEH_RESPONSE_add_global_headers (struct MHD_Response *response);


/**
 * Try to compress a response body.  Updates @a buf and @buf_size.
 *
 * @param[in,out] buf pointer to body to compress
 * @param[in,out] buf_size pointer to initial size of @a buf
 * @return #MHD_TES if @a buf was compressed
 */
int
TEH_RESPONSE_body_compress (void **buf,
			    size_t *buf_size);


/** 
 * Is HTTP body deflate compression supported by the client?
 *
 * @param connection connection to check
 * @return #MHD_YES if 'deflate' compression is allowed
 */
int
TEH_RESPONSE_can_compress (struct MHD_Connection *connection);


/**
 * Send JSON object as response.
 *
 * @param connection the MHD connection
 * @param json the json object
 * @param response_code the http response code
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_json (struct MHD_Connection *connection,
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
TEH_RESPONSE_reply_json_pack (struct MHD_Connection *connection,
                              unsigned int response_code,
                              const char *fmt,
                              ...);


/**
 * Send a response indicating an invalid signature.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param param_name the parameter that is invalid
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_signature_invalid (struct MHD_Connection *connection,
				      enum TALER_ErrorCode ec,
                                      const char *param_name);


/**
 * Send a response indicating an invalid argument.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param param_name the parameter that is invalid
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_arg_invalid (struct MHD_Connection *connection,
				enum TALER_ErrorCode ec,
                                const char *param_name);


/**
 * Send a response indicating an argument refering to a
 * resource unknown to the exchange (i.e. unknown reserve or
 * denomination key).
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param param_name the parameter that is invalid
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_arg_unknown (struct MHD_Connection *connection,
				enum TALER_ErrorCode ec,
                                const char *param_name);


/**
 * Send a response indicating a missing argument.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param param_name the parameter that is missing
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_arg_missing (struct MHD_Connection *connection,
				enum TALER_ErrorCode ec,
                                const char *param_name);


/**
 * Send a response indicating permission denied.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param hint hint about why access was denied
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_permission_denied (struct MHD_Connection *connection,
				      enum TALER_ErrorCode ec,
                                      const char *hint);


/**
 * Send a response indicating an internal error.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param hint hint about the internal error's nature
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_internal_error (struct MHD_Connection *connection,
				   enum TALER_ErrorCode ec,
                                   const char *hint);


/**
 * Send a response indicating an external error.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param hint hint about the error's nature
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_external_error (struct MHD_Connection *connection,
				   enum TALER_ErrorCode ec,
                                   const char *hint);


/**
 * Send a response indicating an error committing a
 * transaction (concurrent interference).
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_commit_error (struct MHD_Connection *connection,
				      enum TALER_ErrorCode ec);

/**
 * Send a response indicating a failure to talk to the Exchange's
 * database.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_internal_db_error (struct MHD_Connection *connection,
				      enum TALER_ErrorCode ec);


/**
 * Send a response indicating that the request was too big.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_request_too_large (struct MHD_Connection *connection);


/**
 * Send a response indicating that the JSON was malformed.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_invalid_json (struct MHD_Connection *connectionx);


/**
 * Send confirmation of deposit success to client. This function
 * will create a signed message affirming the given information
 * and return it to the client.  By this, the exchange affirms that
 * the coin had sufficient (residual) value for the specified
 * transaction and that it will execute the requested deposit
 * operation with the given wiring details.
 *
 * @param connection connection to the client
 * @param coin_pub public key of the coin
 * @param h_wire hash of wire details
 * @param h_proposal_data hash of proposal data
 * @param timestamp client's timestamp
 * @param refund_deadline until when this deposit be refunded
 * @param merchant merchant public key
 * @param amount_without_fee fraction of coin value to deposit (without fee)
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_deposit_success (struct MHD_Connection *connection,
                                    const struct TALER_CoinSpendPublicKeyP *coin_pub,
                                    const struct GNUNET_HashCode *h_wire,
                                    const struct GNUNET_HashCode *h_proposal_data,
                                    struct GNUNET_TIME_Absolute timestamp,
                                    struct GNUNET_TIME_Absolute refund_deadline,
                                    const struct TALER_MerchantPublicKeyP *merchant,
                                    const struct TALER_Amount *amount_without_fee);


/**
 * Send proof that a request is invalid to client because of
 * insufficient funds.  This function will create a message with all
 * of the operations affecting the coin that demonstrate that the coin
 * has insufficient value.
 *
 * @param connection connection to the client
 * @param ec error code to return
 * @param tl transaction list to use to build reply
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_coin_insufficient_funds (struct MHD_Connection *connection,
                                            enum TALER_ErrorCode ec,
                                            const struct TALER_EXCHANGEDB_TransactionList *tl);


/**
 * Generate refund conflict failure message. Returns the
 * transaction list @a tl with the details about the conflict.
 *
 * @param connection connection to the client
 * @param tl transaction list showing the conflict
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_refund_conflict (struct MHD_Connection *connection,
                                    const struct TALER_EXCHANGEDB_TransactionList *tl);


/**
 * Generate generic refund failure message. All the details
 * are in the @a response_code.  The body can be empty.
 *
 * @param connection connection to the client
 * @param response_code response code to generate
 * @param ec error code uniquely identifying the error
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_refund_failure (struct MHD_Connection *connection,
				   unsigned int response_code,
				   enum TALER_ErrorCode ec);


/**
 * Generate successful refund confirmation message.
 *
 * @param connection connection to the client
 * @param refund details about the successful refund
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_refund_success (struct MHD_Connection *connection,
                                   const struct TALER_EXCHANGEDB_Refund *refund);


/**
 * A merchant asked for details about a deposit, but
 * we do not know anything about the deposit. Generate the
 * 404 reply.
 *
 * @param connection connection to the client
 * @param ec Taler error code
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_transaction_unknown (struct MHD_Connection *connection,
					enum TALER_ErrorCode ec);


/**
 * A merchant asked for details about a deposit, but
 * we did not execute the deposit yet. Generate a 202 reply.
 *
 * @param connection connection to the client
 * @param planned_exec_time planned execution time
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_transfer_pending (struct MHD_Connection *connection,
				     struct GNUNET_TIME_Absolute planned_exec_time);


/**
 * A merchant asked for details about a deposit.  Provide
 * them. Generates the 200 reply.
 *
 * @param connection connection to the client
 * @param h_proposal_data hash of the proposal data
 * @param h_wire hash of wire account details
 * @param coin_pub public key of the coin
 * @param coin_contribution contribution of this coin to the total amount transferred
 * @param wtid raw wire transfer identifier
 * @param exec_time execution time of the wire transfer
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_track_transaction (struct MHD_Connection *connection,
                                      const struct GNUNET_HashCode *h_proposal_data,
                                      const struct GNUNET_HashCode *h_wire,
                                      const struct TALER_CoinSpendPublicKeyP *coin_pub,
                                      const struct TALER_Amount *coin_contribution,
                                      const struct TALER_WireTransferIdentifierRawP *wtid,
                                      struct GNUNET_TIME_Absolute exec_time);


/**
 * Detail for /wire/deposit response.
 */
struct TEH_TrackTransferDetail
{

  /**
   * We keep deposit details in a DLL.
   */
  struct TEH_TrackTransferDetail *next;

  /**
   * We keep deposit details in a DLL.
   */
  struct TEH_TrackTransferDetail *prev;

  /**
   * Hash of the proposal data.
   */
  struct GNUNET_HashCode h_proposal_data;

  /**
   * Coin's public key.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Total value of the coin.
   */
  struct TALER_Amount deposit_value;

  /**
   * Fees charged by the exchange for the deposit.
   */
  struct TALER_Amount deposit_fee;
};


/**
 * A merchant asked for transaction details about a wire transfer.
 * Provide them. Generates the 200 reply.
 *
 * @param connection connection to the client
 * @param total total amount that was transferred
 * @param merchant_pub public key of the merchant
 * @param h_wire destination account
 * @param wire_fee wire fee that was charged
 * @param exec_time execution time of the wire transfer
 * @param wdd_head linked list with details about the combined deposits
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_track_transfer_details (struct MHD_Connection *connection,
                                           const struct TALER_Amount *total,
                                           const struct TALER_MerchantPublicKeyP *merchant_pub,
                                           const struct GNUNET_HashCode *h_wire,
                                           const struct TALER_Amount *wire_fee,
                                           struct GNUNET_TIME_Absolute exec_time,
                                           const struct TEH_TrackTransferDetail *wdd_head);


/**
 * Send reserve status information to client.
 *
 * @param connection connection to the client
 * @param rh reserve history to return
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_reserve_status_success (struct MHD_Connection *connection,
                                           const struct TALER_EXCHANGEDB_ReserveHistory *rh);


/**
 * Send reserve status information to client with the
 * message that we have insufficient funds for the
 * requested /reserve/withdraw operation.
 *
 * @param connection connection to the client
 * @param rh reserve history to return
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_reserve_withdraw_insufficient_funds (struct MHD_Connection *connection,
                                                        const struct TALER_EXCHANGEDB_ReserveHistory *rh);


/**
 * Send blinded coin information to client.
 *
 * @param connection connection to the client
 * @param collectable blinded coin to return
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_reserve_withdraw_success (struct MHD_Connection *connection,
                                             const struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable);


/**
 * Send a confirmation response to a "/refresh/melt" request.
 *
 * @param connection the connection to send the response to
 * @param session_hash hash of the refresh session
 * @param noreveal_index which index will the client not have to reveal
 * @return a MHD status code
 */
int
TEH_RESPONSE_reply_refresh_melt_success (struct MHD_Connection *connection,
                                         const struct GNUNET_HashCode *session_hash,
                                         uint16_t noreveal_index);


/**
 * Send a response for a failed "/refresh/melt" request.  The
 * transaction history of the given coin demonstrates that the
 * @a residual value of the coin is below the @a requested
 * contribution of the coin for the melt.  Thus, the exchange
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
TEH_RESPONSE_reply_refresh_melt_insufficient_funds (struct MHD_Connection *connection,
                                                    const struct TALER_CoinSpendPublicKeyP *coin_pub,
                                                    struct TALER_Amount coin_value,
                                                    struct TALER_EXCHANGEDB_TransactionList *tl,
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
TEH_RESPONSE_reply_refresh_reveal_success (struct MHD_Connection *connection,
                                           unsigned int num_newcoins,
                                           const struct TALER_DenominationSignature *sigs);


/**
 * Send a response for a failed "/refresh/reveal", where the
 * revealed value(s) do not match the original commitment.
 *
 * @param connection the connection to send the response to
 * @param session info about session
 * @param commit_coins array of @a num_newcoins committed envelopes at offset @a gamma
 * @param denom_pubs array of @a num_newcoins denomination keys for the new coins
 * @param gamma_tp transfer public key at offset @a gamma
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_refresh_reveal_missmatch (struct MHD_Connection *connection,
                                             const struct TALER_EXCHANGEDB_RefreshSession *session,
                                             const struct TALER_EXCHANGEDB_RefreshCommitCoin *commit_coins,
                                             const struct TALER_DenominationPublicKey *denom_pubs,
                                             const struct TALER_TransferPublicKeyP *gamma_tp);


/**
 * @brief Information for each session a coin was melted into.
 */
struct TEH_RESPONSE_LinkSessionInfo
{
  /**
   * Transfer public key of the coin.
   */
  struct TALER_TransferPublicKeyP transfer_pub;

  /**
   * Linked data of coins being created in the session.
   */
  struct TALER_EXCHANGEDB_LinkDataList *ldl;

};


/**
 * Send a response for "/refresh/link".
 *
 * @param connection the connection to send the response to
 * @param num_sessions number of sessions the coin was used in
 * @param sessions array of @a num_session entries with
 *                  information for each session
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_refresh_link_success (struct MHD_Connection *connection,
                                         unsigned int num_sessions,
                                         const struct TEH_RESPONSE_LinkSessionInfo *sessions);


/**
 * A wallet asked for /payback, but we do not know anything about the
 * original withdraw operation specified. Generates a 404 reply.
 *
 * @param connection connection to the client
 * @param ec Taler error code
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_payback_unknown (struct MHD_Connection *connection,
                                    enum TALER_ErrorCode ec);


/**
 * A wallet asked for /payback, return the successful response.
 *
 * @param connection connection to the client
 * @param coin_pub coin for which we are processing the payback request
 * @param reserve_pub public key of the reserve that will receive the payback
 * @param amount the amount we will wire back
 * @param timestamp when did the exchange receive the /payback request
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_payback_success (struct MHD_Connection *connection,
                                    const struct TALER_CoinSpendPublicKeyP *coin_pub,
                                    const struct TALER_ReservePublicKeyP *reserve_pub,
                                    const struct TALER_Amount *amount,
                                    struct GNUNET_TIME_Absolute timestamp);


#endif
