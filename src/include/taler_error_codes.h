/*
  This file is part of TALER
  Copyright (C) 2016, 2017, 2019 Taler Systems SA

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
 * This file defines constants for error codes returned
 * in Taler APIs.  We use codes above 1000 to avoid any
 * confusing with HTTP status codes.  All constants have the
 * shared prefix "TALER_EC_" to indicate that they are error
 * codes.
 *
 * THIS FILE IS AUTO-GENERATED, DO NOT MODIFY!
 * If you want to add an error code, please add it in the
 * taler-util.git repository.  Instructions
 * for this are in the README in taler-util.git.
 */
#ifndef TALER_ERROR_CODES_H
#define TALER_ERROR_CODES_H

/**
 * Enumeration with all possible Taler error codes.
 */
enum TALER_ErrorCode
{

  /**
   * Special code to indicate no error (or no "code" present).
   */
  TALER_EC_NONE = 0,

  /**
   * Special code to indicate that a non-integer error code was returned
   * in the JSON response.
   */
  TALER_EC_INVALID = 1,

  /**
   * The response we got from the server was not even in JSON format.
   */
  TALER_EC_INVALID_RESPONSE = 2,

  /**
   * Generic implementation error: this function was not yet
   * implemented.
   */
  TALER_EC_NOT_IMPLEMENTED = 3,

  /**
   * Exchange is badly configured and thus cannot operate.
   */
  TALER_EC_EXCHANGE_BAD_CONFIGURATION = 4,

  /**
   * Internal assertion error.
   */
  TALER_EC_INTERNAL_INVARIANT_FAILURE = 5,

  /**
   * Operation timed out.
   */
  TALER_EC_TIMEOUT = 6,

  /**
   * Exchange failed to allocate memory for building JSON reply.
   */
  TALER_EC_JSON_ALLOCATION_FAILURE = 7,

  /**
   * HTTP method invalid for this URL.
   */
  TALER_EC_METHOD_INVALID = 8,

  /**
   * The exchange failed to even just initialize its connection to the
   * database.  This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_DB_SETUP_FAILED = 1001,

  /**
   * The exchange encountered an error event to just start the database
   * transaction.  This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_DB_START_FAILED = 1002,

  /**
   * The exchange encountered an error event to commit the database
   * transaction (hard, unrecoverable error). This response is provided
   * with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_DB_COMMIT_FAILED_HARD = 1003,

  /**
   * The exchange encountered an error event to commit the database
   * transaction, even after repeatedly retrying it there was always a
   * conflicting transaction. (This indicates a repeated serialization
   * error; should only happen if some client maliciously tries to
   * create conflicting concurrent transactions.) This response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
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
   * (Generic parse error). This response is provided with HTTP status
   * code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_JSON_INVALID = 1006,

  /**
   * The JSON in the client's request to the exchange was malformed.
   * Details about the location of the parse error are provided. This
   * response is provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_JSON_INVALID_WITH_DETAILS = 1007,

  /**
   * A required parameter in the request to the exchange was missing.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PARAMETER_MISSING = 1008,

  /**
   * A parameter in the request to the exchange was malformed. This
   * response is provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PARAMETER_MALFORMED = 1009,

  /**
   * The exchange failed to obtain the transaction history of the given
   * coin from the database while generating an insufficient funds
   * errors.  This can happen during /deposit or /recoup requests. This
   * response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_COIN_HISTORY_DB_ERROR_INSUFFICIENT_FUNDS = 1010,

  /**
   * Internal logic error.  Some server-side function failed that really
   * should not. This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_INTERNAL_LOGIC_ERROR = 1011,

  /**
   * The method specified in a payto:// URI is not one we expected.
   */
  TALER_EC_PAYTO_WRONG_METHOD = 1012,

  /**
   * The payto:// URI is malformed.
   */
  TALER_EC_PAYTO_MALFORMED = 1013,

  /**
   * We failed to update the database of known coins.
   */
  TALER_EC_DB_COIN_HISTORY_STORE_ERROR = 1014,

  /**
   * The given reserve does not have sufficient funds to admit the
   * requested withdraw operation at this time.  The response includes
   * the current "balance" of the reserve as well as the transaction
   * "history" that lead to this balance.  This response is provided
   * with HTTP status code MHD_HTTP_CONFLICT.
   */
  TALER_EC_WITHDRAW_INSUFFICIENT_FUNDS = 1100,

  /**
   * The exchange has no information about the "reserve_pub" that was
   * given. This response is provided with HTTP status code
   * MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_WITHDRAW_RESERVE_UNKNOWN = 1101,

  /**
   * The amount to withdraw together with the fee exceeds the numeric
   * range for Taler amounts.  This is not a client failure, as the coin
   * value and fees come from the exchange's configuration. This
   * response is provided with HTTP status code MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_WITHDRAW_AMOUNT_FEE_OVERFLOW = 1102,

  /**
   * All of the deposited amounts into this reserve total up to a value
   * that is too big for the numeric range for Taler amounts. This is
   * not a client failure, as the transaction history comes from the
   * exchange's configuration.  This response is provided with HTTP
   * status code MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_AMOUNT_DEPOSITS_OVERFLOW = 1103,

  /**
   * For one of the historic withdrawals from this reserve, the exchange
   * could not find the denomination key. This is not a client failure,
   * as the transaction history comes from the exchange's configuration.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_WITHDRAW_HISTORIC_DENOMINATION_KEY_NOT_FOUND = 1104,

  /**
   * All of the withdrawals from reserve total up to a value that is too
   * big for the numeric range for Taler amounts. This is not a client
   * failure, as the transaction history comes from the exchange's
   * configuration.  This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_WITHDRAW_AMOUNT_WITHDRAWALS_OVERFLOW = 1105,

  /**
   * The exchange somehow knows about this reserve, but there seem to
   * have been no wire transfers made.  This is not a client failure, as
   * this is a database consistency issue of the exchange.  This
   * response is provided with HTTP status code MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_WITHDRAW_RESERVE_WITHOUT_WIRE_TRANSFER = 1106,

  /**
   * The exchange failed to create the signature using the denomination
   * key.  This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
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
   * The exchange is not aware of the denomination key the wallet
   * requested for the withdrawal. This response is provided with HTTP
   * status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_WITHDRAW_DENOMINATION_KEY_NOT_FOUND = 1110,

  /**
   * The signature of the reserve is not valid.  This response is
   * provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_WITHDRAW_RESERVE_SIGNATURE_INVALID = 1111,

  /**
   * When computing the reserve history, we ended up with a negative
   * overall balance, which should be impossible. This response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_WITHDRAW_HISTORY_DB_ERROR_INSUFFICIENT_FUNDS = 1112,

  /**
   * When computing the reserve history, we ended up with a negative
   * overall balance, which should be impossible. This response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_WITHDRAW_RESERVE_HISTORY_IMPOSSIBLE = 1113,

  /**
   * Validity period of the coin to be withdrawn is in the future.
   * Returned with an HTTP status of #MHD_HTTP_PRECONDITION_FAILED.
   */
  TALER_EC_WITHDRAW_VALIDITY_IN_FUTURE = 1114,

