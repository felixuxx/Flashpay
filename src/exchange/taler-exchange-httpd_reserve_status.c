/*
  This file is part of TALER
  Copyright (C) 2014-2017 GNUnet e.V.

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
 * @file taler-exchange-httpd_reserve_status.c
 * @brief Handle /reserve/status requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_mhd_lib.h"
#include "taler_json_lib.h"
#include "taler-exchange-httpd_reserve_status.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keystate.h"


/**
 * Send reserve status information to client.
 *
 * @param connection connection to the client
 * @param rh reserve history to return
 * @return MHD result code
 */
static int
reply_reserve_status_success (struct MHD_Connection *connection,
                              const struct TALER_EXCHANGEDB_ReserveHistory *rh)
{
  json_t *json_balance;
  json_t *json_history;
  struct TALER_Amount balance;

  json_history = TEH_RESPONSE_compile_reserve_history (rh,
                                                       &balance);
  if (NULL == json_history)
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_RESERVE_STATUS_DB_ERROR,
                                       "balance calculation failure");
  json_balance = TALER_JSON_from_amount (&balance);
  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_OK,
                                    "{s:o, s:o}",
                                    "balance", json_balance,
                                    "history", json_history);
}


/**
 * Closure for #reserve_status_transaction.
 */
struct ReserveStatusContext
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
 * Function implementing /reserve/status transaction.
 * Execute a /reserve/status.  Given the public key of a reserve,
 * return the associated transaction history.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error,
 * the transaction logic MUST queue a MHD response and set @a mhd_ret.
 * IF it returns the soft error code, the function MAY be called again
 * to retry and MUST not queue a MHD response.
 *
 * @param cls a `struct ReserveStatusContext *`
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!); unused
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
reserve_status_transaction (void *cls,
                            struct MHD_Connection *connection,
                            struct TALER_EXCHANGEDB_Session *session,
                            int *mhd_ret)
{
  struct ReserveStatusContext *rsc = cls;

  (void) connection;
  (void) mhd_ret;
  return TEH_plugin->get_reserve_history (TEH_plugin->cls,
                                          session,
                                          &rsc->reserve_pub,
                                          &rsc->rh);
}


/**
 * Handle a "/reserve/status" request.  Parses the
 * given "reserve_pub" argument (which should contain the
 * EdDSA public key of a reserve) and then respond with the
 * status of the reserve.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TEH_RESERVE_handler_reserve_status (struct TEH_RequestHandler *rh,
                                    struct MHD_Connection *connection,
                                    void **connection_cls,
                                    const char *upload_data,
                                    size_t *upload_data_size)
{
  struct ReserveStatusContext rsc;
  int res;
  int mhd_ret;

  res = TALER_MHD_parse_request_arg_data (connection,
                                          "reserve_pub",
                                          &rsc.reserve_pub,
                                          sizeof (struct
                                                  TALER_ReservePublicKeyP));
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* internal error */
  if (GNUNET_NO == res)
    return MHD_YES; /* parse error */
  rsc.rh = NULL;
  if (GNUNET_OK !=
      TEH_DB_run_transaction (connection,
                              "get reserve status",
                              &mhd_ret,
                              &reserve_status_transaction,
                              &rsc))
    return mhd_ret;

  /* generate proper response */
  if (NULL == rsc.rh)
    return TALER_MHD_reply_json_pack (connection,
                                      MHD_HTTP_NOT_FOUND,
                                      "{s:s, s:s, s:I}",
                                      "error", "Reserve not found",
                                      "parameter", "withdraw_pub",
                                      "code",
                                      (json_int_t)
                                      TALER_EC_RESERVE_STATUS_UNKNOWN);
  mhd_ret = reply_reserve_status_success (connection,
                                          rsc.rh);
  TEH_plugin->free_reserve_history (TEH_plugin->cls,
                                    rsc.rh);
  return mhd_ret;
}


/* end of taler-exchange-httpd_reserve_status.c */
