/*
  This file is part of TALER
  Copyright (C) 2016 Inria

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler_error_codes.h
 * @brief error codes returned by GNU Taler
 *
 * This file should define constants for error codes returned
 * in Taler APIs.  We use codes above 1000 to avoid any
 * confusing with HTTP status codes.  All constants have the
 * shared prefix "TALER_EC_" to indicate that they are error
 * codes.
 */
#ifndef TALER_ERROR_CODES_H
#define TALER_ERROR_CODES_H

/**
 * Enumeration with all possible Taler error codes.
 */
enum TALER_ErrorCode
{

  /**
   * Special code to indicate no error.
   */
  TALER_EC_NONE = 0,

  /* ********** generic error codes ************* */
  
  /**
   * The exchange failed to even just initialize its connection to the
   * database.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_DB_SETUP_FAILED = 1001,

  /**
   * The exchange encountered an error event to just start 
   * the database transaction.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_DB_START_FAILED = 1002,

  /**
   * The exchange encountered an error event to commit 
   * the database transaction (hard, unrecoverable error).
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_DB_COMMIT_FAILED_HARD = 1003,
  
  /**
   * The exchange encountered an error event to commit 
   * the database transaction, even after repeatedly
   * retrying it there was always a conflicting transaction.
   * (This indicates a repeated serialization error; should
   * only happen if some client maliciously tries to create
   * conflicting concurrent transactions.)
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_DB_COMMIT_FAILED_ON_RETRY = 1004,

    /**
   * The exchange had insufficient memory to parse the request. This
   * response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_PARSER_OUT_OF_MEMORY = 1005,

  /**
   * The JSON in the client's request to the exchange was malformed.
   * (Generic parse error).
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_JSON_INVALID = 1006,

  /**
   * The JSON in the client's request to the exchange was malformed.
   * Details about the location of the parse error are provided.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_JSON_INVALID_WITH_DETAILS = 1007,

  /**
   * A required parameter in the request to the exchange was missing.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PARAMETER_MISSING = 1008,

  /**
   * A parameter in the request to the exchange was malformed.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PARAMETER_MALFORMED = 1009,

  /* ********** request-specific error codes ************* */  
  
  /**
   * The given reserve does not have sufficient funds to admit the
   * requested withdraw operation at this time.  The response includes
   * the current "balance" of the reserve as well as the transaction
   * "history" that lead to this balance.  This response is provided
   * with HTTP status code MHD_HTTP_FORBIDDEN.
   */
  TALER_EC_WITHDRAW_INSUFFICIENT_FUNDS = 1100, 

  /**
   * The exchange has no information about the "reserve_pub" that
   * was given.
   * This response is provided with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_WITHDRAW_RESERVE_UNKNOWN = 1101,

  /**
   * The amount to withdraw together with the fee exceeds the
   * numeric range for Taler amounts.  This is not a client 
   * failure, as the coin value and fees come from the exchange's
   * configuration.
   * This response is provided with HTTP status code MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_WITHDRAW_AMOUNT_FEE_OVERFLOW = 1102,
  
  /**
   * All of the deposited amounts into this reserve total up to a
   * value that is too big for the numeric range for Taler amounts.
   * This is not a client failure, as the transaction history comes
   * from the exchange's configuration.  This response is provided
   * with HTTP status code MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_WITHDRAW_AMOUNT_DEPOSITS_OVERFLOW = 1103,

  /**
   * For one of the historic withdrawals from this reserve, the
   * exchange could not find the denomination key.
   * This is not a client failure, as the transaction history comes
   * from the exchange's configuration.  This response is provided
   * with HTTP status code MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_WITHDRAW_HISTORIC_DENOMINATION_KEY_NOT_FOUND = 1104,

  /**
   * All of the withdrawals from reserve total up to a
   * value that is too big for the numeric range for Taler amounts.
   * This is not a client failure, as the transaction history comes
   * from the exchange's configuration.  This response is provided
   * with HTTP status code MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_WITHDRAW_AMOUNT_WITHDRAWALS_OVERFLOW = 1105,

  /**
   * The exchange somehow knows about this reserve, but there seem to
   * have been no wire transfers made.  This is not a client failure,
   * as this is a database consistency issue of the exchange.  This
   * response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_WITHDRAW_RESERVE_WITHOUT_WIRE_TRANSFER = 1106,

  /**
   * The exchange failed to create the signature using the
   * denomination key.  This response is provided with HTTP status
   * code MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_WITHDRAW_SIGNATURE_FAILED = 1107,

  /**
   * The exchange failed to store the withdraw operation in its
   * database.  This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_WITHDRAW_DB_STORE_ERROR = 1108,

  /**
   * The exchange failed to check against historic withdraw data from
   * database (as part of ensuring the idempotency of the operation).
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_WITHDRAW_DB_FETCH_ERROR = 1109,

  /**
   * The exchange is not aware of the denomination key
   * the wallet requested for the withdrawal.
   * This response is provided
   * with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_WITHDRAW_DENOMINATION_KEY_NOT_FOUND = 1110,

  /**
   * The signature of the reserve is not valid.  This response is
   * provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_WITHDRAW_RESERVE_SIGNATURE_INVALID = 1111,

  /**
   * The exchange failed to obtain the transaction history of the
   * given reserve from the database while generating an insufficient
   * funds errors.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_WITHDRAW_HISTORY_DB_ERROR_INSUFFICIENT_FUNDS = 1112,
  
  /**
   * The exchange failed to obtain the transaction history of the
   * given reserve from the database.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_RESERVE_STATUS_DB_ERROR = 1150,


  /**
   * The respective coin did not have sufficient residual value
   * for the /deposit operation (i.e. due to double spending).
   * The "history" in the respose provides the transaction history
   * of the coin proving this fact.  This response is provided
   * with HTTP status code MHD_HTTP_FORBIDDEN.
   */
  TALER_EC_DEPOSIT_INSUFFICIENT_FUNDS = 1200,

