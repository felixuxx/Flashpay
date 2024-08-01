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
#include "taler-auditor-httpd_historic-reserve-summary-get.h"

/**
* Add historic-reserve-summary to the list.
*
* @param[in,out] cls a `json_t *` array to extend
* @param serial_id location of the @a dc in the database
* @param dc struct of inconsistencies
* @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop iterating
*/
static enum GNUNET_GenericReturnValue
process_historic_reserve_summary (
  void *cls,
  uint64_t serial_id,
  const struct TALER_AUDITORDB_HistoricReserveSummary *dc)
{
  json_t *list = cls;
  json_t *obj;

  obj = GNUNET_JSON_PACK (

    GNUNET_JSON_pack_int64 ("row_id", serial_id),
    TALER_JSON_pack_time_abs_human ("start_date", dc->start_date),
    TALER_JSON_pack_time_abs_human ("end_date", dc->end_date),
    TALER_JSON_pack_amount ("reserve_profits", &dc->reserve_profits)


    );
  GNUNET_break (0 ==
                json_array_append_new (list,
                                       obj));


  return GNUNET_OK;
}


MHD_RESULT
TAH_HISTORIC_RESERVE_SUMMARY_handler_get (
  struct TAH_RequestHandler *rh,
  struct MHD_Connection *connection,
  void **connection_cls,
  const char *upload_data,
  size_t *upload_data_size,
  const char *const args[])
{
  json_t *ja;
  enum GNUNET_DB_QueryStatus qs;

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
  ja = json_array ();
  GNUNET_break (NULL != ja);

  int64_t limit = -20;
  uint64_t offset;

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

  bool return_suppressed = false;

  qs = TAH_plugin->get_historic_reserve_summary (
    TAH_plugin->cls,
    limit,
    offset,
    return_suppressed,
    &process_historic_reserve_summary,
    ja);

  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
    json_decref (ja);
    TALER_LOG_WARNING (
      "Failed to handle GET /historic-reserve-summary");
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_FETCH_FAILED,
                                       "historic-reserve-summary");
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_array_steal ("historic-reserve-summary",
                                  ja));
}
