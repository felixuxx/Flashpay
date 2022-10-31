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
 * @file pg_get_wire_auditor_account_progress.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_wire_auditor_account_progress.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_get_wire_auditor_account_progress (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const char *account_name,
  struct TALER_AUDITORDB_WireAccountProgressPoint *pp,
  struct TALER_AUDITORDB_BankAccountProgressPoint *bapp)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_string (account_name),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("last_wire_reserve_in_serial_id",
                                  &pp->last_reserve_in_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_wire_wire_out_serial_id",
                                  &pp->last_wire_out_serial_id),
    GNUNET_PQ_result_spec_uint64 ("wire_in_off",
                                  &bapp->in_wire_off),
    GNUNET_PQ_result_spec_uint64 ("wire_out_off",
                                  &bapp->out_wire_off),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "wire_auditor_account_progress_select",
           "SELECT"
           " last_wire_reserve_in_serial_id"
           ",last_wire_wire_out_serial_id"
           ",wire_in_off"
           ",wire_out_off"
           " FROM wire_auditor_account_progress"
           " WHERE master_pub=$1 AND account_name=$2;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "wire_auditor_account_progress_select",
                                                   params,
                                                   rs);
}