  /**
   * The exchange failed to obtain the transaction history of the
   * given coin from the database (this does not happen merely because
   * the coin is seen by the exchange for the first time).
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_DEPOSIT_HISTORY_DB_ERROR = 1201,

  /**
   * The exchange failed to store the /depost information in the
   * database.  This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_DEPOSIT_STORE_DB_ERROR = 1202,

  /**
   * The exchange database is unaware of the denomination key that
   * signed the coin (however, the exchange process is; this is not
   * supposed to happen; it can happen if someone decides to purge the
   * DB behind the back of the exchange process).  Hence the deposit
   * is being refused.  This response is provided with HTTP status
   * code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_DEPOSIT_DB_DENOMINATION_KEY_UNKNOWN = 1203,
  
  /**
   * The exchange database is unaware of the denomination key that
   * signed the coin (however, the exchange process is; this is not
   * supposed to happen; it can happen if someone decides to purge the
   * DB behind the back of the exchange process).  Hence the deposit
   * is being refused.  This response is provided with HTTP status
   * code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_DEPOSIT_DENOMINATION_KEY_UNKNOWN = 1204,

  /**
   * The signature of the coin is not valid.  This response is
   * provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_DEPOSIT_COIN_SIGNATURE_INVALID = 1205,

  /**
   * The signature of the denomination key over the coin is not valid.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_DEPOSIT_DENOMINATION_SIGNATURE_INVALID = 1206,

  /**
   * The stated value of the coin after the deposit fee is subtracted
   * would be negative.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_DEPOSIT_NEGATIVE_VALUE_AFTER_FEE = 1207,

  /**
   * The stated refund deadline is after the wire deadline.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_DEPOSIT_REFUND_DEADLINE_AFTER_WIRE_DEADLINE = 1208,

  /**
   * The exchange does not recognize the validity of or support the
   * given wire (bank account) address.  This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT = 1209,

  /**
   * The exchange failed to canonicalize and hash the given wire format.
   * This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_JSON = 1210,

  /**
   * The hash of the given wire address does not match the hash
   * specified in the contract.
   * This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_CONTRACT_HASH_CONFLICT = 1211,

  /**
   * The exchange failed to obtain the transaction history of the
   * given coin from the database while generating an insufficient
   * funds errors.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_DEPOSIT_HISTORY_DB_ERROR_INSUFFICIENT_FUNDS = 1212,
  
  /**
   * The respective coin did not have sufficient residual value
   * for the /refresh/melt operation.  The "history" in this
   * response provdes the "residual_value" of the coin, which may
   * be less than its "original_value".  This response is provided
   * with HTTP status code MHD_HTTP_FORBIDDEN.
   */
  TALER_EC_REFRESH_MELT_INSUFFICIENT_FUNDS = 1300,

