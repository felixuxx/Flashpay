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
 * @file exchangedb/pg_get_ready_deposit.c
 * @brief Implementation of the get_ready_deposit function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_ready_deposit.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_get_ready_deposit (void *cls,
                            uint64_t start_shard_row,
                            uint64_t end_shard_row,
                            struct TALER_MerchantPublicKeyP *merchant_pub,
                            char **payto_uri)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now = {0};
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_uint64 (&start_shard_row),
    GNUNET_PQ_query_param_uint64 (&end_shard_row),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                          merchant_pub),
    GNUNET_PQ_result_spec_string ("payto_uri",
                                  payto_uri),
    GNUNET_PQ_result_spec_end
  };

  now = GNUNET_TIME_absolute_round_down (GNUNET_TIME_absolute_get (),
                                         pg->aggregator_shift);
  GNUNET_assert (start_shard_row < end_shard_row);
  GNUNET_assert (end_shard_row <= INT32_MAX);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Finding ready deposits by deadline %s (%llu)\n",
              GNUNET_TIME_absolute2s (now),
              (unsigned long long) now.abs_value_us);


    /* Used in #postgres_get_ready_deposit() */
  PREPARE (pg,
           "deposits_get_ready",
           "SELECT"
           " payto_uri"
           ",merchant_pub"
           " FROM deposits_by_ready dbr"
           "  JOIN deposits dep"
           "    ON (dbr.coin_pub = dep.coin_pub AND"
           "        dbr.deposit_serial_id = dep.deposit_serial_id)"
           "  JOIN wire_targets wt"
           "    USING (wire_target_h_payto)"
           " WHERE dbr.wire_deadline<=$1"
           "   AND dbr.shard >= $2"
           "   AND dbr.shard <= $3"
           " ORDER BY "
           "   dbr.wire_deadline ASC"
           "  ,dbr.shard ASC"
           " LIMIT 1;");



  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "deposits_get_ready",
                                                   params,
                                                   rs);
}






