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

#include "pg_insert_denomination_pending.h"

enum GNUNET_DB_QueryStatus
TAH_PG_insert_denomination_pending (
  void *cls,
  const struct TALER_AUDITORDB_DenominationPending *dc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&dc->denom_pub_hash),
    TALER_PQ_query_param_amount (pg->conn, &dc->denom_balance),
    TALER_PQ_query_param_amount (pg->conn, &dc->denom_loss),
    GNUNET_PQ_query_param_uint64 (&dc->num_issued),
    TALER_PQ_query_param_amount (pg->conn, &dc->denom_risk),
    TALER_PQ_query_param_amount (pg->conn, &dc->recoup_loss),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_denomination_pending_insert",
           "INSERT INTO auditor_denomination_pending "
           "( denom_pub_hash,"
           " denom_balance,"
           " denom_loss,"
           " num_issued,"
           " denom_risk,"
           " recoup_loss"
           ") VALUES ($1,$2,$3,$4,$5,$6)"
           " ON CONFLICT (denom_pub_hash) UPDATE"
           " SET denom_balance = excluded.denom_balance, "
           " denom_loss = excluded.denom_loss,"
           " num_issued = excluded.num_issued,"
           " denom_risk = excluded.denom_risk,"
           " recoup_loss = excluded.recoup_loss,"
           " suppressed = false;"
           );
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_denomination_pending_insert",
                                             params);
}