  /**
   * The exchange is unaware of the denomination key that was
   * used to sign the melted coin.  This response is provided
   * with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_REFRESH_MELT_DENOMINATION_KEY_NOT_FOUND = 1301,

  /**
   * The exchange had an internal error reconstructing the
   * transaction history of the coin that was being melted.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */ 
  TALER_EC_REFRESH_MELT_COIN_HISTORY_COMPUTATION_FAILED = 1302,

  /**
   * The exchange failed to check against historic melt data from
   * database (as part of ensuring the idempotency of the operation).
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_REFRESH_MELT_DB_FETCH_ERROR = 1303,

  /**
   * The exchange failed to store session data in the
   * database.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_REFRESH_MELT_DB_STORE_SESSION_ERROR = 1304,

  /**
   * The exchange failed to store refresh order data in the
   * database.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_REFRESH_MELT_DB_STORE_ORDER_ERROR = 1305,

  /**
   * The exchange failed to store commit data in the
   * database.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_REFRESH_MELT_DB_STORE_COMMIT_ERROR = 1306,
  
  /**
   * The exchange failed to store transfer keys in the
   * database.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_REFRESH_MELT_DB_STORE_TRANSFER_ERROR = 1307,

  /**
   * The exchange is unaware of the denomination key that was
   * requested for one of the fresh coins.  This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_MELT_FRESH_DENOMINATION_KEY_NOT_FOUND = 1308,

  /**
   * The exchange encountered a numeric overflow totaling up
   * the cost for the refresh operation.  This response is provided
   * with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_REFRESH_MELT_COST_CALCULATION_OVERFLOW = 1309,

  /**
   * During the transaction phase, the exchange could suddenly
   * no longer find the denomination key that was
   * used to sign the melted coin.  This response is provided
   * with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_REFRESH_MELT_DB_DENOMINATION_KEY_NOT_FOUND = 1310,

  /**
   * The exchange encountered melt fees exceeding the melted
   * coin's contribution.  This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_MELT_FEES_EXCEED_CONTRIBUTION = 1311,

  /**
   * The exchange's cost calculation does not add up to the
   * melt fees specified in the request.  This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_MELT_FEES_MISSMATCH = 1312,

  /**
   * The denomination key signature on the melted coin is invalid.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_MELT_DENOMINATION_SIGNATURE_INVALID = 1313,

  /**
   * The exchange's cost calculation shows that the melt amount
   * is below the costs of the transaction.  This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_MELT_AMOUNT_INSUFFICIENT = 1314,

  /**
   * The signature made with the coin to be melted is invalid.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_MELT_COIN_SIGNATURE_INVALID = 1315,

  /**
   * The size of the cut-and-choose dimension of the 
   * blinded coins request does not match #TALER_CNC_KAPPA.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_MELT_CNC_COIN_ARRAY_SIZE_INVALID = 1316,
  
  /**
   * The size of the cut-and-choose dimension of the 
   * transfer keys request does not match #TALER_CNC_KAPPA.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_MELT_CNC_TRANSFER_ARRAY_SIZE_INVALID = 1317,

  /**
   * The exchange failed to obtain the transaction history of the
   * given coin from the database while generating an insufficient
   * funds errors.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_REFRESH_MELT_HISTORY_DB_ERROR_INSUFFICIENT_FUNDS = 1318,
  
  /**
   * The provided transfer keys do not match up with the
   * original commitment.  Information about the original
   * commitment is included in the response.  This response is
   * provided with HTTP status code MHD_HTTP_CONFLICT.
   */
  TALER_EC_REFRESH_REVEAL_COMMITMENT_VIOLATION = 1350,

  /**
   * Failed to blind the envelope to reconstruct the blinded
   * coins for revealation checks.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_REFRESH_REVEAL_BLINDING_ERROR = 1351,

  /**
   * Failed to produce the blinded signatures over the coins
   * to be returned.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */ 
  TALER_EC_REFRESH_REVEAL_SIGNING_ERROR = 1352,
  
  /**
   * The exchange is unaware of the refresh sessino specified in
   * the request.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST. 
   */
  TALER_EC_REFRESH_REVEAL_SESSION_UNKNOWN = 1353,

