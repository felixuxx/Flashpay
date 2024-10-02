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
 * @file exchangedb/pg_insert_active_legitimization_measure.c
 * @brief Implementation of the insert_active_legitimization_measure function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_active_legitimization_measure.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_active_legitimization_measure (
  void *cls,
  const struct TALER_AccountAccessTokenP *access_token,
  const json_t *jmeasures,
  uint64_t *legitimization_measure_serial_id)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Timestamp now
    = GNUNET_TIME_timestamp_get ();
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (access_token),
    GNUNET_PQ_query_param_timestamp (&now),
    TALER_PQ_query_param_json (jmeasures),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("out_legitimization_measure_serial_id",
                                  legitimization_measure_serial_id),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "do_insert_active_legitimization_measure",
           "SELECT"
           " out_legitimization_measure_serial_id"
           " FROM exchange_do_insert_active_legitimization_measure"
           "($1, $2, $3);");
  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "do_insert_active_legitimization_measure",
    params,
    rs);
}
