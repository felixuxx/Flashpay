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
#include "taler-auditor-httpd_reserve-not-closed-inconsistency-get.h"


/**
 * Add reserve-not-closed-inconsistency to the list.
 *
 * @param[in,out] cls a `json_t *` array to extend
 * @param dc struct of inconsistencies
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop iterating
 */
static enum GNUNET_GenericReturnValue
process_reserve_not_closed_inconsistency (
  void *cls,
  const struct TALER_AUDITORDB_ReserveNotClosedInconsistency *dc)
{
  json_t *list = cls;
  json_t *obj;

  obj = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_uint64 ("row_id",
                             dc->row_id),
    GNUNET_JSON_pack_data_auto ("reserve_pub",
                                &dc->reserve_pub),
    TALER_JSON_pack_amount ("balance",
                            &dc->balance),
    TALER_JSON_pack_time_abs_human ("expiration_time",
                                    dc->expiration_time),
    GNUNET_JSON_pack_string ("diagnostic",
                             dc->diagnostic),
    GNUNET_JSON_pack_bool ("suppressed",
                           dc->suppressed)
    );
  GNUNET_break (0 ==
                json_array_append_new (list,
                                       obj));
  return GNUNET_OK;
}


MHD_RESULT
TAH_RESERVE_NOT_CLOSED_INCONSISTENCY_handler_get (
  struct TAH_RequestHandler *rh,
  struct MHD_Connection *connection,
  void **connection_cls,
  const char *upload_data,
  size_t *upload_data_size,
  const char *const args[])
{
  json_t *ja;
  enum GNUNET_DB_QueryStatus qs;
  int64_t limit = -20;
  uint64_t offset;
  bool return_suppressed = false;

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
  TALER_MHD_parse_request_snumber (connection,
                                   "limit",
                                   &limit);
  if (limit < 0)
    offset = INT64_MAX;
  else
    offset = 0;
  TALER_MHD_parse_request_number (connection,
                                  "offset",
                                  &offset);
  {
    const char *ret_s
      = MHD_lookup_connection_value (connection,
                                     MHD_GET_ARGUMENT_KIND,
                                     "return_suppressed");
    if ( (NULL != ret_s) &&
         (0 == strcmp (ret_s,
                       "true")) )
    {
      return_suppressed = true;
    }
  }

  ja = json_array ();
  GNUNET_break (NULL != ja);
  qs = TAH_plugin->get_reserve_not_closed_inconsistency (
    TAH_plugin->cls,
    limit,
    offset,
    return_suppressed,
    &process_reserve_not_closed_inconsistency,
    ja);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
    json_decref (ja);
    TALER_LOG_WARNING (
      "Failed to handle GET /reserve-not-closed-inconsistency");
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_FETCH_FAILED,
                                       "reserve-not-closed-inconsistency");
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_array_steal ("reserve_not_closed_inconsistency",
                                  ja));
}
