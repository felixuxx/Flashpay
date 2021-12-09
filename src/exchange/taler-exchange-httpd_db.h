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
#include "taler-exchange-httpd_metrics.h"
#include <gnunet/gnunet_mhd_compat.h>


/**
 * Ensure coin is known in the database, and handle conflicts and errors.
 *
 * @param coin the coin to make known
 * @param connection MHD request context
 * @param[out] mhd_ret set to MHD status on error
 * @return transaction status, negative on error (@a mhd_ret will be set in this case)
 */
enum GNUNET_DB_QueryStatus
TEH_make_coin_known (const struct TALER_CoinPublicInfo *coin,
                     struct MHD_Connection *connection,
                     MHD_RESULT *mhd_ret);


/**
 * Check that a coin has an adequate balance so that we can
 * commit the current transaction. If the balance is
 * insufficient for all transactions associated with the
 * coin, return a hard error.
 *
 * We first do a "fast" check using a stored procedure, and
 * only obtain the "full" data on failure (for performance).
 *
 * @param connection HTTP connection to report hard errors on
 * @param coin_pub coin to analyze
 * @param coin_value total value of the original coin (by denomination)
 * @param op_cost cost of the current operation (for error reporting)
 * @param check_recoup should we include recoup transactions in the check
 * @param zombie_required additional requirement that the coin must
 *          be a zombie coin, or also hard failure
 * @param[out] mhd_ret set to response status code, on hard error only
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_check_coin_balance (struct MHD_Connection *connection,
                        const struct TALER_CoinSpendPublicKeyP *coin_pub,
                        const struct TALER_Amount *coin_value,
                        const struct TALER_Amount *op_cost,
                        bool check_recoup,
                        bool zombie_required,
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
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
typedef enum GNUNET_DB_QueryStatus
(*TEH_DB_TransactionCallback)(void *cls,
                              struct MHD_Connection *connection,
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
 * @param mt type of the requests, for metric generation
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
                        enum TEH_MetricType mt,
                        MHD_RESULT *mhd_ret,
                        TEH_DB_TransactionCallback cb,
                        void *cb_cls);


#endif
/* TALER_EXCHANGE_HTTPD_DB_H */
