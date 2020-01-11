/*
  This file is part of TALER
  Copyright (C) 2016-2020 Taler Systems SA

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
 */
struct TALER_WIRE_CreditDetails
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
   * Binary data that was encoded in the wire transfer subject.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * payto://-URL of the source's account (used
   * when the reserve is closed or for debugging).
   */
  const char *source_account_url;
};


/**
 * Details about a valid wire transfer made by the
 * exchange's aggregator to a merchant.
 */
struct TALER_WIRE_DebitDetails
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
   * Binary data that was encoded in the wire transfer subject.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * payto://-URL of the target account which received
   * the funds.
   */
  const char *target_account_url;
};


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank for the transaction history.  NOTE: this function will
 * NOT get the list of history elements, but rather get (iteratively)
 * called for each (parsed) history element.
 *
 * @param cls closure
 * @param ec taler error code
 * @param row_off identification of the position at which we are querying
 * @param row_off_size number of bytes in @a row_off
 * @param details details about the wire transfer
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to abort iteration
 */
typedef int
(*TALER_WIRE_CreditResultCallback) (void *cls,
                                    enum TALER_ErrorCode ec,
                                    const void *row_off,
                                    size_t row_off_size,
                                    const struct
                                    TALER_WIRE_CreditDetails *details);


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank for the transaction history.  NOTE: this function will
 * NOT get the list of history elements, but rather get (iteratively)
 * called for each (parsed) history element.
 *
 * @param cls closure
 * @param ec taler error code
 * @param row_off identification of the position at which we are querying
 * @param row_off_size number of bytes in @a row_off
 * @param details details about the wire transfer
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to abort iteration
 */
typedef int
(*TALER_WIRE_DebitResultCallback) (void *cls,
                                   enum TALER_ErrorCode ec,
                                   const void *row_off,
                                   size_t row_off_size,
                                   const struct
                                   TALER_WIRE_DebitDetails *details);


/**
 * Handle returned for cancelling a preparation step.
 */
struct TALER_WIRE_PrepareHandle;

/**
 * Handle returned for cancelling an execution step.
 */
struct TALER_WIRE_ExecuteHandle;

/**
 * Handle returned for querying the credit transaction history.
 */
struct TALER_WIRE_CreditHistoryHandle;

/**
 * Handle returned for querying the debit transaction history.
 */
struct TALER_WIRE_DebitHistoryHandle;


/**
 * Function called with the result from the execute step.
 *
 * @param cls closure
 * @param success #GNUNET_OK on success, #GNUNET_SYSERR on failure
 * @param row_id unique ID of the wire transfer in the bank's records; NULL on error
 * @param row_id_size number of bytes in @e row_id
 * @param emsg NULL on success, otherwise an error message
 */
typedef void
(*TALER_WIRE_ConfirmationCallback)(void *cls,
                                   int success,
                                   const void *row_id,
                                   size_t row_id_size,
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
   * Which wire method (payto://METHOD/") is supported by this plugin?
   * For example, "x-taler-bank" or "iban".
   */
  const char *method;

  /**
   * Round amount DOWN to the amount that can be transferred via the wire
   * method.  For example, Taler may support 0.000001 EUR as a unit of
   * payment, but IBAN only supports 0.01 EUR.  This function would
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
   * Check if the given payto:// URL is correctly formatted for this plugin
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param account_url the payto:// URL
   * @return #TALER_EC_NONE if correctly formatted
   */
  enum TALER_ErrorCode
  (*wire_validate)(void *cls,
                   const char *account_url);


  /**
   * Query credits made to exchange account.  We use the variable-size
   * @a start_off to indicate which transfers we are interested in as
   * different banking systems may have different ways to identify
   * transfers.  The @a start_off value must thus match the value of
   * a `row_off` argument previously given to the @a hres_cb.  Use
   * NULL to query transfers from the beginning of time (with
   * positive @a num_results) or from the latest committed transfers
   * (with negative @a num_results).
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param account_section specifies the configuration section which
   *        identifies the account for which we should get the history
   * @param start_off from which row on do we want to get results, use NULL for the latest; exclusive
   * @param start_off_len number of bytes in @a start_off
   * @param num_results how many results do we want; negative numbers to go into the past,
   *                    positive numbers to go into the future starting at @a start_row;
   *                    must not be zero.
   * @param hres_cb the callback to call with the transaction history
   * @param hres_cb_cls closure for the above callback
   */
  struct TALER_WIRE_CreditHistoryHandle *
  (*get_credits) (void *cls,
                  const char *account_section,
                  const void *start_off,
                  size_t start_off_len,
                  int64_t num_results,
                  TALER_WIRE_CreditResultCallback hres_cb,
                  void *hres_cb_cls);

  /**
   * Cancel going over the account's history.
   *
   * @param cls plugins' closure
   * @param chh operation to cancel
   */
  void
  (*get_credits_cancel) (void *cls,
                         struct TALER_WIRE_CreditHistoryHandle *chh);


  /**
   * Query debits (transfers to merchants) made by an exchange.  We use the
   * variable-size @a start_off to indicate which transfers we are interested
   * in as different banking systems may have different ways to identify
   * transfers.  The @a start_off value must thus match the value of a
   * `row_off` argument previously given to the @a hres_cb.  Use NULL to query
   * transfers from the beginning of time (with positive @a num_results) or
   * from the latest committed transfers (with negative @a num_results).
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param account_section specifies the configuration section which
   *        identifies the account for which we should get the history
   * @param start_off from which row on do we want to get results, use NULL for the latest; exclusive
   * @param start_off_len number of bytes in @a start_off
   * @param num_results how many results do we want; negative numbers to go into the past,
   *                    positive numbers to go into the future starting at @a start_row;
   *                    must not be zero.
   * @param hres_cb the callback to call with the transaction history
   * @param hres_cb_cls closure for the above callback
   */
  struct TALER_WIRE_DebitHistoryHandle *
  (*get_debits) (void *cls,
                 const char *account_section,
                 const void *start_off,
                 size_t start_off_len,
                 int64_t num_results,
                 TALER_WIRE_DebitResultCallback hres_cb,
                 void *hres_cb_cls);

  /**
   * Cancel going over the account's history.
   *
   * @param cls plugins' closure
   * @param dhh operation to cancel
   */
  void
  (*get_debits_cancel) (void *cls,
                        struct TALER_WIRE_DebitHistoryHandle *dhh);


};


#endif /* TALER_WIRE_PLUGIN_H */
