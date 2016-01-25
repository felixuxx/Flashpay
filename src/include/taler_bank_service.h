/*
  This file is part of TALER
  Copyright (C) 2015, 2016 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file include/taler_bank_service.h
 * @brief C interface of libtalerbank, a C library to use the Taler bank's HTTP API
 * @author Christian Grothoff
 */
#ifndef _TALER_BANK_SERVICE_H
#define _TALER_BANK_SERVICE_H

#include "taler_util.h"

/* ********************* event loop *********************** */

/**
 * @brief Handle to this library context.  This is where the
 * main event loop logic lives.
 */
struct TALER_BANK_Context;


/**
 * Initialise a context.  A context should be used for each thread and should
 * not be shared among multiple threads.
 *
 * @param url HTTP base URL for the bank
 * @return the context, NULL on error (failure to initialize)
 */
struct TALER_BANK_Context *
TALER_BANK_init (const char *url);


/**
 * Obtain the information for a select() call to wait until
 * #TALER_BANK_perform() is ready again.  Note that calling
 * any other TALER_BANK-API may also imply that the library
 * is again ready for #TALER_BANK_perform().
 *
 * Basically, a client should use this API to prepare for select(),
 * then block on select(), then call #TALER_BANK_perform() and then
 * start again until the work with the context is done.
 *
 * This function will NOT zero out the sets and assumes that @a max_fd
 * and @a timeout are already set to minimal applicable values.  It is
 * safe to give this API FD-sets and @a max_fd and @a timeout that are
 * already initialized to some other descriptors that need to go into
 * the select() call.
 *
 * @param ctx context to get the event loop information for
 * @param read_fd_set will be set for any pending read operations
 * @param write_fd_set will be set for any pending write operations
 * @param except_fd_set is here because curl_multi_fdset() has this argument
 * @param max_fd set to the highest FD included in any set;
 *        if the existing sets have no FDs in it, the initial
 *        value should be "-1". (Note that `max_fd + 1` will need
 *        to be passed to select().)
 * @param timeout set to the timeout in milliseconds (!); -1 means
 *        no timeout (NULL, blocking forever is OK), 0 means to
 *        proceed immediately with #TALER_BANK_perform().
 */
void
TALER_BANK_get_select_info (struct TALER_BANK_Context *ctx,
                            fd_set *read_fd_set,
                            fd_set *write_fd_set,
                            fd_set *except_fd_set,
                            int *max_fd,
                            long *timeout);


/**
 * Run the main event loop for the Taler interaction.
 *
 * @param ctx the library context
 */
void
TALER_BANK_perform (struct TALER_BANK_Context *ctx);


/**
 * Cleanup library initialisation resources.  This function should be called
 * after using this library to cleanup the resources occupied during library's
 * initialisation.
 *
 * @param ctx the library context
 */
void
TALER_BANK_fini (struct TALER_BANK_Context *ctx);


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
 */
typedef void
(*TALER_BANK_AdminAddIncomingResultCallback) (void *cls,
                                              unsigned int http_status);


/**
 * Notify the bank that we have received an incoming transaction
 * which fills a reserve.  Note that this API is an administrative
 * API and thus not accessible to typical bank clients, but only
 * to the operators of the bank.
 *
 * @param bank the bank handle; the bank must be ready to operate
 * @param reserve_pub public key of the reserve
 * @param amount amount that was deposited
 * @param execution_date when did we receive the amount
 * @param wire wire details
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return NULL
 *         if the inputs are invalid (i.e. invalid amount).
 *         In this case, the callback is not called.
 */
struct TALER_BANK_AdminAddIncomingHandle *
TALER_BANK_admin_add_incoming (struct TALER_BANK_Context *bank,
                               const struct TALER_WireTransferIdentifierRawP *wtid,
                               const struct TALER_Amount *amount,
                               const json_t *wire,
                               TALER_BANK_AdminAddIncomingResultCallback res_cb,
                               void *res_cb_cls);


/**
 * Cancel an add incoming.  This function cannot be used on a request
 * handle if a response is already served for it.
 *
 * @param aai the admin add incoming request handle
 */
void
TALER_BANK_admin_add_incoming_cancel (struct TALER_BANK_AdminAddIncomingHandle *aai);

#endif  /* _TALER_BANK_SERVICE_H */
