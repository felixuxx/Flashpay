/*
  This file is part of TALER
  Copyright (C) 2015-2024 Taler Systems SA

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
 * @file include/taler_bank_service.h
 * @brief C interface of libtalerbank, a C library to use the Taler Wire gateway HTTP API
 *        See https://docs.taler.net/core/api-wire.html
 * @author Christian Grothoff
 */
#ifndef _TALER_BANK_SERVICE_H
#define _TALER_BANK_SERVICE_H

#include <jansson.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_util.h"
#include "taler_error_codes.h"

/**
 * Version of the Bank API, in hex.
 * Thus 0.12.0-0 = 0x000C0000.
 */
#define TALER_BANK_SERVICE_API_VERSION 0x000C0000

/**
 * Authentication method types.
 */
enum TALER_BANK_AuthenticationMethod
{

  /**
   * No authentication.
   */
  TALER_BANK_AUTH_NONE,

  /**
   * Basic authentication with cleartext username and password.
   */
  TALER_BANK_AUTH_BASIC,

  /**
   * Bearer token authentication.
   */
  TALER_BANK_AUTH_BEARER,
};


/**
 * Information used to authenticate to the bank.
 */
struct TALER_BANK_AuthenticationData
{

  /**
   * Base URL we use to talk to the wire gateway,
   * which talks to the bank for us.
   */
  char *wire_gateway_url;

  /**
   * Which authentication method should we use?
   */
  enum TALER_BANK_AuthenticationMethod method;

  /**
   * Further details as per @e method.
   */
  union
  {

    /**
     * Details for #TALER_BANK_AUTH_BASIC.
     */
    struct
    {
      /**
       * Username to use.
       */
      char *username;

      /**
       * Password to use.
       */
      char *password;
    } basic;

    /**
     * Details for #TALER_BANK_AUTH_BEARER.
     */
    struct
    {
      /**
       * Token to use.
       */
      char *token;

    } bearer;

  } details;

};


/* ********************* /accounts/$ACC/token *********************** */


/**
 * @brief A /accounts/$USERNAME/token request handle
 */
struct TALER_BANK_AccountTokenHandle;


/**
 * Response details for a token request.
 */
struct TALER_BANK_AccountTokenResponse
{

  /**
   * HTTP status.
   */
  unsigned int http_status;

  /**
   * Taler error code, #TALER_EC_NONE on success.
   */
  enum TALER_ErrorCode ec;

  /**
   * Full response, NULL if body was not in JSON format.
   */
  const json_t *response;

  /**
   * Details returned depending on the @e http_status.
   */
  union
  {

    /**
     * Details if status was #MHD_HTTP_OK
     */
    struct
    {
      /**
       * Access token to use.
       */
      const char *access_token;

      /**
       * time when the token will expire.
       */
      struct GNUNET_TIME_Timestamp expiration;

    } ok;

  } details;

};

/**
 * Callbacks of this type are used to return the result of submitting
 * a request for an access token to the bank.
 *
 * @param cls closure
 * @param atr response details
 */
typedef void
(*TALER_BANK_AccountTokenCallback) (
  void *cls,
  const struct TALER_BANK_AccountTokenResponse *atr);


/**
 * Possible access scopes for bank bearer tokens.
 */
enum TALER_BANK_TokenScope
{

  /**
   * Only grant read-access to the account. Useful for
   * human auditors.
   */
  TALER_BANK_TOKEN_SCOPE_READONLY,

  /**
   * Grants full read-write access to the account. Useful
   * for the SPA. Strongly recommended to limit validity
   * duration.
   */
  TALER_BANK_TOKEN_SCOPE_READWRITE,

  /**
   * Only grant (read-access to) the revenue API. Useful for
   * merchant backends.
   */
  TALER_BANK_TOKEN_SCOPE_REVENUE,

  /**
   * Only grant access to the wire gateway API. Useful for
   * the exchange.
   */
  TALER_BANK_TOKEN_SCOPE_WIREGATEWAY

};


/**
 * Requests an access token from the bank. Note that this
 * request is against the CORE banking API and not done by
 * exchange code itself (but used to get access tokens when testing).
 *
 * @param ctx curl context for the event loop
 * @param auth authentication data to send to the bank
 * @param account_name username of the bank account to get a token for
 * @param scope requested token scope
 * @param refreshable true if the token should be refreshable
 * @param description human-readable token description (for token management)
 * @param duration requested token validity, use zero for default
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return NULL
 *         if the inputs are invalid (i.e. invalid amount) or internal errors.
 *         In this case, the callback is not called.
 */
