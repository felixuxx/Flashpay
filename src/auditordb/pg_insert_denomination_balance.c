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
 * @file pg_insert_denomination_balance.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_denomination_balance.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_insert_denomination_balance (
  void *cls,
  const struct TALER_DenominationHashP *denom_pub_hash,
  const struct TALER_AUDITORDB_DenominationCirculationData *dcd)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &dcd->denom_balance),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &dcd->denom_loss),
    GNUNET_PQ_query_param_uint64 (&dcd->num_issued),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &dcd->denom_risk),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &dcd->recoup_loss),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_denomination_pending_insert",
           "INSERT INTO auditor_denomination_pending "
           "(denom_pub_hash"
           ",denom_balance"
           ",denom_loss"
           ",num_issued"
           ",denom_risk"
           ",recoup_loss"
           ") VALUES ("
           "$1,$2,$3,$4,$5,$6"
           ");");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_denomination_pending_insert",
                                             params);
}
