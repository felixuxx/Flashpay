/*
  This file is part of TALER
  (C) 2016 Inria and GNUnet e.V.

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
 * Start the fake bank.  The fake bank will, like the normal bank,
 * listen for requests for /admin/add/incoming. However, instead of
 * executing or storing those requests, it will simply allow querying
 * whether such a request has been made via #TALER_FAKEBANK_check().
 *
 * This is useful for writing testcases to check whether the exchange
 * would have issued the correct wire transfer orders.
 *
 * @param port port to listen to
 * @return NULL on error
 */
struct TALER_FAKEBANK_Handle *
TALER_FAKEBANK_start (uint16_t port);


/**
 * Check that no wire transfers were ordered (or at least none
 * that have not been taken care of via #TALER_FAKEBANK_check()).
 * If any transactions are onrecord, return #GNUNET_SYSERR.
 *
 * @param h bank instance
 * @return #GNUNET_OK on success
 */
int
TALER_FAKEBANK_check_empty (struct TALER_FAKEBANK_Handle *h);


/**
 * Check that the @a want_amount was transferred from the @a
 * want_debit to the @a want_credit account.  If so, set the @a wtid
 * to the transfer identifier and remove the transaction from the
 * list.  If the transaction was not recorded, return #GNUNET_SYSERR.
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
TALER_FAKEBANK_check (struct TALER_FAKEBANK_Handle *h,
                      const struct TALER_Amount *want_amount,
                      uint64_t want_debit,
                      uint64_t want_credit,
                      const char *exchange_base_url,
                      struct TALER_WireTransferIdentifierRawP *wtid);


/**
 * Stop running the fake bank.
 *
 * @param h bank to stop
 */
void
TALER_FAKEBANK_stop (struct TALER_FAKEBANK_Handle *h);


#endif
