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
 * @file pg_get_predicted_balance.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_predicted_balance.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_get_predicted_balance (void *cls,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              struct TALER_Amount *balance,
                              struct TALER_Amount *drained)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("balance",
                                 balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("drained",
                                 drained),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "auditor_predicted_result_select",
           "SELECT"
           " balance"
           ",drained"
           " FROM auditor_predicted_result"
           " WHERE master_pub=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_predicted_result_select",
                                                   params,
                                                   rs);
}
