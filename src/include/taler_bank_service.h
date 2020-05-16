/*
  This file is part of TALER
  Copyright (C) 2015-2020 Taler Systems SA

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

  } details;

};


/* ********************* /admin/add-incoming *********************** */


/**
 * @brief A /admin/add-incoming Handle
 */
struct TALER_BANK_AdminAddIncomingHandle;


/**
 * Callbacks of this type are used to return the result of submitting
 * a request to transfer funds to the exchange.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the bank's reply is bogus (fails to follow the protocol)
 * @param ec detailed error code
 * @param serial_id unique ID of the wire transfer in the bank's records; UINT64_MAX on error
 * @param timestamp time when the transaction was made.
 * @param json detailed response from the HTTPD, or NULL if reply was not in JSON
 */
typedef void
(*TALER_BANK_AdminAddIncomingCallback) (void *cls,
                                        unsigned int http_status,
                                        enum TALER_ErrorCode ec,
                                        uint64_t serial_id,
                                        struct GNUNET_TIME_Absolute timestamp,
                                        const json_t *json);


/**
 * Perform a wire transfer from some account to the exchange to fill a
 * reserve.  Note that this API is usually only used for testing (with
 * fakebank and our Python bank) and thus may not be accessible in a
 * production setting.
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
  const char *debit_account,
  TALER_BANK_AdminAddIncomingCallback res_cb,
  void *res_cb_cls);


/**
 * Cancel an add incoming operation.  This function cannot be used on a
 * request handle if a response is already served for it.
 *
 * @param aai the admin add incoming request handle
 */
void
TALER_BANK_admin_add_incoming_cancel (
  struct TALER_BANK_AdminAddIncomingHandle *aai);


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
  const char *destination_account_payto_uri,
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
 * Function called with the result from the execute step.
 *
 * @param cls closure
 * @param response_code HTTP status code
 * @param ec taler error code
 * @param row_id unique ID of the wire transfer in the bank's records
 * @param timestamp when did the transaction go into effect
 */
typedef void
(*TALER_BANK_TransferCallback)(void *cls,
                               unsigned int response_code,
                               enum TALER_ErrorCode ec,
                               uint64_t row_id,
                               struct GNUNET_TIME_Absolute timestamp);


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
TALER_BANK_transfer (struct GNUNET_CURL_Context *ctx,
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
 * @param th handle of the wire transfer request to cancel
 */
void
TALER_BANK_transfer_cancel (struct TALER_BANK_TransferHandle *th);


/* ********************* /history/incoming *********************** */

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
   * Amount that was transferred
   */
  struct TALER_Amount amount;

  /**
   * Time of the the transfer
   */
  struct GNUNET_TIME_Absolute execution_date;

  /**
   * Reserve public key encoded in the wire
   * transfer subject.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * payto://-URL of the source account that
   * send the funds.
   */
  const char *debit_account_url;

  /**
   * payto://-URL of the target account that
   * received the funds.
   */
  const char *credit_account_url;
};


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank for the credit transaction history.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the bank's reply is bogus (fails to follow the protocol),
 *                    #MHD_HTTP_NO_CONTENT if there are no more results; on success the
 *                    last callback is always of this status (even if `abs(num_results)` were
 *                    already returned).
 * @param ec detailed error code
 * @param serial_id monotonically increasing counter corresponding to the transaction
 * @param details details about the wire transfer
 * @param json detailed response from the HTTPD, or NULL if reply was not in JSON
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to abort iteration
 */
typedef int
(*TALER_BANK_CreditHistoryCallback) (
  void *cls,
  unsigned int http_status,
  enum TALER_ErrorCode ec,
  uint64_t serial_id,
  const struct TALER_BANK_CreditDetails *details,
  const json_t *json);


/**
 * Request the wire credit history of an exchange's bank account.
 *
 * @param ctx curl context for the event loop
 * @param auth authentication data to use
 * @param start_row from which row on do we want to get results, use UINT64_MAX for the latest; exclusive
 * @param num_results how many results do we want; negative numbers to go into the past,
 *                    positive numbers to go into the future starting at @a start_row;
 *                    must not be zero.
 * @param hres_cb the callback to call with the transaction history
 * @param hres_cb_cls closure for the above callback
 * @return NULL
 *         if the inputs are invalid (i.e. zero value for @e num_results).
 *         In this case, the callback is not called.
 */