  /**
   * Withdraw period of the coin to be withdrawn is in the past.
   * Returned with an HTTP status of #MHD_HTTP_GONE.
   */
  TALER_EC_WITHDRAW_VALIDITY_IN_PAST = 1115,

  /**
   * Withdraw period of the coin to be withdrawn is in the past.
   * Returned with an HTTP status of #MHD_HTTP_GONE.
   */
  TALER_EC_DENOMINATION_KEY_LOST = 1116,

  /**
   * The exchange failed to obtain the transaction history of the given
   * reserve from the database. This response is provided with HTTP
   * status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_RESERVE_STATUS_DB_ERROR = 1150,

  /**
   * The reserve status was requested using a unknown key, to be
   * returned with 404 Not Found.
   */
  TALER_EC_RESERVE_STATUS_UNKNOWN = 1151,

  /**
   * The respective coin did not have sufficient residual value for the
   * /deposit operation (i.e. due to double spending). The "history" in
   * the respose provides the transaction history of the coin proving
   * this fact.  This response is provided with HTTP status code
   * MHD_HTTP_CONFLICT.
   */
  TALER_EC_DEPOSIT_INSUFFICIENT_FUNDS = 1200,

  /**
   * The exchange failed to obtain the transaction history of the given
   * coin from the database (this does not happen merely because the
   * coin is seen by the exchange for the first time). This response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
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
   * DB behind the back of the exchange process).  Hence the deposit is
   * being refused.  This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_DEPOSIT_DB_DENOMINATION_KEY_UNKNOWN = 1203,

  /**
   * The exchange was trying to lookup the denomination key for the
   * purpose of a DEPOSIT operation. However, the denomination key is
   * unavailable for that purpose. This can be because it is entirely
   * unknown to the exchange or not in the validity period for the
   * deposit operation.  Hence the deposit is being refused.  This
   * response is provided with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_DEPOSIT_DENOMINATION_KEY_UNKNOWN = 1204,

  /**
   * The signature made by the coin over the deposit permission is not
   * valid.  This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
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
   * would be negative.  This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_DEPOSIT_NEGATIVE_VALUE_AFTER_FEE = 1207,

  /**
   * The stated refund deadline is after the wire deadline. This
   * response is provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_DEPOSIT_REFUND_DEADLINE_AFTER_WIRE_DEADLINE = 1208,

  /**
   * The exchange does not recognize the validity of or support the
   * given wire format type. This response is provided with HTTP status
   * code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_TYPE = 1209,

  /**
   * The exchange failed to canonicalize and hash the given wire format.
   * For example, the merchant failed to provide the "salt" or a valid
   * payto:// URI in the wire details.  Note that while the exchange
   * will do some basic sanity checking on the wire details, it cannot
   * warrant that the banking system will ultimately be able to route to
   * the specified address, even if this check passed. This response is
   * provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_JSON = 1210,

  /**
   * The hash of the given wire address does not match the hash
   * specified in the proposal data.  This response is provided with
   * HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_CONTRACT_HASH_CONFLICT = 1211,

  /**
   * The exchange detected that the given account number is invalid for
   * the selected wire format type.  This response is provided with HTTP
   * status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_ACCOUNT_NUMBER = 1213,

  /**
   * Timestamp included in deposit permission is intolerably far off
   * with respect to the clock of the exchange.
   */
  TALER_EC_DEPOSIT_INVALID_TIMESTAMP = 1218,

  /**
   * Validity period of the denomination key is in the future.  Returned
   * with an HTTP status of MHD_HTTP_PRECONDITION_FAILED.
   */
  TALER_EC_DEPOSIT_DENOMINATION_VALIDITY_IN_FUTURE = 1219,

  /**
   * Denomination key of the coin is past the deposit deadline.
   * Returned with an HTTP status of #MHD_HTTP_GONE.
   */
  TALER_EC_DEPOSIT_DENOMINATION_EXPIRED = 1220,

  /**
   * The respective coin did not have sufficient residual value for the
   * /refresh/melt operation.  The "history" in this response provdes
   * the "residual_value" of the coin, which may be less than its
   * "original_value".  This response is provided with HTTP status code
   * MHD_HTTP_CONFLICT.
   */
  TALER_EC_REFRESH_MELT_INSUFFICIENT_FUNDS = 1300,

  /**
   * The respective coin did not have sufficient residual value for the
   * /refresh/melt operation.  The "history" in this response provdes
   * the "residual_value" of the coin, which may be less than its
   * "original_value".  This response is provided with HTTP status code
   * MHD_HTTP_CONFLICT.
   */
  TALER_EC_TALER_EC_REFRESH_MELT_DENOMINATION_KEY_NOT_FOUND = 1301,

  /**
   * The exchange had an internal error reconstructing the transaction
   * history of the coin that was being melted. This response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
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
   * The exchange failed to store session data in the database. This
   * response is provided with HTTP status code MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_REFRESH_MELT_DB_STORE_SESSION_ERROR = 1304,

  /**
   * The exchange encountered melt fees exceeding the melted coin's
   * contribution.  This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_MELT_FEES_EXCEED_CONTRIBUTION = 1305,

  /**
   * The denomination key signature on the melted coin is invalid. This
   * response is provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_MELT_DENOMINATION_SIGNATURE_INVALID = 1306,

  /**
   * The signature made with the coin to be melted is invalid. This
   * response is provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_MELT_COIN_SIGNATURE_INVALID = 1307,

  /**
   * The exchange failed to obtain the transaction history of the given
   * coin from the database while generating an insufficient funds
   * errors. This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_REFRESH_MELT_HISTORY_DB_ERROR_INSUFFICIENT_FUNDS = 1308,

  /**
   * The denomination of the given coin has past its expiration date and
   * it is also not a valid zombie (that is, was not refreshed with the
   * fresh coin being subjected to recoup).
   */
  TALER_EC_REFRESH_MELT_COIN_EXPIRED_NO_ZOMBIE = 1309,

