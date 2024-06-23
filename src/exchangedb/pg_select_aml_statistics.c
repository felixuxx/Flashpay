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
/**
 * @file exchangedb/pg_select_aml_statistics.c
 * @brief Implementation of the select_aml_statistics function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_aml_statistics.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_select_aml_statistics (
  void *cls,
  const char *name,
  struct GNUNET_TIME_Timestamp start_date,
  struct GNUNET_TIME_Timestamp end_date,
  uint64_t *cnt)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (name),
    GNUNET_PQ_query_param_timestamp (&start_date),
    GNUNET_PQ_query_param_timestamp (&end_date),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("count",
                                  cnt),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "select_aml_statistics",
           "SELECT "
           " COUNT(*) AS count"
           " FROM kyc_events"
           " WHERE event_type=$1"
           "   AND event_timestamp >= $1"
           "   AND event_timestamp < $2;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_aml_statistics",
                                                   params,
                                                   rs);
}
