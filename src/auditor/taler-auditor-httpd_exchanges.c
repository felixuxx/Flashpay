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
#include "taler-auditor-httpd_exchanges.h"


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
  GNUNET_break (NULL != obj);
  GNUNET_break (0 ==
                json_array_append_new (list,
                                       obj));

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
MHD_RESULT
TAH_EXCHANGES_handler (struct TAH_RequestHandler *rh,
                       struct MHD_Connection *connection,
                       void **connection_cls,
                       const char *upload_data,
                       size_t *upload_data_size)
{
  json_t *ja;
  struct TALER_AUDITORDB_Session *session;
  enum GNUNET_DB_QueryStatus qs;

  (void) rh;
  (void) connection_cls;
  (void) upload_data;
  (void) upload_data_size;
  session = TAH_plugin->get_session (TAH_plugin->cls);
  if (NULL == session)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_DB_SETUP_FAILED,
                                       NULL);
  }
  ja = json_array ();
  GNUNET_break (NULL != ja);
  qs = TAH_plugin->list_exchanges (TAH_plugin->cls,
                                   session,
                                   &add_exchange,
                                   ja);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
    json_decref (ja);
    TALER_LOG_WARNING ("Failed to handle /exchanges in database\n");
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_LIST_EXCHANGES_DB_ERROR,
                                       NULL);
  }
  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_OK,
                                    "{s:o}",
                                    "exchanges", ja);
}


/* end of taler-auditor-httpd_exchanges.c */