  /**
   * The exchange is unaware of the denomination key that was used to
   * sign the melted zombie coin.  This response is provided with HTTP
   * status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_REFRESH_RECOUP_DENOMINATION_KEY_NOT_FOUND = 1351,

  /**
   * Validity period of the denomination key is in the future.  Returned
   * with an HTTP status of #MHD_HTTP_PRECONDITION_FAILED.
   */
  TALER_EC_REFRESH_RECOUP_DENOMINATION_VALIDITY_IN_FUTURE = 1352,

  /**
   * Denomination key of the coin is past the deposit deadline.
   * Returned with an HTTP status of #MHD_HTTP_GONE.
   */
  TALER_EC_REFRESH_RECOUP_DENOMINATION_EXPIRED = 1353,

  /**
   * Denomination key of the coin is past the deposit deadline.
   * Returned with an HTTP status of #MHD_HTTP_GONE.
   */
  TALER_EC_REFRESH_ZOMBIE_DENOMINATION_EXPIRED = 1354,

  /**
   * The provided transfer keys do not match up with the original
   * commitment.  Information about the original commitment is included
   * in the response.  This response is provided with HTTP status code
   * MHD_HTTP_CONFLICT.
   */
  TALER_EC_REFRESH_REVEAL_COMMITMENT_VIOLATION = 1370,

  /**
   * Failed to produce the blinded signatures over the coins to be
   * returned. This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_REFRESH_REVEAL_SIGNING_ERROR = 1371,

  /**
   * The exchange is unaware of the refresh session specified in the
   * request. This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_REVEAL_SESSION_UNKNOWN = 1372,

  /**
   * The exchange failed to retrieve valid session data from the
   * database. This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_REFRESH_REVEAL_DB_FETCH_SESSION_ERROR = 1373,

  /**
   * The exchange failed to retrieve previously revealed data from the
   * database.  This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_REFRESH_REVEAL_DB_FETCH_REVEAL_ERROR = 1374,

  /**
   * The exchange failed to retrieve commitment data from the database.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_ERROR.
   */
  TALER_EC_REFRESH_REVEAL_DB_COMMIT_ERROR = 1375,

  /**
   * The size of the cut-and-choose dimension of the private transfer
   * keys request does not match #TALER_CNC_KAPPA - 1. This response is
   * provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_REVEAL_CNC_TRANSFER_ARRAY_SIZE_INVALID = 1376,

  /**
   * The number of coins to be created in refresh exceeds the limits of
   * the exchange. private transfer keys request does not match
   * #TALER_CNC_KAPPA - 1. This response is provided with HTTP status
   * code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_REVEAL_NEW_DENOMS_ARRAY_SIZE_EXCESSIVE = 1377,

  /**
   * The number of envelopes given does not match the number of
   * denomination keys given. This response is provided with HTTP status
   * code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_REVEAL_NEW_DENOMS_ARRAY_SIZE_MISSMATCH = 1378,

  /**
   * The exchange encountered a numeric overflow totaling up the cost
   * for the refresh operation.  This response is provided with HTTP
   * status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_REFRESH_REVEAL_COST_CALCULATION_OVERFLOW = 1379,

  /**
   * The exchange's cost calculation shows that the melt amount is below
   * the costs of the transaction.  This response is provided with HTTP
   * status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_REVEAL_AMOUNT_INSUFFICIENT = 1380,

  /**
   * The exchange is unaware of the denomination key that was requested
   * for one of the fresh coins.  This response is provided with HTTP
   * status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_REVEAL_FRESH_DENOMINATION_KEY_NOT_FOUND = 1381,

  /**
   * The signature made with the coin over the link data is invalid.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFRESH_REVEAL_LINK_SIGNATURE_INVALID = 1382,

  /**
   * The exchange failed to generate the signature as it could not find
   * the signing key for the denomination. This response is provided
   * with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_REFRESH_REVEAL_KEYS_MISSING = 1383,

  /**
   * The coin specified in the link request is unknown to the exchange.
   * This response is provided with HTTP status code MHD_HTTP_NOT_FOUND.
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
   * The exchange knows about the coin we were asked to refund, but not
   * about the specific /deposit operation.  Hence, we cannot issue a
   * refund (as we do not know if this merchant public key is authorized
   * to do a refund).  This response is provided with HTTP status code
   * MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_REFUND_DEPOSIT_NOT_FOUND = 1503,

  /**
   * The currency specified for the refund is different from the
   * currency of the coin.  This response is provided with HTTP status
   * code MHD_HTTP_PRECONDITION_FAILED.
   */
  TALER_EC_REFUND_CURRENCY_MISSMATCH = 1504,

  /**
   * When we tried to check if we already paid out the coin, the
   * exchange's database suddenly disagreed with data it previously
   * provided (internal inconsistency). This response is provided with
   * HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_REFUND_DB_INCONSISTENT = 1505,

  /**
   * The exchange can no longer refund the customer/coin as the money
   * was already transferred (paid out) to the merchant. (It should be
   * past the refund deadline.) This response is provided with HTTP
   * status code MHD_HTTP_GONE.
   */
  TALER_EC_REFUND_MERCHANT_ALREADY_PAID = 1506,

  /**
   * The amount the exchange was asked to refund exceeds (with fees) the
   * total amount of the deposit (including fees). This response is
   * provided with HTTP status code MHD_HTTP_PRECONDITION_FAILED.
   */
  TALER_EC_REFUND_INSUFFICIENT_FUNDS = 1507,

  /**
   * The exchange failed to recover information about the denomination
   * key of the refunded coin (even though it recognizes the key).
   * Hence it could not check the fee strucutre. This response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_REFUND_DENOMINATION_KEY_NOT_FOUND = 1508,

  /**
   * The refund fee specified for the request is lower than the refund
   * fee charged by the exchange for the given denomination key of the
   * refunded coin. This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFUND_FEE_TOO_LOW = 1509,

  /**
   * The exchange failed to store the refund information to its
   * database. This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_REFUND_STORE_DB_ERROR = 1510,

  /**
   * The refund fee is specified in a different currency than the refund
   * amount. This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFUND_FEE_CURRENCY_MISSMATCH = 1511,

  /**
   * The refunded amount is smaller than the refund fee, which would
   * result in a negative refund. This response is provided with HTTP
   * status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFUND_FEE_ABOVE_AMOUNT = 1512,

  /**
   * The signature of the merchant is invalid. This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_REFUND_MERCHANT_SIGNATURE_INVALID = 1513,

  /**
   * Merchant backend failed to create the refund confirmation
   * signature. This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_REFUND_MERCHANT_SIGNING_FAILED = 1514,

  /**
   * The wire format specified in the "sender_account_details" is not
   * understood or not supported by this exchange. Returned with an HTTP
   * status code of MHD_HTTP_NOT_FOUND. (As we did not find an
   * interpretation of the wire format.)
   */
  TALER_EC_ADMIN_ADD_INCOMING_WIREFORMAT_UNSUPPORTED = 1600,

