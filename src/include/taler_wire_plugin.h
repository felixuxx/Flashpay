/*
  This file is part of TALER
  Copyright (C) 2016, 2017 GNUnet e.V. & Inria

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
 * @file include/taler_wire_plugin.h
 * @brief Plugin API for the handling of wire transactions
 * @author Christian Grothoff
 */
#ifndef TALER_WIRE_PLUGIN_H
#define TALER_WIRE_PLUGIN_H

#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_util.h"
#include "taler_error_codes.h"
#include "taler_bank_service.h" /* for `enum TALER_BANK_Direction` and `struct TALER_BANK_TransferDetails` */


/**
 * Callback with prepared transaction.
 *
 * @param cls closure
 * @param buf transaction data to persist, NULL on error
 * @param buf_size number of bytes in @a buf, 0 on error
 */
typedef void
(*TALER_WIRE_PrepareTransactionCallback) (void *cls,
                                          const char *buf,
                                          size_t buf_size);


/**
 * Details about a valid wire transfer to the exchange.
 * It is the plugin's responsibility to filter and undo
 * invalid transfers.
 */
struct TALER_WIRE_TransferDetails
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
   * Binary data that was encoded in the wire transfer subject, if
   * it decoded properly.  Otherwise all-zeros and @e wtid_s is set.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * Wire transfer identifer as a string.  Set to NULL if the
   * identifier was properly Base32 encoded and this @e wtid could be
   * set instead.
   */
  char *wtid_s;

  /**
   * The other account that was involved
   */
  json_t *account_details;
};


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank for the transaction history.
 *
 * @param cls closure
 * @param ec taler error code
 * @param dir direction of the transfer
 * @param row_off identification of the position at which we are querying
 * @param row_off_size number of bytes in @a row_off
 * @param details details about the wire transfer
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to abort iteration
 */
typedef int
(*TALER_WIRE_HistoryResultCallback) (void *cls,
                                     enum TALER_ErrorCode ec,
                                     enum TALER_BANK_Direction dir,
                                     const void *row_off,
                                     size_t row_off_size,
                                     const struct TALER_WIRE_TransferDetails *details);


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank to reject a wire transfer.
 *
 * @param cls closure
 * @param ec status of the operation, #TALER_EC_NONE on success
 */
typedef void
(*TALER_WIRE_RejectTransferCallback) (void *cls,
                                      enum TALER_ErrorCode ec);


/**
 * Handle returned for cancelling a preparation step.
 */
struct TALER_WIRE_PrepareHandle;

/**
 * Handle returned for cancelling an execution step.
 */
struct TALER_WIRE_ExecuteHandle;

/**
 * Handle returned for querying the transaction history.
 */
struct TALER_WIRE_HistoryHandle;


/**
 * Function called with the result from the execute step.
 *
 * @param cls closure
 * @param success #GNUNET_OK on success, #GNUNET_SYSERR on failure
 * @param serial_id unique ID of the wire transfer in the bank's records; UINT64_MAX on error
 * @param emsg NULL on success, otherwise an error message
 */
typedef void
(*TALER_WIRE_ConfirmationCallback)(void *cls,
                                   int success,
                                   uint64_t serial_id,
                                   const char *emsg);


/**
 * @brief The plugin API, returned from the plugin's "init" function.
 * The argument given to "init" is simply a configuration handle.
 */
struct TALER_WIRE_Plugin
{

  /**
   * Closure for all callbacks.
   */
  void *cls;

  /**
   * Name of the library which generated this plugin.  Set by the
   * plugin loader.
   */
  char *library_name;

  /**
   * Round amount DOWN to the amount that can be transferred via the wire
   * method.  For example, Taler may support 0.000001 EUR as a unit of
   * payment, but SEPA only supports 0.01 EUR.  This function would
   * round 0.125 EUR to 0.12 EUR in this case.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param[in,out] amount amount to round down
   * @return #GNUNET_OK on success, #GNUNET_NO if rounding was unnecessary,
   *         #GNUNET_SYSERR if the amount or currency was invalid
   */
  int
  (*amount_round) (void *cls,
                   struct TALER_Amount *amount);


  /**
   * Obtain wire transfer details in the plugin-specific format
   * from the configuration.
   *
   * @param cls closure
   * @param cfg configuration with details about wire accounts
   * @param account_name which section in the configuration should we parse
   * @return NULL if @a cfg fails to have valid wire details for @a account_name
   */
  json_t *
  (*get_wire_details)(void *cls,
                      const struct GNUNET_CONFIGURATION_Handle *cfg,
                      const char *account_name);


  /**
   * Sign wire transfer details in the plugin-specific format.
   *
   * @param cls closure
   * @param in wire transfer details in JSON format
   * @param key private signing key to use
   * @param salt salt to add
   * @param[out] sig where to write the signature
   * @return #GNUNET_OK on success
   */
  int
  (*sign_wire_details)(void *cls,
                       const json_t *in,
                       const struct TALER_MasterPrivateKeyP *key,
                       const struct GNUNET_HashCode *salt,
                       struct TALER_MasterSignatureP *sig);


