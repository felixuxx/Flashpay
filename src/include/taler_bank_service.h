/*
  This file is part of TALER
  Copyright (C) 2015, 2016, 2017 Taler Systems SA

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
 * @brief C interface of libtalerbank, a C library to use the Taler bank's HTTP API
 *        This is currently ONLY used to provide the "test" wire transfer protocol.
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
  TALER_BANK_AUTH_BASIC
};


/**
 * Information used to authenticate to the bank.
 */
struct TALER_BANK_AuthenticationData
{

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


/* ********************* /admin/add/incoming *********************** */


/**
 * @brief A /admin/add/incoming Handle
 */
struct TALER_BANK_AdminAddIncomingHandle;


/**
 * Callbacks of this type are used to serve the result of submitting
 * information about an incoming transaction to a bank.
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
(*TALER_BANK_AdminAddIncomingResultCallback) (void *cls,
                                              unsigned int http_status,
                                              enum TALER_ErrorCode ec,
                                              uint64_t serial_id,
                                              struct GNUNET_TIME_Absolute
                                              timestamp,
                                              const json_t *json);


/**
 * Notify the bank that we have received an incoming transaction
 * which fills a reserve.  Note that this API is an administrative
 * API and thus not accessible to typical bank clients, but only
 * to the operators of the bank.
 *
 * @param ctx curl context for the event loop
 * @param bank_base_url URL of the bank (used to execute this request)
 * @param auth authentication data to use
 * @param exchange_base_url base URL of the exchange (for tracking)
 * @param subject wire transfer subject for the transfer
 * @param amount amount that was deposited
 * @param debit_account_no account number to withdraw from (53 bits at most)
 * @param credit_account_no account number to deposit into (53 bits at most)
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return NULL
 *         if the inputs are invalid (i.e. invalid amount).
 *         In this case, the callback is not called.
 */
struct TALER_BANK_AdminAddIncomingHandle *
TALER_BANK_admin_add_incoming (struct GNUNET_CURL_Context *ctx,
                               const char *bank_base_url,
                               const struct TALER_BANK_AuthenticationData *auth,
                               const char *exchange_base_url,
                               const char *subject,
                               const struct TALER_Amount *amount,
                               uint64_t debit_account_no,
                               uint64_t credit_account_no,
                               TALER_BANK_AdminAddIncomingResultCallback res_cb,
                               void *res_cb_cls);


/**
 * Cancel an add incoming.  This function cannot be used on a request
 * handle if a response is already served for it.
 *
 * @param aai the admin add incoming request handle
 */
void
TALER_BANK_admin_add_incoming_cancel (struct
                                      TALER_BANK_AdminAddIncomingHandle *aai);


/**
 * Which types of transactions should be (or is being) returned?
 */
enum TALER_BANK_Direction
{

  /**
   * Base case, used to indicate errors or end of list.
   */
  TALER_BANK_DIRECTION_NONE = 0,

  /**
   * Transactions where the bank account receives money.
   */
  TALER_BANK_DIRECTION_CREDIT = 1,

  /**
   * Transactions where the bank account looses money.
   */
  TALER_BANK_DIRECTION_DEBIT = 2,

  /**
   * Return both types of transactions.
   */
  TALER_BANK_DIRECTION_BOTH = (TALER_BANK_DIRECTION_CREDIT
                               | TALER_BANK_DIRECTION_DEBIT),

  /**
   * Bit mask that is applied to view transactions that have been
   * cancelled. The bit is set for cancelled transactions that are
   * returned from /history, and must also be set in order for
   * cancelled transactions to show up in the /history.
   */
  TALER_BANK_DIRECTION_CANCEL = 4

};


/**
 * Handle for querying the bank's transaction history.
 */
struct TALER_BANK_HistoryHandle;

/**
 * Details about a wire transfer.
 */
struct TALER_BANK_TransferDetails
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
   * Wire transfer subject.  Usually a reserve public key
   * followed by the base URL of the exchange.
   */
  char *wire_transfer_subject;

  /**
   * payto://-URL of the other account that was involved
   */
  char *account_url;
};


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank for the transaction history.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the bank's reply is bogus (fails to follow the protocol),
 *                    #MHD_HTTP_NO_CONTENT if there are no more results; on success the
 *                    last callback is always of this status (even if `abs(num_results)` were
 *                    already returned).
 * @param ec detailed error code
 * @param dir direction of the transfer
 * @param serial_id monotonically increasing counter corresponding to the transaction
 * @param details details about the wire transfer
 * @param json detailed response from the HTTPD, or NULL if reply was not in JSON
 */
typedef void
(*TALER_BANK_HistoryResultCallback) (void *cls,
                                     unsigned int http_status,
                                     enum TALER_ErrorCode ec,
                                     enum TALER_BANK_Direction dir,
                                     uint64_t serial_id,
                                     const struct
                                     TALER_BANK_TransferDetails *details,
                                     const json_t *json);