struct TALER_BANK_AccountTokenHandle *
TALER_BANK_account_token (
  struct GNUNET_CURL_Context *ctx,
  const struct TALER_BANK_AuthenticationData *auth,
  const char *account_name,
  enum TALER_BANK_TokenScope scope,
  bool refreshable,
  const char *description,
  struct GNUNET_TIME_Relative duration,
  TALER_BANK_AccountTokenCallback res_cb,
  void *res_cb_cls);


/**
 * Cancel an add incoming operation.  This function cannot be used on a
 * request handle if a response is already served for it.
 *
 * @param[in] ath the admin add incoming request handle
 */
void
TALER_BANK_account_token_cancel (
  struct TALER_BANK_AccountTokenHandle *ath);


/* ********************* /admin/add-incoming *********************** */


/**
 * @brief A /admin/add-incoming Handle
 */
struct TALER_BANK_AdminAddIncomingHandle;


/**
 * Response details for a history request.
 */
struct TALER_BANK_AdminAddIncomingResponse
{

  /**
   * HTTP status.
   */
  unsigned int http_status;

  /**
   * Taler error code, #TALER_EC_NONE on success.
   */
  enum TALER_ErrorCode ec;

  /**
   * Full response, NULL if body was not in JSON format.
   */
  const json_t *response;

  /**
   * Details returned depending on the @e http_status.
   */
  union
  {

    /**
     * Details if status was #MHD_HTTP_OK
     */
    struct
    {
      /**
       * unique ID of the wire transfer in the bank's records
       */
      uint64_t serial_id;

      /**
       * time when the transaction was made.
       */
      struct GNUNET_TIME_Timestamp timestamp;

    } ok;

  } details;

};

/**
 * Callbacks of this type are used to return the result of submitting
 * a request to transfer funds to the exchange.
 *
 * @param cls closure
 * @param air response details
 */
typedef void
(*TALER_BANK_AdminAddIncomingCallback) (
  void *cls,
  const struct TALER_BANK_AdminAddIncomingResponse *air);


/**
 * Perform a wire transfer from some account to the exchange to fill a
 * reserve.  Note that this API is usually only used for testing (with
 * fakebank) and thus may not be accessible in a production setting.
 *
 * @param ctx curl context for the event loop
 * @param auth authentication data to send to the bank
 * @param reserve_pub wire transfer subject for the transfer
 * @param amount amount that is to be deposited
 * @param debit_account account to deposit from (payto URI, but used as 'payfrom')
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return NULL
 *         if the inputs are invalid (i.e. invalid amount) or internal errors.
 *         In this case, the callback is not called.
 */
struct TALER_BANK_AdminAddIncomingHandle *
TALER_BANK_admin_add_incoming (
  struct GNUNET_CURL_Context *ctx,
  const struct TALER_BANK_AuthenticationData *auth,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_Amount *amount,
  const struct TALER_FullPayto debit_account,
  TALER_BANK_AdminAddIncomingCallback res_cb,
  void *res_cb_cls);


/**
 * Cancel an add incoming operation.  This function cannot be used on a
 * request handle if a response is already served for it.
 *
 * @param[in] aai the admin add incoming request handle
 */
void
TALER_BANK_admin_add_incoming_cancel (
  struct TALER_BANK_AdminAddIncomingHandle *aai);


/**
 * @brief A /admin/add-kycauth Handle
 */
struct TALER_BANK_AdminAddKycauthHandle;


/**
 * Response details for a history request.
 */
struct TALER_BANK_AdminAddKycauthResponse
{

  /**
   * HTTP status.
   */
  unsigned int http_status;

  /**
   * Taler error code, #TALER_EC_NONE on success.
   */
  enum TALER_ErrorCode ec;

  /**
   * Full response, NULL if body was not in JSON format.
   */
  const json_t *response;

  /**
   * Details returned depending on the @e http_status.
   */
  union
  {

    /**
     * Details if status was #MHD_HTTP_OK
     */
    struct
    {
      /**
       * unique ID of the wire transfer in the bank's records
       */
      uint64_t serial_id;

      /**
       * time when the transaction was made.
       */
      struct GNUNET_TIME_Timestamp timestamp;

    } ok;

  } details;

};

/**
 * Callbacks of this type are used to return the result of submitting
 * a request to transfer funds to the exchange.
 *
 * @param cls closure
 * @param air response details
 */
typedef void
(*TALER_BANK_AdminAddKycauthCallback) (
  void *cls,
  const struct TALER_BANK_AdminAddKycauthResponse *air);


