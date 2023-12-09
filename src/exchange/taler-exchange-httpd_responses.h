/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * @brief API for generating generic replies of the exchange; these
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
#include "taler_error_codes.h"
#include "taler-exchange-httpd.h"
#include "taler-exchange-httpd_db.h"


/**
 * Send assertion that the given denomination key hash
 * is unknown to us at this time.
 *
 * @param connection connection to the client
 * @param dph denomination public key hash
 * @return MHD result code
 */
MHD_RESULT
TEH_RESPONSE_reply_unknown_denom_pub_hash (
  struct MHD_Connection *connection,
  const struct TALER_DenominationHashP *dph);


/**
 * Return error message indicating that a reserve had
 * an insufficient balance for the given operation.
 *
 * @param connection connection to the client
 * @param ec specific error code to return with the reserve history
 * @param reserve_balance balance remaining in the reserve
 * @param balance_required the balance required for the operation
 * @param reserve_pub the reserve with insufficient balance
 * @return MHD result code
 */
MHD_RESULT
TEH_RESPONSE_reply_reserve_insufficient_balance (
  struct MHD_Connection *connection,
  enum TALER_ErrorCode ec,
  const struct TALER_Amount *reserve_balance,
  const struct TALER_Amount *balance_required,
  const struct TALER_ReservePublicKeyP *reserve_pub);

/**
 * Return error message indicating that a reserve requires age
 * restriction to be set during withdraw, that is: the age-withdraw
 * protocol MUST be used with commitment to an admissible age.
 *
 * @param connection connection to the client
 * @param maximum_allowed_age the balance required for the operation
 * @return MHD result code
 */
MHD_RESULT
TEH_RESPONSE_reply_reserve_age_restriction_required (
  struct MHD_Connection *connection,
  uint16_t maximum_allowed_age);


/**
 * Send information that a KYC check must be
 * satisfied to proceed to client.
 *
 * @param connection connection to the client
 * @param h_payto account identifier to include in reply
 * @param kyc details about the KYC requirements
 * @return MHD result code
 */
MHD_RESULT
TEH_RESPONSE_reply_kyc_required (struct MHD_Connection *connection,
                                 const struct TALER_PaytoHashP *h_payto,
                                 const struct TALER_EXCHANGEDB_KycStatus *kyc);


/**
 * Send information that an AML process is blocking
 * the operation right now.
 *
 * @param connection connection to the client
 * @param status current AML status
 * @return MHD result code
 */
MHD_RESULT
TEH_RESPONSE_reply_aml_blocked (struct MHD_Connection *connection,
                                enum TALER_AmlDecisionState status);


/**
 * Send assertion that the given denomination key hash
 * is not usable (typically expired) at this time.
 *
 * @param connection connection to the client
 * @param dph denomination public key hash
 * @param ec error code to use
 * @param oper name of the operation that is not allowed at this time
 * @return MHD result code
 */
MHD_RESULT
TEH_RESPONSE_reply_expired_denom_pub_hash (
  struct MHD_Connection *connection,
  const struct TALER_DenominationHashP *dph,
  enum TALER_ErrorCode ec,
  const char *oper);


/**
 * Send assertion that the given denomination cannot be used for this operation.
 *
 * @param connection connection to the client
 * @param dph denomination public key hash
 * @return MHD result code
 */
MHD_RESULT
TEH_RESPONSE_reply_invalid_denom_cipher_for_operation (
  struct MHD_Connection *connection,
  const struct TALER_DenominationHashP *dph);


/**
 * Send proof that a request is invalid to client because of
 * insufficient funds.  This function will create a message with all
 * of the operations affecting the coin that demonstrate that the coin
 * has insufficient value.
 *
 * @param connection connection to the client
 * @param ec error code to return
 * @param h_denom_pub hash of the denomination of the coin
 * @param coin_pub public key of the coin
 * @return MHD result code
 */
MHD_RESULT
TEH_RESPONSE_reply_coin_insufficient_funds (
  struct MHD_Connection *connection,
  enum TALER_ErrorCode ec,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub);

/**
 * Send proof that a request is invalid to client because of
 * a conflicting value for the age commitment hash of a coin.
 * This function will create a message with the conflicting
 * hash value for the age commitment of the given coin.
 *
 * @param connection connection to the client
 * @param ec error code to return
 * @param h_denom_pub hash of the denomination of the coin
 * @param coin_pub public key of the coin
 * @param h_age_commitment hash of the age commitment as found in the database
 * @return MHD result code
 */
MHD_RESULT
TEH_RESPONSE_reply_coin_age_commitment_conflict (
  struct MHD_Connection *connection,
  enum TALER_ErrorCode ec,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_AgeCommitmentHash *h_age_commitment);

/**
 * Fundamental details about a purse.
 */
struct TEH_PurseDetails
{
  /**
   * When should the purse expire.
   */
  struct GNUNET_TIME_Timestamp purse_expiration;

  /**
   * Hash of the contract terms of the purse.
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Public key of the purse we are creating.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * Total amount to be put into the purse.
   */
  struct TALER_Amount target_amount;
};


/**
 * Send confirmation that a purse was created with
 * the current purse balance.
 *
 * @param connection connection to the client
 * @param pd purse details
 * @param exchange_timestamp our time for purse creation
 * @param purse_balance current balance in the purse
 * @return MHD result code
 */
MHD_RESULT
TEH_RESPONSE_reply_purse_created (
  struct MHD_Connection *connection,
  struct GNUNET_TIME_Timestamp exchange_timestamp,
  const struct TALER_Amount *purse_balance,
  const struct TEH_PurseDetails *pd);


/**
 * Callback used to set headers in a response.
 *
 * @param cls closure
 * @param[in,out] resp response to modify
 */
typedef void
(*TEH_RESPONSE_SetHeaders)(void *cls,
                           struct MHD_Response *resp);


/**
 * Generate a HTTP "Not modified" response with the
 * given @a etags.
 *
 * @param connection connection to queue response on
 * @param etags ETag header to set
 * @param cb callback to modify response headers
 * @param cb_cls closure for @a cb
 * @return MHD result code
 */
MHD_RESULT
TEH_RESPONSE_reply_not_modified (
  struct MHD_Connection *connection,
  const char *etags,
  TEH_RESPONSE_SetHeaders cb,
  void *cb_cls);


#endif
