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
 * @file exchangedb/pg_count_known_coins.c
 * @brief Implementation of the count_known_coins function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_count_known_coins.h"
#include "pg_helper.h"

long long
TEH_PG_count_known_coins (void *cls,
                            const struct
                            TALER_DenominationHashP *denom_pub_hash)
{
  struct PostgresClosure *pg = cls;
  uint64_t count;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("count",
                                  &count),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;


  PREPARE (pg,
           "count_known_coins",
           "SELECT"
           " COUNT(*) AS count"
           " FROM known_coins"
           " WHERE denominations_serial="
           "  (SELECT denominations_serial"
           "    FROM denominations"
           "    WHERE denom_pub_hash=$1);");
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "count_known_coins",
                                                 params,
                                                 rs);
  if (0 > qs)
    return (long long) qs;
  return (long long) count;
}