  /**
   * The exchange failed to retrieve valid session data from the
   * database.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_REFRESH_REVEAL_DB_FETCH_SESSION_ERROR = 1354,

  /**
   * The exchange failed to retrieve order data from the
   * database.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_REFRESH_REVEAL_DB_FETCH_ORDER_ERROR = 1355,

  /**
   * The exchange failed to retrieve transfer keys from the
   * database.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_REFRESH_REVEAL_DB_FETCH_TRANSFER_ERROR = 1356,

  /**
   * The exchange failed to retrieve commitment data from the
   * database.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_REFRESH_REVEAL_DB_FETCH_COMMIT_ERROR = 1357,

  /**
   * The size of the cut-and-choose dimension of the 
   * private transfer keys request does not match #TALER_CNC_KAPPA - 1.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_REVEAL_CNC_TRANSFER_ARRAY_SIZE_INVALID = 1358,
  
  
  /**
   * The coin specified in the link request is unknown to the exchange.
   * This response is provided with HTTP status code
   * MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_REFRESH_LINK_COIN_UNKNOWN = 1400,

  
  /**
   * The exchange knows literally nothing about the coin we were asked
   * to refund. But without a transaction history, we cannot issue a
   * refund.  This is kind-of OK, the owner should just refresh it
   * directly without executing the refund.  This response is provided
   * with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_REFUND_COIN_NOT_FOUND = 1500,

  /**
   * We could not process the refund request as the coin's transaction
   * history does not permit the requested refund at this time.  The
   * "history" in the response proves this.  This response is provided
   * with HTTP status code MHD_HTTP_CONFLICT.
   */
  TALER_EC_REFUND_CONFLICT = 1501,
  
  /**
   * The exchange knows about the coin we were asked to refund, but
   * not about the specific /deposit operation.  Hence, we cannot
   * issue a refund (as we do not know if this merchant public key is
   * authorized to do a refund).  This response is provided with HTTP
   * status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_REFUND_DEPOSIT_NOT_FOUND = 1503,

  /**
   * The currency specified for the refund is different from
   * the currency of the coin.  This response is provided with HTTP
   * status code MHD_HTTP_PRECONDITION_FAILED.
   */
  TALER_EC_REFUND_CURRENCY_MISSMATCH = 1504,

  /**
   * When we tried to check if we already paid out the coin, the
   * exchange's database suddenly disagreed with data it previously
   * provided (internal inconsistency).
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_REFUND_DB_INCONSISTENT = 1505,

  /**
   * The exchange can no longer refund the customer/coin as the
   * money was already transferred (paid out) to the merchant.
   * (It should be past the refund deadline.)
   * This response is provided with HTTP status code
   * MHD_HTTP_GONE.
   */
  TALER_EC_REFUND_MERCHANT_ALREADY_PAID = 1506,

  /**
   * The amount the exchange was asked to refund exceeds
   * (with fees) the total amount of the deposit (including fees).
   * This response is provided with HTTP status code
   * MHD_HTTP_PRECONDITION_FAILED.
   */
  TALER_EC_REFUND_INSUFFICIENT_FUNDS = 1507,

  /**
   * The exchange failed to recover information about the
   * denomination key of the refunded coin (even though it
   * recognizes the key).  Hence it could not check the fee
   * strucutre.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_REFUND_DENOMINATION_KEY_NOT_FOUND = 1508,

  /**
   * The refund fee specified for the request is lower than
   * the refund fee charged by the exchange for the given 
   * denomination key of the refunded coin.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFUND_FEE_TOO_LOW = 1509,

  /**
   * The exchange failed to store the refund information to
   * its database.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_REFUND_STORE_DB_ERROR = 1510,

  /**
   * The refund fee is specified in a different currency
   * than the refund amount.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFUND_FEE_CURRENCY_MISSMATCH = 1511,

  /**
   * The refunded amount is smaller than the refund fee,
   * which would result in a negative refund.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFUND_FEE_ABOVE_AMOUNT = 1512,

  /**
   * The signature of the merchant is invalid.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFUND_MERCHANT_SIGNATURE_INVALID = 1513,

  
  /**
   * The wire format specified in the "sender_account_details"
   * is not understood or not supported by this exchange.
   * Returned with an HTTP status code of MHD_HTTP_NOT_FOUND.
   * (As we did not find an interpretation of the wire format.)
   */
  TALER_EC_ADMIN_ADD_INCOMING_WIREFORMAT_UNSUPPORTED = 1600,

  /**
   * The currency specified in the "amount" parameter is not
   * supported by this exhange.  Returned with an HTTP status
   * code of MHD_HTTP_BAD_REQUEST.
   */ 
  TALER_EC_ADMIN_ADD_INCOMING_CURRENCY_UNSUPPORTED = 1601,

