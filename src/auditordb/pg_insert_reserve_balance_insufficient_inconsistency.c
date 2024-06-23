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

#include "pg_insert_reserve_balance_insufficient_inconsistency.h"

enum GNUNET_DB_QueryStatus
TAH_PG_insert_reserve_balance_insufficient_inconsistency (
  void *cls,
  const struct TALER_AUDITORDB_ReserveBalanceInsufficientInconsistency *dc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {

    GNUNET_PQ_query_param_auto_from_type (&dc->reserve_pub),
    GNUNET_PQ_query_param_bool (dc->inconsistency_gain),
    TALER_PQ_query_param_amount (pg->conn, &dc->inconsistency_amount),

    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_reserve_balance_insufficient_inconsistency_insert",
           "INSERT INTO auditor_reserve_balance_insufficient_inconsistency "
           "(reserve_pub"
           ",inconsistency_gain"
           ",inconsistency_amount"
           ") VALUES ($1,$2,$3);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_reserve_balance_insufficient_inconsistency_insert",
                                             params);
}