  /**
   * The currency specified in the "amount" parameter is not supported
   * by this exhange.  Returned with an HTTP status code of
   * MHD_HTTP_BAD_REQUEST.
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
   * the wire transfer) trying to lookup a wire transfer identifier in
   * the database.  This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSFER_DB_FETCH_FAILED = 1700,

  /**
   * The exchange found internally inconsistent data when resolving a
   * wire transfer identifier in the database.  This response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSFER_DB_INCONSISTENT = 1701,

  /**
   * The exchange did not find information about the specified wire
   * transfer identifier in the database.  This response is provided
   * with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_TRACK_TRANSFER_WTID_NOT_FOUND = 1702,

  /**
   * The exchange did not find information about the wire transfer fees
   * it charged. This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSFER_WIRE_FEE_NOT_FOUND = 1703,

  /**
   * The exchange found a wire fee that was above the total transfer
   * value (and thus could not have been charged). This response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSFER_WIRE_FEE_INCONSISTENT = 1704,

  /**
   * The exchange found internally inconsistent fee data when resolving
   * a transaction in the database.  This response is provided with HTTP
   * status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSACTION_DB_FEE_INCONSISTENT = 1800,

  /**
   * The exchange encountered an error (that is not about not finding
   * the transaction) trying to lookup a transaction in the database.
   * This response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSACTION_DB_FETCH_FAILED = 1801,

  /**
   * The exchange did not find information about the specified
   * transaction in the database.  This response is provided with HTTP
   * status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_TRACK_TRANSACTION_NOT_FOUND = 1802,

  /**
   * The exchange failed to identify the wire transfer of the
   * transaction (or information about the plan that it was supposed to
   * still happen in the future).  This response is provided with HTTP
   * status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSACTION_WTID_RESOLUTION_ERROR = 1803,

  /**
   * The signature of the merchant is invalid. This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_TRACK_TRANSACTION_MERCHANT_SIGNATURE_INVALID = 1804,

  /**
   * The given denomination key is not in the "recoup" set of the
   * exchange right now.  This response is provided with an HTTP status
   * code of MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_RECOUP_DENOMINATION_KEY_UNKNOWN = 1850,

  /**
   * The given coin signature is invalid for the request. This response
   * is provided with an HTTP status code of MHD_HTTP_FORBIDDEN.
   */
  TALER_EC_RECOUP_SIGNATURE_INVALID = 1851,

  /**
   * The signature of the denomination key over the coin is not valid.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_RECOUP_DENOMINATION_SIGNATURE_INVALID = 1852,

  /**
   * The exchange failed to access its own database about reserves. This
   * response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_RECOUP_DB_FETCH_FAILED = 1853,

  /**
   * The exchange could not find the corresponding withdraw operation.
   * The request is denied.  This response is provided with an HTTP
   * status code of MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_RECOUP_WITHDRAW_NOT_FOUND = 1854,

  /**
   * The exchange obtained an internally inconsistent transaction
   * history for the given coin. This response is provided with HTTP
   * status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_RECOUP_HISTORY_DB_ERROR = 1855,

  /**
   * The exchange failed to store information about the recoup to be
   * performed in the database. This response is provided with HTTP
   * status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_RECOUP_DB_PUT_FAILED = 1856,

  /**
   * The coin's remaining balance is zero.  The request is denied. This
   * response is provided with an HTTP status code of
   * MHD_HTTP_FORBIDDEN.
   */
  TALER_EC_RECOUP_COIN_BALANCE_ZERO = 1857,

  /**
   * The exchange failed to reproduce the coin's blinding. This response
   * is provided with an HTTP status code of
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_RECOUP_BLINDING_FAILED = 1858,

  /**
   * The coin's remaining balance is zero.  The request is denied. This
   * response is provided with an HTTP status code of
   * MHD_HTTP_INTERNAL_SERVER_ERROR
   */
  TALER_EC_RECOUP_COIN_BALANCE_NEGATIVE = 1859,

  /**
   * Validity period of the denomination key is in the future.  Returned
   * with an HTTP status of #MHD_HTTP_PRECONDITION_FAILED.
   */
  TALER_EC_RECOUP_DENOMINATION_VALIDITY_IN_FUTURE = 1860,

  /**
   * The "have" parameter was not a natural number. This reponse is
   * provied with an HTTP status code of MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_KEYS_HAVE_NOT_NUMERIC = 1900,

  /**
   * We currently cannot find any keys. This reponse is provied with an
   * HTTP status code of MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_KEYS_MISSING = 1901,

  /**
   * The backend could not find the merchant instance specified in the
   * request.   This response is provided with HTTP status code
   * MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_INSTANCE_UNKNOWN = 2000,

  /**
   * The backend lacks a wire transfer method configuration option for
   * the given instance.
   */
  TALER_EC_PROPOSAL_INSTANCE_CONFIGURATION_LACKS_WIRE = 2002,

  /**
   * The exchange failed to provide a meaningful response to a /deposit
   * request.  This response is provided with HTTP status code
   * MHD_HTTP_SERVICE_UNAVAILABLE.
   */
  TALER_EC_PAY_EXCHANGE_FAILED = 2101,

  /**
   * The merchant failed to commit the exchanges' response to a /deposit
   * request to its database.  This response is provided with HTTP
   * status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_PAY_DB_STORE_PAY_ERROR = 2102,

  /**
   * The specified exchange is not supported/trusted by this merchant.
   * This response is provided with HTTP status code
   * MHD_HTTP_PRECONDITION_FAILED.
   */
  TALER_EC_PAY_EXCHANGE_REJECTED = 2103,

  /**
   * The denomination key used for payment is not listed among the
   * denomination keys of the exchange.  This response is provided with
   * HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_DENOMINATION_KEY_NOT_FOUND = 2104,

  /**
   * The denomination key used for payment is not audited by an auditor
   * approved by the merchant.  This response is provided with HTTP
   * status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_DENOMINATION_KEY_AUDITOR_FAILURE = 2105,

  /**
   * There was an integer overflow totaling up the amounts or deposit
   * fees in the payment.  This response is provided with HTTP status
   * code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_AMOUNT_OVERFLOW = 2106,

  /**
   * The deposit fees exceed the total value of the payment. This
   * response is provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_FEES_EXCEED_PAYMENT = 2107,

  /**
   * After considering deposit fees, the payment is insufficient to
   * satisfy the required amount for the contract. This response is
   * provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_PAYMENT_INSUFFICIENT_DUE_TO_FEES = 2108,

  /**
   * While the merchant is happy to cover all applicable deposit fees,
   * the payment is insufficient to satisfy the required amount for the
   * contract.  This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_PAYMENT_INSUFFICIENT = 2109,

  /**
   * The signature over the contract of one of the coins was invalid.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_COIN_SIGNATURE_INVALID = 2110,

  /**
   * We failed to contact the exchange for the /pay request. This
   * response is provided with HTTP status code
   * MHD_HTTP_SERVICE_UNAVAILABLE.
   */
  TALER_EC_PAY_EXCHANGE_TIMEOUT = 2111,