  /**
   * The exchange failed to store information about the incoming
   * transfer in its database.  This response is provided with HTTP
   * status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_ADMIN_ADD_INCOMING_DB_STORE = 1602,

  /**
   * The exchange encountered an error (that is not about not finding
   * the wire transfer) trying to lookup a wire transfer identifier
   * in the database.  This response is provided with HTTP
   * status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSFER_DB_FETCH_FAILED = 1700,

  /**
   * The exchange found internally inconsistent data when resolving a
   * wire transfer identifier in the database.  This response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSFER_DB_INCONSISTENT = 1701,

  /**
   * The exchange did not find information about the specified
   * wire transfer identifier in the database.  This response is
   * provided with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_TRACK_TRANSFER_WTID_NOT_FOUND = 1702,

  
  /**
   * The exchange found internally inconsistent fee data when
   * resolving a transaction in the database.  This
   * response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSACTION_DB_FEE_INCONSISTENT = 1800,

  /**
   * The exchange encountered an error (that is not about not finding
   * the transaction) trying to lookup a transaction 
   * in the database.  This response is provided with HTTP
   * status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSACTION_DB_FETCH_FAILED = 1801,

  /**
   * The exchange did not find information about the specified
   * transaction in the database.  This response is
   * provided with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_TRACK_TRANSACTION_NOT_FOUND = 1802,
  
  /**
   * The exchange failed to identify the wire transfer of the
   * transaction (or information about the plan that it was supposed
   * to still happen in the future).  This response is provided with
   * HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSACTION_WTID_RESOLUTION_ERROR = 1803,

  /**
   * The signature of the merchant is invalid.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_TRACK_TRANSACTION_MERCHANT_SIGNATURE_INVALID = 1804,


  /* *********** Merchant backend error codes ********* */

  /**
   * The backend could not find the merchant instance specified
   * in the request.   This response is
   * provided with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_CONTRACT_INSTANCE_UNKNOWN = 2000,

  /**
   * The exchange failed to provide a meaningful response
   * to a /deposit request.  This response is provided
   * with HTTP status code MHD_HTTP_SERVICE_UNAVAILABLE.
   */
  TALER_EC_PAY_EXCHANGE_FAILED = 2101,

  /**
   * The merchant failed to commit the exchanges' response to
   * a /deposit request to its database.  This response is provided
   * with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_PAY_DB_STORE_PAY_ERROR = 2102,

  /**
   * The specified exchange is not supported/trusted by
   * this merchant.  This response is provided
   * with HTTP status code MHD_HTTP_PRECONDITION_FAILED.
   */
  TALER_EC_PAY_EXCHANGE_REJECTED = 2103,

  /**
   * The denomination key used for payment is not listed among the
   * denomination keys of the exchange.  This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_DENOMINATION_KEY_NOT_FOUND = 2104,

  /**
   * The denomination key used for payment is not audited by an
   * auditor approved by the merchant.  This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_DENOMINATION_KEY_AUDITOR_FAILURE = 2105,

  /**
   * There was an integer overflow totaling up the amounts or
   * deposit fees in the payment.  This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_AMOUNT_OVERFLOW = 2106,

  /**
   * The deposit fees exceed the total value of the payment.
   * This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_FEES_EXCEED_PAYMENT = 2107,

  /**
   * After considering deposit fees, the payment is insufficient
   * to satisfy the required amount for the contract.
   * This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_PAYMENT_INSUFFICIENT_DUE_TO_FEES = 2108,

  /**
   * While the merchant is happy to cover all applicable deposit fees,
   * the payment is insufficient to satisfy the required amount for
   * the contract.  This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_PAYMENT_INSUFFICIENT = 2109,

  /**
   * The signature over the contract of one of the coins
   * was invalid. This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_COIN_SIGNATURE_INVALID = 2110,

  /**
   * We failed to contact the exchange for the /pay request.
   * This response is provided
   * with HTTP status code MHD_HTTP_SERVICE_UNAVAILABLE.
   */
  TALER_EC_PAY_EXCHANGE_TIMEOUT = 2111,