/**
 * Perform a wire transfer from some account to the exchange to register a
 * public key for KYC authentication of the origin account.  Note that this
 * API is usually only used for testing (with fakebank) and thus may not be
 * accessible in a production setting.
 *
 * @param ctx curl context for the event loop
 * @param auth authentication data to send to the bank
 * @param account_pub wire transfer subject for the transfer
 * @param amount amount that is to be deposited
 * @param debit_account account to deposit from (payto URI, but used as 'payfrom')
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return NULL
 *         if the inputs are invalid (i.e. invalid amount) or internal errors.
 *         In this case, the callback is not called.
 */
struct TALER_BANK_AdminAddKycauthHandle *
TALER_BANK_admin_add_kycauth (
  struct GNUNET_CURL_Context *ctx,
  const struct TALER_BANK_AuthenticationData *auth,
  const union TALER_AccountPublicKeyP *account_pub,
  const struct TALER_Amount *amount,
  const struct TALER_FullPayto debit_account,
  TALER_BANK_AdminAddKycauthCallback res_cb,
  void *res_cb_cls);


/**
 * Cancel an add kycauth operation.  This function cannot be used on a
 * request handle if a response is already served for it.
 *
 * @param[in] aai the admin add kycauth request handle
 */
void
TALER_BANK_admin_add_kycauth_cancel (
  struct TALER_BANK_AdminAddKycauthHandle *aai);


/* ********************* /transfer *********************** */

/**
 * Prepare for execution of a wire transfer from the exchange to some
 * merchant.
 *
 * @param destination_account_payto_uri payto:// URL identifying where to send the money
 * @param amount amount to transfer, already rounded
 * @param exchange_base_url base URL of this exchange (included in subject
 *        to facilitate use of tracking API by merchant backend)
 * @param wtid wire transfer identifier to use
 * @param[out] buf set to transaction data to persist, NULL on error
 * @param[out] buf_size set to number of bytes in @a buf, 0 on error
 */
void
TALER_BANK_prepare_transfer (
  const struct TALER_FullPayto destination_account_payto_uri,
  const struct TALER_Amount *amount,
  const char *exchange_base_url,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  void **buf,
  size_t *buf_size);


/**
 * Handle for active wire transfer.
 */
struct TALER_BANK_TransferHandle;


/**
 * Response details for a history request.
 */
struct TALER_BANK_TransferResponse
{

  /**
   * HTTP status.
   */
  unsigned int http_status;

  /**
   * Taler error code, #TALER_EC_NONE on success.
   */
  enum TALER_ErrorCode ec;

  /**
   * Full response, NULL if body was not in JSON format.
   */
  const json_t *response;

  /**
   * Details returned depending on the @e http_status.
   */
  union
  {

    /**
     * Details if status was #MHD_HTTP_OK
     */
    struct
    {


      /**
       * unique ID of the wire transfer in the bank's records
       */
      uint64_t row_id;

      /**
       * when did the transaction go into effect
       */
      struct GNUNET_TIME_Timestamp timestamp;

    } ok;
  } details;
};


/**
 * Function called with the result from the execute step.
 *
 * @param cls closure
 * @param tr response details
 */
typedef void
(*TALER_BANK_TransferCallback)(
  void *cls,
  const struct TALER_BANK_TransferResponse *tr);


/**
 * Execute a wire transfer from the exchange to some merchant.
 *
 * @param ctx context for HTTP interaction
 * @param auth authentication data to authenticate with the bank
 * @param buf buffer with the prepared execution details
 * @param buf_size number of bytes in @a buf
 * @param cc function to call upon success
 * @param cc_cls closure for @a cc
 * @return NULL on error
 */
struct TALER_BANK_TransferHandle *
TALER_BANK_transfer (
  struct GNUNET_CURL_Context *ctx,
  const struct TALER_BANK_AuthenticationData *auth,
  const void *buf,
  size_t buf_size,
  TALER_BANK_TransferCallback cc,
  void *cc_cls);


/**
 * Abort execution of a wire transfer. For example, because we are shutting
 * down.  Note that if an execution is aborted, it may or may not still
 * succeed.
 *
 * The caller MUST run #TALER_BANK_transfer() again for the same request as
 * soon as possible, to ensure that the request either ultimately succeeds or
 * ultimately fails. Until this has been done, the transaction is in limbo
 * (i.e. may or may not have been committed).
 *
 * This function cannot be used on a request handle if a response is already
 * served for it.
 *
 * @param[in] th handle of the wire transfer request to cancel
 */
void
TALER_BANK_transfer_cancel (
  struct TALER_BANK_TransferHandle *th);


/* ********************* /history/incoming *********************** */

/**
 * Different types of wire transfers that might be
 * credited to an exchange account.
 */