  /**
   * The signature over the contract of the merchant was invalid. This
   * response is provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_MERCHANT_SIGNATURE_INVALID = 2113,

  /**
   * The refund deadline was after the transfer deadline. This response
   * is provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_REFUND_DEADLINE_PAST_WIRE_TRANSFER_DEADLINE = 2114,

  /**
   * The request fails to provide coins for the payment. This response
   * is provided with HTTP status code MHD_HTTP_BAD_REQUEST.
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
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_DB_TRANSACTION_ID_CONFLICT = 2118,

  /**
   * The merchant failed to store the merchant's state with respect to
   * the transaction in its database.  This response is provided with
   * HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_PAY_DB_STORE_TRANSACTION_ERROR = 2119,

  /**
   * The exchange failed to provide a valid response to the merchant's
   * /keys request. This response is provided with HTTP status code
   * MHD_HTTP_SERVICE_UNAVAILABLE.
   */
  TALER_EC_PAY_EXCHANGE_KEYS_FAILURE = 2120,

  /**
   * The payment is too late, the offer has expired. This response is
   * provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_OFFER_EXPIRED = 2121,

  /**
   * The "merchant" field is missing in the proposal data. This response
   * is provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_PAY_MERCHANT_FIELD_MISSING = 2122,

  /**
   * Failed computing a hash code (likely server out-of-memory). This
   * response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_PAY_FAILED_COMPUTE_PROPOSAL_HASH = 2123,

  /**
   * Failed to locate merchant's account information matching the wire
   * hash given in the proposal. This response is provided with HTTP
   * status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_PAY_WIRE_HASH_UNKNOWN = 2124,

  /**
   * We got different currencies for the wire fee and the maximum wire
   * fee.  This response is provided with HTTP status code of
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_PAY_WIRE_FEE_CURRENCY_MISSMATCH = 2125,

  /**
   * The merchant refuses to abort and refund the payment operation as
   * the payment succeeded already. This response is provided with HTTP
   * status code of MHD_HTTP_FORBIDDEN.
   */
  TALER_EC_PAY_ABORT_REFUND_REFUSED_PAYMENT_COMPLETE = 2126,

  /**
   * A unknown merchant public key was included in the payment.  That
   * happens typically when the wallet sends the payment to the wrong
   * merchant instance.
   */
  TALER_EC_PAY_WRONG_INSTANCE = 2127,

  /**
   * Integer overflow with sepcified timestamp argument detected. This
   * response is provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_HISTORY_TIMESTAMP_OVERFLOW = 2200,

  /**
   * Failed to retrieve history from merchant database. This response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_HISTORY_DB_FETCH_ERROR = 2201,

  /**
   * The backend could not find the contract specified in the request.
   * This response is provided with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_POLL_PAYMENT_CONTRACT_NOT_FOUND = 2250,

  /**
   * We failed to contact the exchange for the /track/transaction
   * request.  This response is provided with HTTP status code
   * MHD_HTTP_SERVICE_UNAVAILABLE.
   */
  TALER_EC_TRACK_TRANSACTION_EXCHANGE_TIMEOUT = 2300,

  /**
   * The backend could not find the transaction specified in the
   * request.   This response is provided with HTTP status code
   * MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_TRACK_TRANSACTION_TRANSACTION_UNKNOWN = 2302,

  /**
   * The backend had a database access error trying to retrieve
   * transaction data from its database. The response is provided with
   * HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSACTION_DB_FETCH_TRANSACTION_ERROR = 2303,

  /**
   * The backend had a database access error trying to retrieve payment
   * data from its database. The response is provided with HTTP status
   * code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSACTION_DB_FETCH_PAYMENT_ERROR = 2304,

  /**
   * The backend found no applicable deposits in the database. This is
   * odd, as we know about the transaction, but not about deposits we
   * made for the transaction.  The response is provided with HTTP
   * status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_TRACK_TRANSACTION_DB_NO_DEPOSITS_ERROR = 2305,

  /**
   * We failed to obtain a wire transfer identifier for one of the coins
   * in the transaction.  The response is provided with HTTP status code
   * MHD_HTTP_FAILED_DEPENDENCY if the exchange had a hard error, or
   * MHD_HTTP_ACCEPTED if the exchange signaled that the transfer was in
   * progress.
   */
  TALER_EC_TRACK_TRANSACTION_COIN_TRACE_ERROR = 2306,

  /**
   * We failed to obtain the full wire transfer identifier for the
   * transfer one of the coins was aggregated into. The response is
   * provided with HTTP status code MHD_HTTP_FAILED_DEPENDENCY.
   */
  TALER_EC_TRACK_TRANSACTION_WIRE_TRANSFER_TRACE_ERROR = 2307,

  /**
   * We got conflicting reports from the exhange with respect to which
   * transfers are included in which aggregate. The response is provided
   * with HTTP status code MHD_HTTP_FAILED_DEPENDENCY.
   */
  TALER_EC_TRACK_TRANSACTION_CONFLICTING_REPORTS = 2308,

  /**
   * We failed to contact the exchange for the /track/transfer request.
   * This response is provided with HTTP status code
   * MHD_HTTP_SERVICE_UNAVAILABLE.
   */
  TALER_EC_TRACK_TRANSFER_EXCHANGE_TIMEOUT = 2400,

  /**
   * We failed to persist coin wire transfer information in our merchant
   * database. The response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSFER_DB_STORE_COIN_ERROR = 2402,

  /**
   * We internally failed to execute the /track/transfer request. The
   * response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSFER_REQUEST_ERROR = 2403,

  /**
   * We failed to persist wire transfer information in our merchant
   * database. The response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSFER_DB_STORE_TRANSFER_ERROR = 2404,

  /**
   * The exchange returned an error from /track/transfer. The response
   * is provided with HTTP status code MHD_HTTP_FAILED_DEPENDENCY.
   */
  TALER_EC_TRACK_TRANSFER_EXCHANGE_ERROR = 2405,

