/*
  This file is part of TALER
  Copyright (C) 2014-2018 Inria and GNUnet e.V.

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
 * @file taler-auditor-httpd_exchanges.c
 * @brief Handle /exchanges requests; returns list of exchanges we audit
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-auditor-httpd.h"
#include "taler-auditor-httpd_db.h"
#include "taler-auditor-httpd_exchanges.h"


/**
 * Send confirmation of deposit-confirmation success to client.
 *
 * @param connection connection to the client
 * @param ja array with information about exchanges
 * @return MHD result code
 */
static int
reply_exchanges_success (struct MHD_Connection *connection,
                         json_t *ja)
{
  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_OK,
                                    "{s:o}",
                                    "exchanges", ja);
}


/**
 * Add exchange information to the list.
 *
 * @param[in,out] cls a `json_t *` array to extend
 * @param master_pub master public key of an exchange
 * @param exchange_url base URL of an exchange
 */
static void
add_exchange (void *cls,
              const struct TALER_MasterPublicKeyP *master_pub,
              const char *exchange_url)
{
  json_t *list = cls;
  json_t *obj;

  obj = json_pack ("{s:o, s:s}",
                   "master_pub",
                   GNUNET_JSON_from_data_auto (master_pub),
                   "exchange_url",
                   exchange_url);
  GNUNET_assert (NULL != obj);
  GNUNET_assert (0 ==
                 json_array_append_new (list,
                                        obj));

}


/**
 * Execute database transaction for /exchanges. Obtains the list.  IF
 * it returns a non-error code, the transaction logic MUST NOT queue a
 * MHD response.  IF it returns an hard error, the transaction logic
 * MUST queue a MHD response and set @a mhd_ret.  IF it returns the
 * soft error code, the function MAY be called again to retry and MUST
 * not queue a MHD response.
 *
 * @param cls[in,out] a `json_t *` with an array of exchanges to be created
 * @param connection MHD request context
 * @param session database session and transaction to use
 * @param[out] mhd_ret set to MHD status on error
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
list_exchanges (void *cls,
                struct MHD_Connection *connection,
                struct TALER_AUDITORDB_Session *session,
                int *mhd_ret)
{
  json_t *list = cls;
  enum GNUNET_DB_QueryStatus qs;

  qs = TAH_plugin->list_exchanges (TAH_plugin->cls,
                                   session,
                                   &add_exchange,
                                   list);
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    TALER_LOG_WARNING ("Failed to handle /exchanges in database\n");
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_LIST_EXCHANGES_DB_ERROR,
                                           "Could not fetch exchange list from database");
  }
  return qs;
}


/**
 * Handle a "/exchanges" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TAH_EXCHANGES_handler (struct TAH_RequestHandler *rh,
                       struct MHD_Connection *connection,
                       void **connection_cls,
                       const char *upload_data,
                       size_t *upload_data_size)
{
  int mhd_ret;
  json_t *ja;

  ja = json_array ();
  if (GNUNET_OK !=
      TAH_DB_run_transaction (connection,
                              "list exchanges",
                              &mhd_ret,
                              &list_exchanges,
                              (void *) ja))
    return mhd_ret;
  return reply_exchanges_success (connection,
                                  ja);
}


/* end of taler-auditor-httpd_exchanges.c */