enum TALER_BANK_CreditType
{
  /**
   * Common wire transfer into a reserve account.
   */
  TALER_BANK_CT_RESERVE,

  /**
   * KYC authentication wire transfer with an account
   * public key.
   */
  TALER_BANK_CT_KYCAUTH,

  /**
   * WAD transfer between exchanges.
   */
  TALER_BANK_CT_WAD

};

/**
 * Handle for querying the bank for transactions
 * made to the exchange.
 */
struct TALER_BANK_CreditHistoryHandle;

/**
 * Details about a wire transfer to the exchange.
 */
struct TALER_BANK_CreditDetails
{

  /**
   * Type of the wire transfer.
   */
  enum TALER_BANK_CreditType type;

  /**
   * Serial ID of the wire transfer.
   */
  uint64_t serial_id;

  /**
   * Amount that was transferred
   */
  struct TALER_Amount amount;

  /**
   * Fee paid by the creditor.
   */
  struct TALER_Amount credit_fee;

  /**
   * Time of the the transfer
   */
  struct GNUNET_TIME_Timestamp execution_date;

  /**
   * payto://-URL of the source account that send the funds.
   */
  struct TALER_FullPayto debit_account_uri;

  /**
   * Details that depend on the @e type.
   */
  union
  {

    /**
     * Details for @e type #TALER_BANK_CT_RESERVE.
     */
    struct
    {

      /**
       * Reserve public key encoded in the wire transfer subject.
       */
      struct TALER_ReservePublicKeyP reserve_pub;

    } reserve;

    /**
     * Details for @e type #TALER_BANK_CT_KYCAUTH.
     */
    struct
    {

      /**
       * Public key to associate with the owner of the
       * origin bank account.
       */
      union TALER_AccountPublicKeyP account_pub;

    } kycauth;

    /**
     * Details for @e type #TALER_BANK_CT_WAD.
     */
    struct
    {

      /**
       * WAD identifier for the transfer.
       */
      struct TALER_WadIdentifierP wad_id;

      /**
       * Base URL of the exchange originating the transfer.
       */
      const char *origin_exchange_url;
    } wad;

  } details;

};


/**
 * Response details for a history request.
 */
struct TALER_BANK_CreditHistoryResponse
{

  /**
   * HTTP status.  Note that #MHD_HTTP_OK and #MHD_HTTP_NO_CONTENT are both
   * successful replies, but @e details will only contain @e success information
   * if this is set to #MHD_HTTP_OK.
   */
  unsigned int http_status;

  /**
   * Taler error code, #TALER_EC_NONE on success.
   */
  enum TALER_ErrorCode ec;

  /**
   * Full response, NULL if body was not in JSON format.
   */
  const json_t *response;

  /**
   * Details returned depending on the @e http_status.
   */
  union
  {

    /**
     * Details if status was #MHD_HTTP_OK
     */
    struct
    {

      /**
       * payto://-URL of the target account that received the funds.
       */
      struct TALER_FullPayto credit_account_uri;

      /**
       * Array of transactions received.
       */
      const struct TALER_BANK_CreditDetails *details;

      /**
       * Length of the @e details array.
       */
      unsigned int details_length;

    } ok;

  } details;

};


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank for the credit transaction history.
 *
 * @param cls closure
 * @param reply details about the response
 */
typedef void
(*TALER_BANK_CreditHistoryCallback)(
  void *cls,
  const struct TALER_BANK_CreditHistoryResponse *reply);


/**
 * Request the wire credit history of an exchange's bank account.
 *
 * @param ctx curl context for the event loop
 * @param auth authentication data to use
 * @param start_row from which row on do we want to get results, use UINT64_MAX for the latest; exclusive
 * @param num_results how many results do we want; negative numbers to go into the past,
 *                    positive numbers to go into the future starting at @a start_row;
 *                    must not be zero.
 * @param timeout how long the client is willing to wait for more results
 *                (only useful if @a num_results is positive)
 * @param hres_cb the callback to call with the transaction history
 * @param hres_cb_cls closure for the above callback
 * @return NULL
 *         if the inputs are invalid (i.e. zero value for @e num_results).
 *         In this case, the callback is not called.
 */
struct TALER_BANK_CreditHistoryHandle *
TALER_BANK_credit_history (
  struct GNUNET_CURL_Context *ctx,
  const struct TALER_BANK_AuthenticationData *auth,
  uint64_t start_row,
  int64_t num_results,
  struct GNUNET_TIME_Relative timeout,
  TALER_BANK_CreditHistoryCallback hres_cb,
  void *hres_cb_cls);


