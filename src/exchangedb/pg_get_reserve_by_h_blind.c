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
 * @file exchangedb/pg_get_reserve_by_h_blind.c
 * @brief Implementation of the get_reserve_by_h_blind function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_reserve_by_h_blind.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_get_reserve_by_h_blind (
  void *cls,
  const struct TALER_BlindedCoinHashP *bch,
  struct TALER_ReservePublicKeyP *reserve_pub,
  uint64_t *reserve_out_serial_id)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (bch),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                          reserve_pub),
    GNUNET_PQ_result_spec_uint64 ("reserve_out_serial_id",
                                  reserve_out_serial_id),
    GNUNET_PQ_result_spec_end
  };
  /* Used in #postgres_get_reserve_by_h_blind() */
  PREPARE (pg,
           "reserve_by_h_blind",
           "SELECT"
           " reserves.reserve_pub"
           ",reserve_out_serial_id"
           " FROM reserves_out"
           " JOIN reserves"
           "   USING (reserve_uuid)"
           " WHERE h_blind_ev=$1"
           " LIMIT 1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "reserve_by_h_blind",
                                                   params,
                                                   rs);
}