  /**
   * We failed to fetch deposit information from our merchant database.
   * The response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSFER_DB_FETCH_DEPOSIT_ERROR = 2406,

  /**
   * We encountered an internal logic error. The response is provided
   * with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TRACK_TRANSFER_DB_INTERNAL_LOGIC_ERROR = 2407,

  /**
   * The exchange gave conflicting information about a coin which has
   * been wire transferred. The response is provided with HTTP status
   * code MHD_HTTP_FAILED_DEPENDENCY.
   */
  TALER_EC_TRACK_TRANSFER_CONFLICTING_REPORTS = 2408,

  /**
   * The merchant backend had problems in creating the JSON response.
   */
  TALER_EC_TRACK_TRANSFER_JSON_RESPONSE_ERROR = 2409,

  /**
   * The exchange charged a different wire fee than what it originally
   * advertised, and it is higher.  The response is provied with an HTTP
   * status of MHD_HTTP_BAD_DEPENDENCY.
   */
  TALER_EC_TRACK_TRANSFER_JSON_BAD_WIRE_FEE = 2410,

  /**
   * The hash provided in the request of /map/in does not match the
   * contract sent alongside in the same request.
   */
  TALER_EC_MAP_IN_UNMATCHED_HASH = 2500,

  /**
   * The backend encountered an error while trying to store the
   * h_contract_terms into the database. The response is provided with
   * HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_PROPOSAL_STORE_DB_ERROR = 2501,

  /**
   * The backend encountered an error while trying to retrieve the
   * proposal data from database.  Likely to be an internal error.
   */
  TALER_EC_PROPOSAL_LOOKUP_DB_ERROR = 2502,

  /**
   * The proposal being looked up is not found on this merchant.
   */
  TALER_EC_PROPOSAL_LOOKUP_NOT_FOUND = 2503,

  /**
   * The proposal had no timestamp and the backend failed to obtain the
   * local time. Likely to be an internal error.
   */
  TALER_EC_PROPOSAL_NO_LOCALTIME = 2504,

  /**
   * The order provided to the backend could not be parsed, some
   * required fields were missing or ill-formed. Returned as a bad
   * request.
   */
  TALER_EC_PROPOSAL_ORDER_PARSE_ERROR = 2505,

  /**
   * The backend encountered an error while trying to find the existing
   * proposal in the database. The response is provided with HTTP status
   * code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_PROPOSAL_STORE_DB_ERROR_HARD = 2506,

  /**
   * The backend encountered an error while trying to find the existing
   * proposal in the database. The response is provided with HTTP status
   * code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_PROPOSAL_STORE_DB_ERROR_SOFT = 2507,

  /**
   * The backend encountered an error: the proposal already exists. The
   * response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_PROPOSAL_STORE_DB_ERROR_ALREADY_EXISTS = 2508,

  /**
   * The order provided to the backend uses an amount in a currency that
   * does not match the backend's configuration. Returned as a bad
   * request.
   */
  TALER_EC_PROPOSAL_ORDER_BAD_CURRENCY = 2509,

  /**
   * The frontend gave an unknown order id to issue the refund to.
   */
  TALER_EC_REFUND_ORDER_ID_UNKNOWN = 2601,

  /**
   * The amount to be refunded is inconsistent: either is lower than the
   * previous amount being awarded, or it is too big to be paid back. In
   * this second case, the fault stays on the business dept. side.
   * Returned with an HTTP status of #MHD_HTTP_CONFLICT.
   */
  TALER_EC_REFUND_INCONSISTENT_AMOUNT = 2602,

  /**
   * The backend encountered an error while trying to retrieve the
   * payment data from database.  Likely to be an internal error.
   */
  TALER_EC_REFUND_LOOKUP_DB_ERROR = 2603,

  /**
   * The backend encountered an error while trying to retrieve the
   * payment data from database.  Likely to be an internal error.
   */
  TALER_EC_REFUND_MERCHANT_DB_COMMIT_ERROR = 2604,

  /**
   * Payments are stored in a single db transaction; this error
   * indicates that one db operation within that transaction failed.
   * This might involve storing of coins or other related db operations,
   * like starting/committing the db transaction or marking a contract
   * as paid.
   */
  TALER_EC_PAY_DB_STORE_PAYMENTS_ERROR = 2605,

  /**
   * The backend failed to sign the refund request.
   */
  TALER_EC_PAY_REFUND_SIGNATURE_FAILED = 2606,

  /**
   * The backend knows the instance that was supposed to support the
   * tip, but it was not configured for tipping (i.e. has no exchange
   * associated with it).  Likely to be a configuration error. Returned
   * with an HTTP status code of "NOT FOUND".
   */
  TALER_EC_TIP_AUTHORIZE_INSTANCE_DOES_NOT_TIP = 2701,

  /**
   * The reserve that was used to fund the tips has expired. Returned
   * with an HTTP status code of "not found".
   */
  TALER_EC_TIP_AUTHORIZE_RESERVE_EXPIRED = 2702,

  /**
   * The reserve that was used to fund the tips was not found in the DB.
   * Returned with an HTTP status code of "not found".
   */
  TALER_EC_TIP_AUTHORIZE_RESERVE_UNKNOWN = 2703,

  /**
   * The backend knows the instance that was supposed to support the
   * tip, and it was configured for tipping. However, the funds
   * remaining are insufficient to cover the tip, and the merchant
   * should top up the reserve. Returned with an HTTP status code of
   * "PRECONDITION FAILED".
   */
  TALER_EC_TIP_AUTHORIZE_INSUFFICIENT_FUNDS = 2704,

  /**
   * The backend had trouble accessing the database to persist
   * information about the tip authorization. Returned with an HTTP
   * status code of internal error.
   */
  TALER_EC_TIP_AUTHORIZE_DB_HARD_ERROR = 2705,

  /**
   * The backend had trouble accessing the database to persist
   * information about the tip authorization. The problem might be
   * fixable by repeating the transaction.
   */
  TALER_EC_TIP_AUTHORIZE_DB_SOFT_ERROR = 2706,

  /**
   * The backend failed to obtain a reserve status from the exchange.
   */
  TALER_EC_TIP_QUERY_RESERVE_STATUS_FAILED_EXCHANGE_DOWN = 2707,

  /**
   * The backend got an empty (!) reserve history from the exchange.
   */
  TALER_EC_TIP_QUERY_RESERVE_HISTORY_FAILED_EMPTY = 2708,

  /**
   * The backend got an invalid reserve history (fails to start with a
   * deposit) from the exchange.
   */
  TALER_EC_TIP_QUERY_RESERVE_HISTORY_INVALID_NO_DEPOSIT = 2709,

  /**
   * The backend got an reserve history with a bad currency from the
   * exchange.
   */
  TALER_EC_TIP_QUERY_RESERVE_HISTORY_INVALID_CURRENCY = 2710,

