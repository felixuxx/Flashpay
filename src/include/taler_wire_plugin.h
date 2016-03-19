/*
  This file is part of TALER
  Copyright (C) 2016 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
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
 * Handle returned for cancelling a preparation step.
 */
struct TALER_WIRE_PrepareHandle;


/**
 * Handle returned for cancelling an execution step.
 */
struct TALER_WIRE_ExecuteHandle;


/**
 * Function called with the result from the execute step.
 *
 * @param cls closure
 * @param success #GNUNET_OK on success, #GNUNET_SYSERR on failure
 * @param emsg NULL on success, otherwise an error message
 */
typedef void
(*TALER_WIRE_ConfirmationCallback)(void *cls,
                                   int success,
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
   * Check if the given wire format JSON object is correctly formatted
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param wire the JSON wire format object
   * @param master_pub public key of the exchange to verify against
   * @return #GNUNET_YES if correctly formatted; #GNUNET_NO if not
   */
  int
  (*wire_validate) (void *cls,
                    const json_t *wire,
                    const struct TALER_MasterPublicKeyP *master_pub);


  /**
   * Prepare for exeuction of a wire transfer.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param wire valid wire account information
   * @param amount amount to transfer, already rounded
   * @param wtid wire transfer identifier to use
   * @param ptc function to call with the prepared data to persist
   * @param ptc_cls closure for @a ptc
   * @return NULL on failure
   */
  struct TALER_WIRE_PrepareHandle *
  (*prepare_wire_transfer) (void *cls,
                            const json_t *wire,
                            const struct TALER_Amount *amount,
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


};


#endif /* TALER_WIRE_PLUGIN_H */
