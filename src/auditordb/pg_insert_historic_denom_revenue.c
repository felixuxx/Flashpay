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
 * @file pg_insert_historic_denom_revenue.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_historic_denom_revenue.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_insert_historic_denom_revenue (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_DenominationHashP *denom_pub_hash,
  struct GNUNET_TIME_Timestamp revenue_timestamp,
  const struct TALER_Amount *revenue_balance,
  const struct TALER_Amount *loss_balance)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_timestamp (&revenue_timestamp),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       revenue_balance),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       loss_balance),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_historic_denomination_revenue_insert",
           "INSERT INTO auditor_historic_denomination_revenue"
           "(master_pub"
           ",denom_pub_hash"
           ",revenue_timestamp"
           ",revenue_balance"
           ",loss_balance"
           ") VALUES ($1,$2,$3,$4,$5);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_historic_denomination_revenue_insert",
                                             params);
}
