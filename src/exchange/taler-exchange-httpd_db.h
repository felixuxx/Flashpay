/*
  This file is part of TALER
  Copyright (C) 2014-2017 Taler Systems SA

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
 * @file exchange/taler-exchange-httpd_db.h
 * @brief High-level (transactional-layer) database operations for the exchange
 * @author Chrisitan Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_DB_H
#define TALER_EXCHANGE_HTTPD_DB_H

#include <microhttpd.h>
#include "taler_exchangedb_plugin.h"
#include <gnunet/gnunet_mhd_compat.h>


/**
 * Ensure coin is known in the database, and handle conflicts and errors.
 *
 * @param coin the coin to make known
 * @param connection MHD request context
 * @param session database session and transaction to use
 * @param[out] mhd_ret set to MHD status on error
 * @return transaction status, negative on error (@a mhd_ret will be set in this case)
 */
enum GNUNET_DB_QueryStatus
TEH_make_coin_known (const struct TALER_CoinPublicInfo *coin,
                     struct MHD_Connection *connection,
                     struct TALER_EXCHANGEDB_Session *session,
                     MHD_RESULT *mhd_ret);


/**
 * Function implementing a database transaction.  Runs the transaction
 * logic; IF it returns a non-error code, the transaction logic MUST
 * NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF
 * it returns the soft error code, the function MAY be called again to
 * retry and MUST not queue a MHD response.
 *
 * @param cls closure
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
typedef enum GNUNET_DB_QueryStatus
(*TEH_DB_TransactionCallback)(void *cls,
                              struct MHD_Connection *connection,
                              struct TALER_EXCHANGEDB_Session *session,
                              MHD_RESULT *mhd_ret);


/**
 * Run a database transaction for @a connection.
 * Starts a transaction and calls @a cb.  Upon success,
 * attempts to commit the transaction.  Upon soft failures,
 * retries @a cb a few times.  Upon hard or persistent soft
 * errors, generates an error message for @a connection.
 *
 * @param connection MHD connection to run @a cb for, can be NULL
 * @param name name of the transaction (for debugging)
 * @param[out] mhd_ret set to MHD response code, if transaction failed (returned #GNUNET_SYSERR);
 *             NULL if we are not running with a @a connection and thus
 *             must not queue MHD replies
 * @param cb callback implementing transaction logic
 * @param cb_cls closure for @a cb, must be read-only!
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on failure
 */
enum GNUNET_GenericReturnValue
TEH_DB_run_transaction (struct MHD_Connection *connection,
                        const char *name,
                        MHD_RESULT *mhd_ret,
                        TEH_DB_TransactionCallback cb,
                        void *cb_cls);


#endif
/* TALER_EXCHANGE_HTTPD_DB_H */
