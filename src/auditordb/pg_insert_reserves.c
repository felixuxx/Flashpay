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

#include "pg_insert_reserves.h"

enum GNUNET_DB_QueryStatus
TAH_PG_insert_reserves (
  void *cls,
  const struct TALER_AUDITORDB_Reserves *dc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {

    GNUNET_PQ_query_param_auto_from_type (&dc->reserve_pub),
    TALER_PQ_query_param_amount (pg->conn, &dc->reserve_balance),
    TALER_PQ_query_param_amount (pg->conn, &dc->reserve_loss),
    TALER_PQ_query_param_amount (pg->conn, &dc->withdraw_fee_balance),
    TALER_PQ_query_param_amount (pg->conn, &dc->close_fee_balance),
    TALER_PQ_query_param_amount (pg->conn, &dc->purse_fee_balance),
    TALER_PQ_query_param_amount (pg->conn, &dc->open_fee_balance),
    TALER_PQ_query_param_amount (pg->conn, &dc->history_fee_balance),
    GNUNET_PQ_query_param_absolute_time (&dc->expiration_date),
    GNUNET_PQ_query_param_string (dc->origin_account),


    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_reserves_insert",
           "INSERT INTO auditor_reserves "
           " ( reserve_pub,"
           " reserve_balance,"
           " reserve_loss,"
           " withdraw_fee_balance,"
           " close_fee_balance,"
           " purse_fee_balance,"
           " open_fee_balance,"
           " history_fee_balance,"
           " expiration_date,"
           " origin_account"
           ") VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10);"
           );
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_reserves_insert",
                                             params);
}