  /**
   * The backend got a reserve with a currency that does not match the
   * backend's currency.
   */
  TALER_EC_TIP_QUERY_RESERVE_CURRENCY_MISSMATCH = 2711,

  /**
   * The backend got a reserve history with amounts it cannot process
   * (addition failure in deposits).
   */
  TALER_EC_TIP_QUERY_RESERVE_HISTORY_ARITHMETIC_ISSUE_DEPOSIT = 2712,

  /**
   * The backend got a reserve history with amounts it cannot process
   * (addition failure in withdraw amounts).
   */
  TALER_EC_TIP_QUERY_RESERVE_HISTORY_ARITHMETIC_ISSUE_WITHDRAW = 2713,

  /**
   * The backend got a reserve history with amounts it cannot process
   * (addition failure in closing amounts).
   */
  TALER_EC_TIP_QUERY_RESERVE_HISTORY_ARITHMETIC_ISSUE_CLOSED = 2714,

  /**
   * The backend got a reserve history with inconsistent amounts.
   */
  TALER_EC_TIP_QUERY_RESERVE_HISTORY_ARITHMETIC_ISSUE_INCONSISTENT = 2715,

  /**
   * The backend encountered a database error querying tipping reserves.
   */
  TALER_EC_TIP_QUERY_DB_ERROR = 2716,

  /**
   * The backend had trouble accessing the database to persist
   * information about enabling tips. Returned with an HTTP status code
   * of internal error.
   */
  TALER_EC_TIP_ENABLE_DB_TRANSACTION_ERROR = 2750,

  /**
   * The tip ID is unknown.  This could happen if the tip has expired.
   * Returned with an HTTP status code of "not found".
   */
  TALER_EC_TIP_PICKUP_TIP_ID_UNKNOWN = 2800,

  /**
   * The amount requested exceeds the remaining tipping balance for this
   * tip ID. Returned with an HTTP status code of "Conflict" (as it
   * conflicts with a previous pickup operation).
   */
  TALER_EC_TIP_PICKUP_NO_FUNDS = 2801,

  /**
   * We encountered a DB error, repeating the request may work.
   */
  TALER_EC_TIP_PICKUP_DB_ERROR_SOFT = 2802,

  /**
   * We encountered a DB error, repeating the request will not help.
   * This is an internal server error.
   */
  TALER_EC_TIP_PICKUP_DB_ERROR_HARD = 2803,

  /**
   * The same pickup ID was already used for picking up a different
   * amount. This points to a very strange internal error as the pickup
   * ID is derived from the denomination key which is tied to a
   * particular amount. Hence this should also be an internal server
   * error.
   */
  TALER_EC_TIP_PICKUP_AMOUNT_CHANGED = 2804,

  /**
   * We failed to contact the exchange to obtain the denomination keys.
   * Returned with a response code "failed dependency" (424).
   */
  TALER_EC_TIP_PICKUP_EXCHANGE_DOWN = 2805,

  /**
   * We contacted the exchange to obtain any denomination keys, but got
   * no valid keys. Returned with a response code "failed dependency"
   * (424).
   */
  TALER_EC_TIP_PICKUP_EXCHANGE_LACKED_KEYS = 2806,

  /**
   * We contacted the exchange to obtain at least one of the
   * denomination keys specified in the request. Returned with a
   * response code "not found" (404).
   */
  TALER_EC_TIP_PICKUP_EXCHANGE_LACKED_KEY = 2807,

  /**
   * We encountered an arithmetic issue totaling up the amount to
   * withdraw. Returned with a response code of "bad request".
   */
  TALER_EC_TIP_PICKUP_EXCHANGE_AMOUNT_OVERFLOW = 2808,

  /**
   * The number of planchets specified exceeded the limit. Returned with
   * a response code of "bad request".
   */
  TALER_EC_TIP_PICKUP_EXCHANGE_TOO_MANY_PLANCHETS = 2809,

  /**
   * The tip id is unknown.  This could happen if the tip id is wrong or
   * the tip authorization expired.
   */
  TALER_EC_TIP_QUERY_TIP_ID_UNKNOWN = 2810,

  /**
   * We failed to contract terms from our merchant database. The
   * response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_CHECK_PAYMENT_DB_FETCH_CONTRACT_TERMS_ERROR = 2911,

  /**
   * We failed to contract terms from our merchant database. The
   * response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_CHECK_PAYMENT_DB_FETCH_ORDER_ERROR = 2912,

  /**
   * The order id we're checking is unknown, likely the frontend did not
   * create the order first.
   */
  TALER_EC_CHECK_PAYMENT_ORDER_ID_UNKNOWN = 2913,

  /**
   * Failed computing a hash code (likely server out-of-memory). This
   * response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_CHECK_PAYMENT_FAILED_COMPUTE_PROPOSAL_HASH = 2914,

  /**
   * Signature "session_sig" failed to verify. This response is provided
   * with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_CHECK_PAYMENT_SESSION_SIGNATURE_INVALID = 2915,

  /**
   * The signature from the exchange on the deposit confirmation is
   * invalid.  Returned with a "400 Bad Request" status code.
   */
  TALER_EC_DEPOSIT_CONFIRMATION_SIGNATURE_INVALID = 3000,

  /**
   * The auditor had trouble storing the deposit confirmation in its
   * database. Returned with an HTTP status code of
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_DEPOSIT_CONFIRMATION_STORE_DB_ERROR = 3001,

  /**
   * The auditor had trouble retrieving the exchange list from its
   * database. Returned with an HTTP status code of
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_LIST_EXCHANGES_DB_ERROR = 3002,

  /**
   * The auditor had trouble storing an exchange in its database.
   * Returned with an HTTP status code of
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_AUDITOR_EXCHANGE_STORE_DB_ERROR = 3003,

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
   * The exchange failed to compute the EdDSA test signature.  This
   * response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TEST_EDDSA_ERROR = 4002,

  /**
   * The exchange failed to generate an RSA key.  This response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TEST_RSA_GEN_ERROR = 4003,

  /**
   * The exchange failed to compute the public RSA key.  This response
   * is provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TEST_RSA_PUB_ERROR = 4004,

  /**
   * The exchange failed to compute the RSA signature.  This response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_TEST_RSA_SIGN_ERROR = 4005,

  /**
   * The JSON in the server's response was malformed.  This response is
   * provided with HTTP status code of 0.
   */
  TALER_EC_SERVER_JSON_INVALID = 5000,

  /**
   * A signature in the server's response was malformed.  This response
   * is provided with HTTP status code of 0.
   */
  TALER_EC_SERVER_SIGNATURE_INVALID = 5001,

  /**
   * Wire tranfer attempted with credit and debit party being the same
   * bank account.
   */
  TALER_EC_BANK_SAME_ACCOUNT = 5102,

