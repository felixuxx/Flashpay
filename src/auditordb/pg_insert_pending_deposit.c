/*
   This file is part of TALER
   Copyright (C) 2023 Taler Systems SA

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
 * @file auditordb/pg_insert_pending_deposit.c
 * @brief Implementation of the insert_pending_deposit function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_pending_deposit.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_insert_pending_deposit (
  void *cls,
  uint64_t batch_deposit_serial_id,
  const struct TALER_FullPaytoHashP *wire_target_h_payto,
  const struct TALER_Amount *total_amount,
  struct GNUNET_TIME_Timestamp deadline)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (pg->conn,
                                 total_amount),
    GNUNET_PQ_query_param_auto_from_type (wire_target_h_payto),
    GNUNET_PQ_query_param_uint64 (&batch_deposit_serial_id),
    GNUNET_PQ_query_param_timestamp (&deadline),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_insert_pending_deposit",
           "INSERT INTO auditor_pending_deposits "
           "(total_amount"
           ",wire_target_h_payto"
           ",batch_deposit_serial_id"
           ",deadline"
           ") VALUES ($1,$2,$3,$4);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_insert_pending_deposit",
                                             params);
}
