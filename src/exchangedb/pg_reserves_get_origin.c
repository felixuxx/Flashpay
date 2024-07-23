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
 * @file exchangedb/pg_reserves_get_origin.c
 * @brief Implementation of the reserves_get_origin function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_reserves_get_origin.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_reserves_get_origin (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct TALER_PaytoHashP *h_payto,
  char **payto_uri)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type (
      "wire_source_h_payto",
      h_payto),
    GNUNET_PQ_result_spec_string (
      "payto_uri",
      payto_uri),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "get_h_wire_source_of_reserve",
           "SELECT"
           " wire_source_h_payto"
           ",payto_uri"
           " FROM reserves_in rt"
           " JOIN wire_targets wt"
           "   ON (rt.wire_source_h_payto = wt.wire_target_h_payto)"
           " WHERE reserve_pub=$1");
  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "get_h_wire_source_of_reserve",
    params,
    rs);
}
