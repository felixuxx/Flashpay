/*
   This file is part of TALER
   Copyright (C) 2022-2023 Taler Systems SA

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
 * @file pg_get_wire_auditor_progress.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_wire_auditor_progress.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_get_wire_auditor_progress (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct TALER_AUDITORDB_WireProgressPoint *pp)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("last_reserve_close_uuid",
                                  &pp->last_reserve_close_uuid),
    GNUNET_PQ_result_spec_uint64 ("last_batch_deposit_uuid",
                                  &pp->last_batch_deposit_uuid),
    GNUNET_PQ_result_spec_uint64 ("last_aggregation_serial",
                                  &pp->last_aggregation_serial),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "wire_auditor_progress_select",
           "SELECT"
           " last_reserve_close_uuid"
           ",last_batch_deposit_uuid"
           ",last_aggregation_serial"
           " FROM wire_auditor_progress"
           " WHERE master_pub=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "wire_auditor_progress_select",
                                                   params,
                                                   rs);
}
