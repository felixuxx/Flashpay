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
 * @file pg_insert_historic_reserve_revenue.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_historic_reserve_revenue.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TAH_PG_insert_historic_reserve_revenue (
  void *cls,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  const struct TALER_Amount *reserve_profits)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&start_time),
    GNUNET_PQ_query_param_timestamp (&end_time),
    TALER_PQ_query_param_amount (pg->conn,
                                 reserve_profits),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_historic_reserve_summary_insert",
           "INSERT INTO auditor_historic_reserve_summary"
           "(start_date"
           ",end_date"
           ",reserve_profits"
           ") VALUES ($1,$2,$3);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_historic_reserve_summary_insert",
                                             params);
}