  /**
   * Wire transfer impossible, due to financial limitation of the party
   * that attempted the payment.
   */
  TALER_EC_BANK_UNALLOWED_DEBIT = 5103,

  /**
   * Arithmetic operation between two amounts of different currency was
   * attempted.
   */
  TALER_EC_BANK_CURRENCY_MISMATCH = 5104,

  /**
   * At least one GET parameter was either missing or invalid for the
   * requested operation.
   */
  TALER_EC_BANK_PARAMETER_MISSING_OR_INVALID = 5105,

  /**
   * JSON body sent was invalid for the requested operation.
   */
  TALER_EC_BANK_JSON_INVALID = 5106,

  /**
   * Negative number was used (as value and/or fraction) to initiate a
   * Amount object.
   */
  TALER_EC_BANK_NEGATIVE_NUMBER_AMOUNT = 5107,

  /**
   * A number too big was used (as value and/or fraction) to initiate a
   * amount object.
   */
  TALER_EC_BANK_NUMBER_TOO_BIG = 5108,

  /**
   * Could not login for the requested operation.
   */
  TALER_EC_BANK_LOGIN_FAILED = 5109,

  /**
   * The bank account referenced in the requested operation was not
   * found.  Returned along "400 Not found".
   */
  TALER_EC_BANK_UNKNOWN_ACCOUNT = 5110,

  /**
   * The transaction referenced in the requested operation (typically a
   * reject operation), was not found.
   */
  TALER_EC_BANK_TRANSACTION_NOT_FOUND = 5111,

  /**
   * Bank received a malformed amount string.
   */
  TALER_EC_BANK_BAD_FORMAT_AMOUNT = 5112,

  /**
   * The client does not own the account credited by the transaction
   * which is to be rejected, so it has no rights do reject it.  To be
   * returned along HTTP 403 Forbidden.
   */
  TALER_EC_BANK_REJECT_NO_RIGHTS = 5200,

  /**
   * This error code is returned when no known exception types captured
   * the exception, and comes along with a 500 Internal Server Error.
   */
  TALER_EC_BANK_UNMANAGED_EXCEPTION = 5300,

  /**
   * This error code is used for all those exceptions that do not really
   * need a specific error code to return to the client, but need to
   * signal the middleware that the bank is not responding with 500
   * Internal Server Error.  Used for example when a client is trying to
   * register with a unavailable username.
   */
  TALER_EC_BANK_SOFT_EXCEPTION = 5400,

  /**
   * The request UID for a request to transfer funds has already been
   * used, but with different details for the transfer.
   */
  TALER_EC_BANK_TRANSFER_REQUEST_UID_REUSED = 5500,

  /**
   * The sync service failed to access its database. This response is
   * provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_SYNC_DB_FETCH_ERROR = 6000,

  /**
   * The sync service failed find the record in its database. This
   * response is provided with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_SYNC_BACKUP_UNKNOWN = 6001,

  /**
   * The sync service failed find the account in its database. This
   * response is provided with HTTP status code MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_SYNC_ACCOUNT_UNKNOWN = 6002,

  /**
   * The SHA-512 hash provided in the If-None-Match header is malformed.
   * This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_SYNC_BAD_IF_NONE_MATCH = 6003,

  /**
   * The SHA-512 hash provided in the If-Match header is malformed or
   * missing. This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_SYNC_BAD_IF_MATCH = 6004,

  /**
   * The signature provided in the "Sync-Signature" header is malformed
   * or missing. This response is provided with HTTP status code
   * MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_SYNC_BAD_SYNC_SIGNATURE = 6005,

  /**
   * The signature provided in the "Sync-Signature" header does not
   * match the account, old or new Etags. This response is provided with
   * HTTP status code MHD_HTTP_FORBIDDEN.
   */
  TALER_EC_SYNC_INVALID_SIGNATURE = 6007,

  /**
   * The "Content-length" field for the upload is either not a number,
   * or too big, or missing. This response is provided with HTTP status
   * code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_SYNC_BAD_CONTENT_LENGTH = 6008,

  /**
   * The "Content-length" field for the upload is too big based on the
   * server's terms of service. This response is provided with HTTP
   * status code MHD_HTTP_PAYLOAD_TOO_LARGE.
   */
  TALER_EC_SYNC_EXCESSIVE_CONTENT_LENGTH = 6009,

  /**
   * The server is out of memory to handle the upload. Trying again
   * later may succeed. This response is provided with HTTP status code
   * MHD_HTTP_PAYLOAD_TOO_LARGE.
   */
  TALER_EC_SYNC_OUT_OF_MEMORY_ON_CONTENT_LENGTH = 6010,

  /**
   * The uploaded data does not match the Etag. This response is
   * provided with HTTP status code MHD_HTTP_BAD_REQUEST.
   */
  TALER_EC_SYNC_INVALID_UPLOAD = 6011,

  /**
   * We failed to check for existing upload data in the database. This
   * response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_SYNC_DATABASE_FETCH_ERROR = 6012,

  /**
   * HTTP server was being shutdown while this operation was pending.
   * This response is provided with HTTP status code
   * MHD_HTTP_SERVICE_UNAVAILABLE.
   */
  TALER_EC_SYNC_SHUTDOWN = 6013,

  /**
   * HTTP server experienced a timeout while awaiting promised payment.
   * This response is provided with HTTP status code
   * MHD_HTTP_REQUEST_TIMEOUT.
   */
  TALER_EC_SYNC_PAYMENT_TIMEOUT = 6014,

  /**
   * Sync could not store order data in its own database. This response
   * is provided with HTTP status code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_SYNC_PAYMENT_CREATE_DB_ERROR = 6015,

  /**
   * Sync could not store payment confirmation in its own database. This
   * response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_SYNC_PAYMENT_CONFIRM_DB_ERROR = 6016,

  /**
   * Sync could not fetch information about possible existing orders
   * from its own database. This response is provided with HTTP status
   * code MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_SYNC_PAYMENT_CHECK_ORDER_DB_ERROR = 6017,

  /**
   * Sync could not setup the payment request with its own backend. This
   * response is provided with HTTP status code
   * MHD_HTTP_INTERNAL_SERVER_ERROR.
   */
  TALER_EC_SYNC_PAYMENT_CREATE_BACKEND_ERROR = 6018,

  /**
   * The sync service failed find the backup to be updated in its
   * database. This response is provided with HTTP status code
   * MHD_HTTP_NOT_FOUND.
   */
  TALER_EC_SYNC_PREVIOUS_BACKUP_UNKNOWN = 6019,

  /**
   * End of error code range.
   */
  TALER_EC_END = 9999,

};


#endif