struct TALER_BANK_CreditHistoryHandle *
TALER_BANK_credit_history (struct GNUNET_CURL_Context *ctx,
                           const struct TALER_BANK_AuthenticationData *auth,
                           uint64_t start_row,
                           int64_t num_results,
                           TALER_BANK_CreditHistoryCallback hres_cb,
                           void *hres_cb_cls);


/**
 * Cancel an history request.  This function cannot be used on a request
 * handle if the last response (anything with a status code other than
 * 200) is already served for it.
 *
 * @param hh the history request handle
 */
void
TALER_BANK_credit_history_cancel (struct TALER_BANK_CreditHistoryHandle *hh);


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
   * Amount that was transferred
   */
  struct TALER_Amount amount;

  /**
   * Time of the the transfer
   */
  struct GNUNET_TIME_Absolute execution_date;

  /**
   * Wire transfer identifier used by the exchange.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * Exchange's base URL as given in the wire transfer.
   */
  const char *exchange_base_url;

  /**
   * payto://-URI of the source account that
   * send the funds.
   */
  const char *debit_account_url; // FIXME: rename: url->uri

  /**
   * payto://-URI of the target account that
   * received the funds.
   */
  const char *credit_account_url; // FIXME: rename: url->uri

};


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank for the debit transaction history.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the bank's reply is bogus (fails to follow the protocol),
 *                    #MHD_HTTP_NO_CONTENT if there are no more results; on success the
 *                    last callback is always of this status (even if `abs(num_results)` were
 *                    already returned).
 * @param ec detailed error code
 * @param serial_id monotonically increasing counter corresponding to the transaction
 * @param details details about the wire transfer
 * @param json detailed response from the HTTPD, or NULL if reply was not in JSON
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to abort iteration
 */
typedef int
(*TALER_BANK_DebitHistoryCallback) (
  void *cls,
  unsigned int http_status,
  enum TALER_ErrorCode ec,
  uint64_t serial_id,
  const struct TALER_BANK_DebitDetails *details,
  const json_t *json);


/**
 * Request the wire credit history of an exchange's bank account.
 *
 * @param ctx curl context for the event loop
 * @param auth authentication data to use
 * @param start_row from which row on do we want to get results, use UINT64_MAX for the latest; exclusive
 * @param num_results how many results do we want; negative numbers to go into the past,
 *                    positive numbers to go into the future starting at @a start_row;
 *                    must not be zero.
 * @param hres_cb the callback to call with the transaction history
 * @param hres_cb_cls closure for the above callback
 * @return NULL
 *         if the inputs are invalid (i.e. zero value for @e num_results).
 *         In this case, the callback is not called.
 */
struct TALER_BANK_DebitHistoryHandle *
TALER_BANK_debit_history (struct GNUNET_CURL_Context *ctx,
                          const struct TALER_BANK_AuthenticationData *auth,
                          uint64_t start_row,
                          int64_t num_results,
                          TALER_BANK_DebitHistoryCallback hres_cb,
                          void *hres_cb_cls);


/**
 * Cancel an history request.  This function cannot be used on a request
 * handle if the last response (anything with a status code other than
 * 200) is already served for it.
 *
 * @param hh the history request handle
 */
void
TALER_BANK_debit_history_cancel (struct TALER_BANK_DebitHistoryHandle *hh);


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
int
TALER_BANK_auth_parse_cfg (const struct GNUNET_CONFIGURATION_Handle *cfg,
                           const char *section,
                           struct TALER_BANK_AuthenticationData *auth);


/**
 * Free memory inside of @a auth (but not @a auth itself).
 * Dual to #TALER_BANK_auth_parse_cfg().
 *
 * @param auth authentication data to free
 */
void
TALER_BANK_auth_free (struct TALER_BANK_AuthenticationData *auth);


#endif  /* _TALER_BANK_SERVICE_H */
