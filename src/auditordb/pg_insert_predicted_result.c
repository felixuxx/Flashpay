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
 * @file pg_insert_predicted_result.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_predicted_result.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_insert_predicted_result (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_Amount *balance,
  const struct TALER_Amount *drained)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       balance),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       drained),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_predicted_result_insert",
           "INSERT INTO auditor_predicted_result"
           "(master_pub"
           ",balance"
           ",drained"
           ") VALUES ($1,$2,$3);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_predicted_result_insert",
                                             params);
}
