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
#include "taler-auditor-httpd_historic-denomination-revenue-get.h"


/**
 * Add historic-denomination-revenue to the list.
 *
 * @param[in,out] cls a `json_t *` array to extend
 * @param serial_id location of the @a dc in the database
 * @param denom_pub_hash public key hash of the denomination
 * @param revenue_timestamp when was the revenue effective
 * @param revenue_balance how much in profit did we make from this denomination
 * @param loss_balance how much loss did we make from this denomination
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop iterating
 */
static enum GNUNET_GenericReturnValue
process_historic_denomination_revenue (
  void *cls,
  uint64_t serial_id,
  const struct TALER_DenominationHashP *denom_pub_hash,
  struct GNUNET_TIME_Timestamp revenue_timestamp,
  const struct TALER_Amount *revenue_balance,
  const struct TALER_Amount *loss_balance)
{
  json_t *list = cls;
  json_t *obj;

  obj = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_uint64 ("serial_id",
                             serial_id),
    GNUNET_JSON_pack_data_auto ("denom_pub_hash",
                                denom_pub_hash),
    TALER_JSON_pack_time_abs_human ("revenue_timestamp",
                                    revenue_timestamp.abs_time),
    TALER_JSON_pack_amount ("revenue_balance",
                            revenue_balance),
    TALER_JSON_pack_amount ("loss_balance",
                            loss_balance)
    );
  GNUNET_break (0 ==
                json_array_append_new (list,
                                       obj));


  return GNUNET_OK;
}


MHD_RESULT
TAH_HISTORIC_DENOMINATION_REVENUE_handler_get (
  struct TAH_RequestHandler *rh,
  struct MHD_Connection *connection,
  void **connection_cls,
  const char *upload_data,
  size_t *upload_data_size,
  const char *const args[])
{
  json_t *ja;
  int64_t limit = -20;
  uint64_t offset;
  enum GNUNET_DB_QueryStatus qs;

  (void) rh;
  (void) connection_cls;
  (void) upload_data;
  (void) upload_data_size;
  if (GNUNET_SYSERR ==
      TAH_plugin->preflight (TAH_plugin->cls))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (
      connection,
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
  ja = json_array ();
  GNUNET_break (NULL != ja);
  qs = TAH_plugin->select_historic_denom_revenue (
    TAH_plugin->cls,
    limit,
    offset,
    &process_historic_denomination_revenue,
    ja);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
    json_decref (ja);
    TALER_LOG_WARNING (
      "Failed to handle GET /historic-denomination-revenue");
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_INTERNAL_SERVER_ERROR,
      TALER_EC_GENERIC_DB_FETCH_FAILED,
      "select_historic_denom_revenue");
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_array_steal (
      "historic-denomination-revenue",
      ja));
}