  /**
   * The backend could not find the merchant instance specified
   * in the request.   This response is
   * provided with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_PAY_INSTANCE_UNKNOWN = 2112,

  /**
   * The signature over the contract of the merchant
   * was invalid. This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_MERCHANT_SIGNATURE_INVALID = 2113,

  /**
   * The refund deadline was after the transfer deadline.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_REFUND_DEADLINE_PAST_WIRE_TRANSFER_DEADLINE = 2114,

  /**
   * The request fails to provide coins for the payment.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_COINS_ARRAY_EMPTY = 2115,

  /**
   * The merchant failed to fetch the merchant's previous state with
   * respect to a /pay request from its database.  This response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_PAY_DB_FETCH_PAY_ERROR = 2116,

  /**
   * The merchant failed to fetch the merchant's previous state with
   * respect to transactions from its database.  This response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_PAY_DB_FETCH_TRANSACTION_ERROR = 2117,

  /**
   * The transaction ID was used for a conflicing transaction before.
   * This response is
   * provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_DB_TRANSACTION_ID_CONFLICT = 2118,

  /**
   * The merchant failed to store the merchant's state with
   * respect to the transaction in its database.  This response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_PAY_DB_STORE_TRANSACTION_ERROR = 2119,

  /**
   * The exchange failed to provide a valid response to
   * the merchant's /keys request.
   * This response is provided
   * with HTTP status code MHD_HTTP_SERVICE_UNAVAILABLE.
   */
  TALER_EC_PAY_EXCHANGE_KEYS_FAILURE = 2120,

  /**
   * The payment is too late, the offer has expired.
   * This response is
   * provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_OFFER_EXPIRED = 2121,

  
  /**
   * Integer overflow with sepcified timestamp argument detected.
   * This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_HISTORY_TIMESTAMP_OVERFLOW = 2200,

  /**
   * Failed to retrieve history from merchant database.
   * This response is provided
   * with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_HISTORY_DB_FETCH_ERROR = 2201,


  /**
   * We failed to contact the exchange for the /track/transaction
   * request.  This response is provided with HTTP status code
   * MHD_HTTP_SERVICE_UNAVAILABLE.
   */
  TALER_EC_TRACK_TRANSACTION_EXCHANGE_TIMEOUT = 2300,
  
  /**
   * The backend could not find the merchant instance specified
   * in the request.   This response is
   * provided with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_TRACK_TRANSACTION_INSTANCE_UNKNOWN = 2301,

  /**
   * The backend could not find the transaction specified
   * in the request.   This response is
   * provided with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_TRACK_TRANSACTION_TRANSACTION_UNKNOWN = 2302,

  /**
   * The backend had a database access error trying to 
   * retrieve transaction data from its database.
   * The response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSACTION_DB_FETCH_TRANSACTION_ERROR = 2303,

  /**
   * The backend had a database access error trying to 
   * retrieve payment data from its database.
   * The response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSACTION_DB_FETCH_PAYMENT_ERROR = 2304,

  /**
   * The backend found no applicable deposits in the database.
   * This is odd, as we know about the transaction, but not
   * about deposits we made for the transaction.  The response is
   * provided with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_TRACK_TRANSACTION_DB_NO_DEPOSITS_ERROR = 2305,

  /**
   * We failed to contact the exchange for the /track/transfer
   * request.  This response is provided with HTTP status code
   * MHD_HTTP_SERVICE_UNAVAILABLE.
   */
  TALER_EC_TRACK_TRANSFER_EXCHANGE_TIMEOUT = 2400,

  /**
   * The backend could not find the merchant instance specified
   * in the request.   This response is
   * provided with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_TRACK_TRANSFER_INSTANCE_UNKNOWN = 2000,


  
  /* ********** /test API error codes ************* */
  
  /**
   * The exchange failed to compute ECDH.  This response is provided
   * with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TEST_ECDH_ERROR = 4000,

  /**
   * The EdDSA test signature is invalid.  This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_TEST_EDDSA_INVALID = 4001,

  /**
   * The exchange failed to compute the EdDSA test signature.  This response is provided
   * with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TEST_EDDSA_ERROR = 4002,

  /**
   * The exchange failed to generate an RSA key.  This response is provided
   * with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TEST_RSA_GEN_ERROR = 4003,

  /**
   * The exchange failed to compute the public RSA key.  This response
   * is provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TEST_RSA_PUB_ERROR = 4004,

  /**
   * The exchange failed to compute the RSA signature.  This response
   * is provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TEST_RSA_SIGN_ERROR = 4005,

  
  /**
   * End of error code range.
   */
  TALER_EC_END = 9999
  
};


#endif
