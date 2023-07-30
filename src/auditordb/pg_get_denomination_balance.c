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
 * @file pg_get_denomination_balance.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_denomination_balance.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_get_denomination_balance (
  void *cls,
  const struct TALER_DenominationHashP *denom_pub_hash,
  struct TALER_AUDITORDB_DenominationCirculationData *dcd)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("denom_balance",
                                 &dcd->denom_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("denom_loss",
                                 &dcd->denom_loss),
    TALER_PQ_RESULT_SPEC_AMOUNT ("denom_risk",
                                 &dcd->denom_risk),
    TALER_PQ_RESULT_SPEC_AMOUNT ("recoup_loss",
                                 &dcd->recoup_loss),
    GNUNET_PQ_result_spec_uint64 ("num_issued",
                                  &dcd->num_issued),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "auditor_denomination_pending_select",
           "SELECT"
           " denom_balance"
           ",denom_loss"
           ",num_issued"
           ",denom_risk"
           ",recoup_loss"
           " FROM auditor_denomination_pending"
           " WHERE denom_pub_hash=$1");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_denomination_pending_select",
                                                   params,
                                                   rs);
}
