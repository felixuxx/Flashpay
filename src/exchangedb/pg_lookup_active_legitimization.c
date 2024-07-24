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
 * @file exchangedb/pg_lookup_pending_legitimization.c
 * @brief Implementation of the lookup_pending_legitimization function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_active_legitimization.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_lookup_active_legitimization (
  void *cls,
  uint64_t legitimization_process_serial_id,
  uint32_t *measure_index,
  json_t **jmeasures)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&legitimization_process_serial_id),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_json (
      "jmeasures",
      jmeasures),
    GNUNET_PQ_result_spec_uint32 (
      "measure_index",
      measure_index),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "lookup_active_legitimization",
           "SELECT "
           " lm.jmeasures"
           ",lp.measure_index"
           " FROM legitimization_processes lp"
           " JOIN legitimization_measures lm"
           "   USING (legitimization_measure_serial_id)"
           " WHERE lp.legitimization_process_serial_id=$1"
           "   AND NOT lm.is_finished;");
  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "lookup_active_legitimization",
    params,
    rs);
}