/**
 * Request the wire transfer history of a bank account.
 *
 * @param ctx curl context for the event loop
 * @param bank_base_url URL of the bank (used to execute this request)
 * @param auth authentication data to use
 * @param account_number which account number should we query
 * @param direction what kinds of wire transfers should be returned
 * @param ascending if GNUNET_YES, history elements will be returned in chronological order.
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
struct TALER_BANK_HistoryHandle *
TALER_BANK_history (struct GNUNET_CURL_Context *ctx,
                    const char *bank_base_url,
                    const struct TALER_BANK_AuthenticationData *auth,
                    uint64_t account_number,
                    enum TALER_BANK_Direction direction,
                    unsigned int ascending,
                    uint64_t start_row,
                    int64_t num_results,
                    TALER_BANK_HistoryResultCallback hres_cb,
                    void *hres_cb_cls);


/**
 * Request the wire transfer history of a bank account,
 * using time stamps to narrow the results.
 *
 * @param ctx curl context for the event loop
 * @param bank_base_url URL of the bank (used to execute this
 *        request)
 * @param auth authentication data to use
 * @param account_number which account number should we query
 * @param direction what kinds of wire transfers should be
 *        returned
 * @param ascending if GNUNET_YES, history elements will
 *        be returned in chronological order.
 * @param start_date threshold for oldest result.
 * @param end_date threshold for youngest result.
 * @param hres_cb the callback to call with the transaction
 *        history
 * @param hres_cb_cls closure for the above callback
 * @return NULL if the inputs are invalid (i.e. zero value for
 *         @e num_results). In this case, the callback is not
 *         called.
 */
struct TALER_BANK_HistoryHandle *
TALER_BANK_history_range (struct GNUNET_CURL_Context *ctx,
                          const char *bank_base_url,
                          const struct TALER_BANK_AuthenticationData *auth,
                          uint64_t account_number,
                          enum TALER_BANK_Direction direction,
                          unsigned int ascending,
                          struct GNUNET_TIME_Absolute start_date,
                          struct GNUNET_TIME_Absolute end_date,
                          TALER_BANK_HistoryResultCallback hres_cb,
                          void *hres_cb_cls);


/**
 * Cancel an history request.  This function cannot be used on a request
 * handle if the last response (anything with a status code other than
 * 200) is already served for it.
 *
 * @param hh the history request handle
 */
void
TALER_BANK_history_cancel (struct TALER_BANK_HistoryHandle *hh);


/**
 * Handle for #TALER_BANK_reject() operation.
 */
struct TALER_BANK_RejectHandle;


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank to reject an incoming wire transfer.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_NO_CONTENT (204) for successful status request;
 *                    #MHD_HTTP_NOT_FOUND if the rowid is unknown;
 *                    0 if the bank's reply is bogus (fails to follow the protocol),
 * @param ec detailed error code
 */
typedef void
(*TALER_BANK_RejectResultCallback) (void *cls,
                                    unsigned int http_status,
                                    enum TALER_ErrorCode ec);


/**
 * Request rejection of a wire transfer, marking it as cancelled and voiding
 * its effects.
 *
 * @param ctx curl context for the event loop
 * @param bank_base_url URL of the bank (used to execute this request)
 * @param auth authentication data to use
 * @param account_number which account number should we query
 * @param rowid transfer to reject
 * @param rcb the callback to call with the operation result
 * @param rcb_cls closure for @a rcb
 * @return NULL
 *         if the inputs are invalid.
 *         In this case, the callback is not called.
 */
struct TALER_BANK_RejectHandle *
TALER_BANK_reject (struct GNUNET_CURL_Context *ctx,
                   const char *bank_base_url,
                   const struct TALER_BANK_AuthenticationData *auth,
                   uint64_t account_number,
                   uint64_t rowid,
                   TALER_BANK_RejectResultCallback rcb,
                   void *rcb_cls);


/**
 * Cancel an reject request.  This function cannot be used on a request
 * handle if the response was is already served for it.
 *
 * @param rh the reject request handle
 */
void
TALER_BANK_reject_cancel (struct TALER_BANK_RejectHandle *rh);


/**
 * Convenience method for parsing configuration section with bank
 * authentication data.  The section must contain an option
 * "METHOD", plus other options that depend on the METHOD specified.
 *
 * @param cfg configuration to parse
 * @param section the section with the configuration data
 * @param auth[out] set to the configuration data found
 * @return #GNUNET_OK on success
 */
int
TALER_BANK_auth_parse_cfg (const struct GNUNET_CONFIGURATION_Handle *cfg,
                           const char *section,
                           struct TALER_BANK_AuthenticationData *auth);


/**
 * Free memory inside of @a auth (but not auth itself).
 * Dual to #TALER_BANK_auth_parse_cfg().
 *
 * @param auth authentication data to free
 */
void
TALER_BANK_auth_free (struct TALER_BANK_AuthenticationData *auth);

#endif  /* _TALER_BANK_SERVICE_H */
