/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

   TALER is free software; you can redistribute it and/or modify it under the
   terms of the GNU General Public License as published by the Free Software
   Foundation; either version 3, or (at your option) any later version.

   TALER is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
   A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

   You should have received a copy of the GNU General Public License along with
   TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
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
#include "taler-auditor-httpd_balances-get.h"

/**
 * Add balance to the list.
 *
 * @param[in,out] cls a `json_t *` array to extend
 * @param dc struct of with balance data
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop iterating
 */
static enum GNUNET_GenericReturnValue
process_balances (
  void *cls,
  const struct TALER_AUDITORDB_Balances *dc)
{
  json_t *list = cls;
  json_t *obj;

  obj = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("balance_key",
                             dc->balance_key),
    TALER_JSON_pack_amount ("balance_value",
                            &dc->balance_value)
    );
  GNUNET_break (0 ==
                json_array_append_new (list,
                                       obj));
  return GNUNET_OK;
}


MHD_RESULT
TAH_BALANCES_handler_get (
  struct TAH_RequestHandler *rh,
  struct MHD_Connection *connection,
  void **connection_cls,
  const char *upload_data,
  size_t *upload_data_size,
  const char *const args[])
{
  json_t *ja;
  enum GNUNET_DB_QueryStatus qs;
  const char *balance_key;

  (void) rh;
  (void) connection_cls;
  (void) upload_data;
  (void) upload_data_size;
  if (GNUNET_SYSERR ==
      TAH_plugin->preflight (TAH_plugin->cls))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_SETUP_FAILED,
                                       NULL);
  }
  balance_key
    = MHD_lookup_connection_value (connection,
                                   MHD_GET_ARGUMENT_KIND,
                                   "balance_key");
  ja = json_array ();
  GNUNET_break (NULL != ja);
  qs = TAH_plugin->get_balances (
    TAH_plugin->cls,
    balance_key,
    &process_balances,
    ja);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
    json_decref (ja);
    TALER_LOG_WARNING (
      "Failed to handle GET /balances");
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_FETCH_FAILED,
                                       "balances");
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_array_steal ("balances",
                                  ja));
}
