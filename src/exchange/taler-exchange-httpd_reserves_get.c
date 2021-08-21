/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file taler-exchange-httpd_reserves_get.c
 * @brief Handle /reserves/$RESERVE_PUB GET requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_mhd_lib.h"
#include "taler_json_lib.h"
#include "taler-exchange-httpd_reserves_get.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Reserve GET request that is long-polling.
 */
struct ReservePoller
{
  /**
   * Kept in a DLL.
   */
  struct ReservePoller *next;

  /**
   * Kept in a DLL.
   */
  struct ReservePoller *prev;

  /**
   * Connection we are handling.
   */
  struct MHD_Connection *connection;

  /**
   * Entry in the timeout heap.
   */
  struct GNUNET_CONTAINER_HeapNode *hn;

  /**
   * Subscription for the database event we are
   * waiting for.
   */
  struct GNUNET_DB_EventHandler *eh;

  /**
   * When will this request time out?
   */
  struct GNUNET_TIME_Absolute timeout;

};


/**
 * Send reserve history to client.
 *
 * @param connection connection to the client
 * @param rh reserve history to return
 * @return MHD result code
 */
static MHD_RESULT
reply_reserve_history_success (struct MHD_Connection *connection,
                               const struct TALER_EXCHANGEDB_ReserveHistory *rh)
{
  json_t *json_history;
  struct TALER_Amount balance;

  json_history = TEH_RESPONSE_compile_reserve_history (rh,
                                                       &balance);
  if (NULL == json_history)
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_JSON_ALLOCATION_FAILURE,
                                       NULL);
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    TALER_JSON_pack_amount ("balance",
                            &balance),
    GNUNET_JSON_pack_array_steal ("history",
                                  json_history));
}


/**
 * Closure for #reserve_history_transaction.
 */
struct ReserveHistoryContext
{
  /**
   * Public key of the reserve the inquiry is about.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * History of the reserve, set in the callback.
   */
  struct TALER_EXCHANGEDB_ReserveHistory *rh;

};


/**
 * Function implementing /reserves/ GET transaction.
 * Execute a /reserves/ GET.  Given the public key of a reserve,
 * return the associated transaction history.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error,
 * the transaction logic MUST queue a MHD response and set @a mhd_ret.
 * IF it returns the soft error code, the function MAY be called again
 * to retry and MUST not queue a MHD response.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!); unused
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
reserve_history_transaction (void *cls,
                             struct MHD_Connection *connection,
                             struct TALER_EXCHANGEDB_Session *session,
                             MHD_RESULT *mhd_ret)
{
  struct ReserveHistoryContext *rsc = cls;

  (void) connection;
  (void) mhd_ret;
  return TEH_plugin->get_reserve_history (TEH_plugin->cls,
                                          session,
                                          &rsc->reserve_pub,
                                          &rsc->rh);
}


MHD_RESULT
TEH_handler_reserves_get (struct TEH_RequestContext *rc,
                          const char *const args[1])
{
  struct ReserveHistoryContext rsc;
  MHD_RESULT mhd_ret;

  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &rsc.reserve_pub,
                                     sizeof (rsc.reserve_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_MERCHANT_GENERIC_RESERVE_PUB_MALFORMED,
                                       args[0]);
  }
  rsc.rh = NULL;
  if (GNUNET_OK !=
      TEH_DB_run_transaction (rc->connection,
                              "get reserve history",
                              &mhd_ret,
                              &reserve_history_transaction,
                              &rsc))
    return mhd_ret;

  /* generate proper response */
  if (NULL == rsc.rh)
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_EXCHANGE_RESERVES_GET_STATUS_UNKNOWN,
                                       args[0]);
  mhd_ret = reply_reserve_history_success (rc->connection,
                                           rsc.rh);
  TEH_plugin->free_reserve_history (TEH_plugin->cls,
                                    rsc.rh);
  return mhd_ret;
}


/* end of taler-exchange-httpd_reserves_get.c */