  /**
   * Check if the given wire format JSON object is correctly formatted
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param wire the JSON wire format object
   * @param master_pub public key of the exchange to verify against
   * @param[out] emsg set to an error message, unless we return #TALER_EC_NONE;
   *             error message must be freed by the caller using GNUNET_free()
   * @return #TALER_EC_NONE if correctly formatted
   */
  enum TALER_ErrorCode
  (*wire_validate) (void *cls,
                    const json_t *wire,
                    const struct TALER_MasterPublicKeyP *master_pub,
                    char **emsg);


  /**
   * Prepare for exeuction of a wire transfer.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param wire valid wire account information
   * @param amount amount to transfer, already rounded
   * @param exchange_base_url base URL of this exchange
   * @param wtid wire transfer identifier to use
   * @param ptc function to call with the prepared data to persist
   * @param ptc_cls closure for @a ptc
   * @return NULL on failure
   */
  struct TALER_WIRE_PrepareHandle *
  (*prepare_wire_transfer) (void *cls,
                            const json_t *wire,
                            const struct TALER_Amount *amount,
                            const char *exchange_base_url,
                            const struct TALER_WireTransferIdentifierRawP *wtid,
                            TALER_WIRE_PrepareTransactionCallback ptc,
                            void *ptc_cls);

  /**
   * Abort preparation of a wire transfer. For example,
   * because we are shutting down.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param pth preparation to cancel
   */
  void
  (*prepare_wire_transfer_cancel) (void *cls,
                                   struct TALER_WIRE_PrepareHandle *pth);


  /**
   * Execute a wire transfer.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param buf buffer with the prepared execution details
   * @param buf_size number of bytes in @a buf
   * @param cc function to call upon success
   * @param cc_cls closure for @a cc
   * @return NULL on error
   */
  struct TALER_WIRE_ExecuteHandle *
  (*execute_wire_transfer) (void *cls,
                            const char *buf,
                            size_t buf_size,
                            TALER_WIRE_ConfirmationCallback cc,
                            void *cc_cls);


  /**
   * Abort execution of a wire transfer. For example, because we are
   * shutting down.  Note that if an execution is aborted, it may or
   * may not still succeed. The caller MUST run @e
   * execute_wire_transfer again for the same request as soon as
   * possilbe, to ensure that the request either ultimately succeeds
   * or ultimately fails. Until this has been done, the transaction is
   * in limbo (i.e. may or may not have been committed).
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param eh execution to cancel
   */
  void
  (*execute_wire_transfer_cancel) (void *cls,
                                   struct TALER_WIRE_ExecuteHandle *eh);


  /**
   * Query transfer history of an account.  We use the variable-size
   * @a start_off to indicate which transfers we are interested in as
   * different banking systems may have different ways to identify
   * transfers.  The @a start_off value must thus match the value of
   * a `row_off` argument previously given to the @a hres_cb.  Use
   * NULL to query transfers from the beginning of time (with
   * positive @a num_results) or from the latest committed transfers
   * (with negative @a num_results).
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param direction what kinds of wire transfers should be returned
   * @param start_off from which row on do we want to get results, use NULL for the latest; exclusive
   * @param start_off_len number of bytes in @a start_off
   * @param num_results how many results do we want; negative numbers to go into the past,
   *                    positive numbers to go into the future starting at @a start_row;
   *                    must not be zero.
   * @param hres_cb the callback to call with the transaction history
   * @param hres_cb_cls closure for the above callback
   */
  struct TALER_WIRE_HistoryHandle *
  (*get_history) (void *cls,
                  enum TALER_BANK_Direction direction,
                  const void *start_off,
                  size_t start_off_len,
                  int64_t num_results,
                  TALER_WIRE_HistoryResultCallback hres_cb,
                  void *hres_cb_cls);

  /**
   * Cancel going over the account's history.
   *
   * @param cls plugins' closure
   * @param whh operation to cancel
   */
  void
  (*get_history_cancel) (void *cls,
			 struct TALER_WIRE_HistoryHandle *whh);


  /**
   * Reject an incoming wire transfer that was obtained from the
   * history. This function can be used to transfer funds back to
   * the sender if the WTID was malformed (i.e. due to a typo).
   *
   * Calling `reject_transfer` twice on the same wire transfer should
   * be idempotent, i.e. not cause the funds to be wired back twice.
   * Furthermore, the transfer should henceforth be removed from the
   * results returned by @e get_history.
   *
   * @param cls plugin's closure
   * @param start_off offset of the wire transfer in plugin-specific format
   * @param start_off_len number of bytes in @a start_off
   * @param rej_cb function to call with the result of the operation
   * @param rej_cb_cls closure for @a rej_cb
   * @return handle to cancel the operation
   */
  struct TALER_WIRE_RejectHandle *
  (*reject_transfer)(void *cls,
                     const void *start_off,
                     size_t start_off_len,
                     TALER_WIRE_RejectTransferCallback rej_cb,
                     void *rej_cb_cls);

  /**
   * Cancel ongoing reject operation.  Note that the rejection may still
   * proceed. Basically, if this function is called, the rejection may
   * have happened or not.  This function is usually used during shutdown
   * or system upgrades.  At a later point, the application must call
   * @e reject_transfer again for this wire transfer, unless the
   * @e get_history shows that the wire transfer no longer exists.
   *
   * @param cls plugins' closure
   * @param rh operation to cancel
   * @return closure of the callback of the operation
   */
  void *
  (*reject_transfer_cancel)(void *cls,
                            struct TALER_WIRE_RejectHandle *rh);


};


#endif /* TALER_WIRE_PLUGIN_H */
