/*
   This file is part of TALER
   Copyright (C) 2022, 2023 Taler Systems SA

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
                          struct TALER_FullPayto *payto_uri)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now
    = GNUNET_TIME_absolute_get ();
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
                                  &payto_uri->full_payto),
    GNUNET_PQ_result_spec_end
  };
  const char *query = "deposits_get_ready";

  PREPARE (pg,
           query,
           "SELECT"
           " wts.payto_uri"
           ",bdep.merchant_pub"
           " FROM batch_deposits bdep"
           " JOIN wire_targets wts"
           "   USING (wire_target_h_payto)"
           " WHERE NOT (bdep.done OR bdep.policy_blocked)"
           "   AND bdep.wire_deadline<=$1"
           "   AND bdep.shard >= $2"
           "   AND bdep.shard <= $3"
           " ORDER BY "
           "   bdep.wire_deadline ASC"
           "  ,bdep.shard ASC"
           " LIMIT 1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   query,
                                                   params,
                                                   rs);
}
