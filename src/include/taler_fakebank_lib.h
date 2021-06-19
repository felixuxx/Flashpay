/*
  This file is part of TALER
  (C) 2016-2021 Taler Systems SA

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
 * @file include/taler_fakebank_lib.h
 * @brief API for a library that fakes being a Taler bank
 * @author Christian Grothoff <christian@grothoff.org>
 */
#ifndef TALER_FAKEBANK_H
#define TALER_FAKEBANK_H

#include "taler_util.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler_json_lib.h"
#include <microhttpd.h>

/**
 * Handle for the fake bank.
 */
struct TALER_FAKEBANK_Handle;


/**
 * Start the fake bank.  The fake bank will, like the normal bank, listen for
 * requests for /admin/add/incoming and /transfer. However, instead of
 * executing or storing those requests, it will simply allow querying whether
 * such a request has been made via #TALER_FAKEBANK_check_debit() and
 * #TALER_FAKEBANK_check_credit() as well as the history API.
 *
 * This is useful for writing testcases to check whether the exchange
 * would have issued the correct wire transfer orders.
 *
 * @param port port to listen to
 * @param currency which currency should the bank offer
 * @return NULL on error
 */
struct TALER_FAKEBANK_Handle *
TALER_FAKEBANK_start (uint16_t port,
                      const char *currency);


/**
 * Start the fake bank.  The fake bank will, like the normal bank, listen for
 * requests for /admin/add/incoming and /transfer. However, instead of
 * executing or storing those requests, it will simply allow querying whether
 * such a request has been made via #TALER_FAKEBANK_check_debit() and
 * #TALER_FAKEBANK_check_credit() as well as the history API.
 *
 * This is useful for writing testcases to check whether the exchange
 * would have issued the correct wire transfer orders.
 *
 * @param port port to listen to
 * @param currency which currency should the bank offer
 * @param ram_limit how much memory do we use at most
 * @param num_threads size of the thread pool, 0 to use the GNUnet scheduler
 * @param close_connections true to force closing a connection after each request (no HTTP keep-alive)
 * @return NULL on error
 */
struct TALER_FAKEBANK_Handle *
TALER_FAKEBANK_start2 (uint16_t port,
                       const char *currency,
                       uint64_t ram_limit,
                       unsigned int num_threads,
                       bool close_connections);


/**
 * Check that no wire transfers were ordered (or at least none
 * that have not been taken care of via #TALER_FAKEBANK_check_debit()
 * or #TALER_FAKEBANK_check_credit()).
 * If any transactions are onrecord, return #GNUNET_SYSERR.
 *
 * Note that this function only works in
 * single-threaded mode while nothing else is happening.
 *
 * @param h bank instance
 * @return #GNUNET_OK on success
 */
int
TALER_FAKEBANK_check_empty (struct TALER_FAKEBANK_Handle *h);


/**
 * Tell the fakebank to create another wire transfer *from* an exchange.
 *
 * @param h fake bank handle
 * @param debit_account account to debit
 * @param credit_account account to credit
 * @param amount amount to transfer
 * @param subject wire transfer subject to use
 * @param exchange_base_url exchange URL
 * @param request_uid unique number to make the request unique, or NULL to create one
 * @param[out] ret_row_id pointer to store the row ID of this transaction
 * @return #GNUNET_YES if the transfer was successful,
 *         #GNUNET_SYSERR if the request_uid was reused for a different transfer
 */
int
TALER_FAKEBANK_make_transfer (
  struct TALER_FAKEBANK_Handle *h,
  const char *debit_account,
  const char *credit_account,
  const struct TALER_Amount *amount,
  const struct TALER_WireTransferIdentifierRawP *subject,
  const char *exchange_base_url,
  const struct GNUNET_HashCode *request_uid,
  uint64_t *ret_row_id);


/**
 * Tell the fakebank to create another wire transfer *to* an exchange.
 *
 * @param h fake bank handle
 * @param debit_account account to debit
 * @param credit_account account to credit
 * @param amount amount to transfer
 * @param reserve_pub reserve public key to use in subject
 * @return serial_id of the transfer, 0 on error
 */
uint64_t
TALER_FAKEBANK_make_admin_transfer (
  struct TALER_FAKEBANK_Handle *h,
  const char *debit_account,
  const char *credit_account,
  const struct TALER_Amount *amount,
  const struct TALER_ReservePublicKeyP *reserve_pub);


/**
 * Check that the @a want_amount was transferred from the @a
 * want_debit to the @a want_credit account.  If so, set the @a subject
 * to the transfer identifier and remove the transaction from the
 * list.  If the transaction was not recorded, return #GNUNET_SYSERR.
 *
 * Note that this function only works in
 * single-threaded mode while nothing else is happening.
 *
 * @param h bank instance
 * @param want_amount transfer amount desired
 * @param want_debit account that should have been debited
 * @param want_debit account that should have been credited
 * @param exchange_base_url expected base URL of the exchange,
 *        i.e. "https://example.com/"; may include a port
 * @param[out] wtid set to the wire transfer identifier
 * @return #GNUNET_OK on success
 */
int
TALER_FAKEBANK_check_debit (struct TALER_FAKEBANK_Handle *h,
                            const struct TALER_Amount *want_amount,
                            const char *want_debit,
                            const char *want_credit,
                            const char *exchange_base_url,
                            struct TALER_WireTransferIdentifierRawP *wtid);


/**
 * Check that the @a want_amount was transferred from the @a want_debit to the
 * @a want_credit account with the @a subject.  If so, remove the transaction
 * from the list.  If the transaction was not recorded, return #GNUNET_SYSERR.
 *
 * Note that this function only works in
 * single-threaded mode while nothing else is happening.
 *
 * @param h bank instance
 * @param want_amount transfer amount desired
 * @param want_debit account that should have been debited
 * @param want_debit account that should have been credited
 * @param reserve_pub reserve public key expected in wire subject
 * @return #GNUNET_OK on success
 */
int
TALER_FAKEBANK_check_credit (struct TALER_FAKEBANK_Handle *h,
                             const struct TALER_Amount *want_amount,
                             const char *want_debit,
                             const char *want_credit,
                             const struct TALER_ReservePublicKeyP *reserve_pub);


/**
 * Stop running the fake bank.
 *
 * @param h bank to stop
 */
void
TALER_FAKEBANK_stop (struct TALER_FAKEBANK_Handle *h);


#endif
