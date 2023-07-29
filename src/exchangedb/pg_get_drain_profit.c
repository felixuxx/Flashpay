/*
   This file is part of TALER
   Copyright (C) 2022 Taler Systems SA

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
 * @file exchangedb/pg_get_drain_profit.c
 * @brief Implementation of the get_drain_profit function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_drain_profit.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_get_drain_profit (
  void *cls,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  uint64_t *serial,
  char **account_section,
  char **payto_uri,
  struct GNUNET_TIME_Timestamp *request_timestamp,
  struct TALER_Amount *amount,
  struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("profit_drain_serial_id",
                                  serial),
    GNUNET_PQ_result_spec_string ("account_section",
                                  account_section),
    GNUNET_PQ_result_spec_string ("payto_uri",
                                  payto_uri),
    GNUNET_PQ_result_spec_timestamp ("trigger_date",
                                     request_timestamp),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                 amount),
    GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                          master_sig),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "get_profit_drain",
           "SELECT"
           " profit_drain_serial_id"
           ",account_section"
           ",payto_uri"
           ",trigger_date"
           ",amount"
           ",master_sig"
           " FROM profit_drains"
           " WHERE wtid=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_profit_drain",
                                                   params,
                                                   rs);
}