/**
 * Cancel an history request.  This function cannot be used on a request
 * handle if the last response (anything with a status code other than
 * 200) is already served for it.
 *
 * @param[in] hh the history request handle
 */
void
TALER_BANK_credit_history_cancel (
  struct TALER_BANK_CreditHistoryHandle *hh);


/* ********************* /history/outgoing *********************** */

/**
 * Handle for querying the bank for transactions
 * made from the exchange to merchants.
 */
struct TALER_BANK_DebitHistoryHandle;

/**
 * Details about a wire transfer made by the exchange
 * to a merchant.
 */
struct TALER_BANK_DebitDetails
{
  /**
   * Serial ID of the wire transfer.
   */
  uint64_t serial_id;

  /**
   * Amount that was transferred
   */
  struct TALER_Amount amount;

  /**
   * Time of the the transfer
   */
  struct GNUNET_TIME_Timestamp execution_date;

  /**
   * Wire transfer identifier used by the exchange.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * Exchange's base URL as given in the wire transfer.
   */
  const char *exchange_base_url;

  /**
   * payto://-URI of the target account that received the funds.
   */
  struct TALER_FullPayto credit_account_uri;

};


/**
 * Response details for a history request.
 */
struct TALER_BANK_DebitHistoryResponse
{

  /**
   * HTTP status.  Note that #MHD_HTTP_OK and #MHD_HTTP_NO_CONTENT are both
   * successful replies, but @e details will only contain @e success information
   * if this is set to #MHD_HTTP_OK.
   */
  unsigned int http_status;

  /**
   * Taler error code, #TALER_EC_NONE on success.
   */
  enum TALER_ErrorCode ec;

  /**
   * Full response, NULL if body was not in JSON format.
   */
  const json_t *response;

  /**
   * Details returned depending on the @e http_status.
   */
  union
  {

    /**
     * Details if status was #MHD_HTTP_OK
     */
    struct
    {

      /**
       * payto://-URI of the source account that send the funds.
       */
      struct TALER_FullPayto debit_account_uri;

      /**
       * Array of transactions initiated.
       */
      const struct TALER_BANK_DebitDetails *details;

      /**
       * Length of the @e details array.
       */
      unsigned int details_length;

    } ok;

  } details;

};


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank for the debit transaction history.
 *
 * @param cls closure
 * @param reply details about the response
 */
typedef void
(*TALER_BANK_DebitHistoryCallback)(
  void *cls,
  const struct TALER_BANK_DebitHistoryResponse *reply);


/**
 * Request the wire credit history of an exchange's bank account.
 *
 * @param ctx curl context for the event loop
 * @param auth authentication data to use
 * @param start_row from which row on do we want to get results, use UINT64_MAX for the latest; exclusive
 * @param num_results how many results do we want; negative numbers to go into the past,
 *                    positive numbers to go into the future starting at @a start_row;
 *                    must not be zero.
 * @param timeout how long the client is willing to wait for more results
 *                (only useful if @a num_results is positive)
 * @param hres_cb the callback to call with the transaction history
 * @param hres_cb_cls closure for the above callback
 * @return NULL
 *         if the inputs are invalid (i.e. zero value for @e num_results).
 *         In this case, the callback is not called.
 */
struct TALER_BANK_DebitHistoryHandle *
TALER_BANK_debit_history (
  struct GNUNET_CURL_Context *ctx,
  const struct TALER_BANK_AuthenticationData *auth,
  uint64_t start_row,
  int64_t num_results,
  struct GNUNET_TIME_Relative timeout,
  TALER_BANK_DebitHistoryCallback hres_cb,
  void *hres_cb_cls);


/**
 * Cancel an history request.  This function cannot be used on a request
 * handle if the last response (anything with a status code other than
 * 200) is already served for it.
 *
 * @param[in] hh the history request handle
 */
void
TALER_BANK_debit_history_cancel (
  struct TALER_BANK_DebitHistoryHandle *hh);


/* ******************** Convenience functions **************** */


/**
 * Convenience method for parsing configuration section with bank
 * authentication data.
 *
 * @param cfg configuration to parse
 * @param section the section with the configuration data
 * @param[out] auth set to the configuration data found
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_BANK_auth_parse_cfg (
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  const char *section,
  struct TALER_BANK_AuthenticationData *auth);


/**
 * Free memory inside of @a auth (but not @a auth itself).
 * Dual to #TALER_BANK_auth_parse_cfg().
 *
 * @param[in,out] auth authentication data to free
 */
void
TALER_BANK_auth_free (
  struct TALER_BANK_AuthenticationData *auth);


#endif  /* _TALER_BANK_SERVICE_H */
