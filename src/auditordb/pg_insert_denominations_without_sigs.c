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

#include "pg_insert_denominations_without_sigs.h"

enum GNUNET_DB_QueryStatus
TAH_PG_insert_denominations_without_sigs (
  void *cls,
  const struct TALER_AUDITORDB_DenominationsWithoutSigs *dc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {

    GNUNET_PQ_query_param_auto_from_type (&dc->denompub_h),
    TALER_PQ_query_param_amount (pg->conn, &dc->value),
    GNUNET_PQ_query_param_absolute_time (&dc->start_time),
    GNUNET_PQ_query_param_absolute_time (&dc->end_time),


    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_denominations_without_sigs_insert",
           "INSERT INTO auditor_denominations_without_sigs "
           "(denompub_h,"
           " value,"
           " start_time,"
           " end_time"
           ") VALUES ($1,$2,$3,$4)"
           " ON CONFLICT (denompub_h) DO UPDATE"
           " SET value = excluded.value,"
           " start_time = excluded.start_time,"
           " end_time = excluded.end_time,"
           " suppressed = false"
           );
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_denominations_without_sigs_insert",
                                             params);
}
