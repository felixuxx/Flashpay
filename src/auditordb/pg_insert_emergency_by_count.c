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
#include "taler_pq_lib.h"
#include "pg_helper.h"


#include "pg_insert_emergency_by_count.h"

enum GNUNET_DB_QueryStatus
TAH_PG_insert_emergency_by_count (
  void *cls,
  const struct TALER_AUDITORDB_EmergenciesByCount *dc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {

    GNUNET_PQ_query_param_auto_from_type (&dc->denompub_h),
    GNUNET_PQ_query_param_int64 (&dc->num_issued),
    GNUNET_PQ_query_param_int64 (&dc->num_known),
    TALER_PQ_query_param_amount (pg->conn, &dc->risk),
    GNUNET_PQ_query_param_absolute_time (&dc->start),
    GNUNET_PQ_query_param_absolute_time (&dc->deposit_end),
    TALER_PQ_query_param_amount (pg->conn, &dc->value),

    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_emergency_by_count_insert",
           "INSERT INTO auditor_emergency_by_count "
           "(denompub_h"
           ",num_issued"
           ",num_known"
           ",risk"
           ",start"
           ",deposit_end"
           ",value"
           ") VALUES ($1,$2,$3,$4,$5,$6,$7);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_emergency_by_count_insert",
                                             params);
}
