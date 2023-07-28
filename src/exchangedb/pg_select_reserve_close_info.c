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
 * @file pg_select_reserve_close_info.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_reserve_close_info.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_select_reserve_close_info (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct TALER_Amount *balance,
  char **payto_uri)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_amount_tuple ("current_balance",
                                       pg->currency,
                                       balance),
    GNUNET_PQ_result_spec_string ("payto_uri",
                                  payto_uri),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "select_reserve_close_info",
           "SELECT "
           " r.current_balance"
           ",wt.payto_uri"
           " FROM reserves r"
           " LEFT JOIN reserves_in ri USING (reserve_pub)"
           " LEFT JOIN wire_targets wt ON (ri.wire_source_h_payto = wt.wire_target_h_payto)"
           " WHERE reserve_pub=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_reserve_close_info",
                                                   params,
                                                   rs);
}
