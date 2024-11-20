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
 * @file exchangedb/pg_get_reserve_balance.c
 * @brief Implementation of the get_reserve_balance function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_reserve_balance.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_get_reserve_balance (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct TALER_Amount *balance,
  struct TALER_FullPayto *origin_account)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_amount ("current_balance",
                                 pg->currency,
                                 balance),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_string ("payto_uri",
                                    &origin_account->full_payto),
      NULL),
    GNUNET_PQ_result_spec_end
  };

  origin_account->full_payto = NULL;
  PREPARE (pg,
           "get_reserve_balance",
           "SELECT"
           "  r.current_balance"
           " ,wt.payto_uri"
           " FROM reserves r"
           " LEFT JOIN reserves_in ri"
           "   USING (reserve_pub)"
           " LEFT JOIN wire_targets wt"
           "   ON (wt.wire_target_h_payto = ri.wire_source_h_payto)"
           " WHERE r.reserve_pub=$1"
           " LIMIT 1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_reserve_balance",
                                                   params,
                                                   rs);
}
