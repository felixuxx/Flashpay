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
                          char **payto_uri)
{
  static int choose_mode = -2;
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
                                  payto_uri),
    GNUNET_PQ_result_spec_end
  };
  const char *query;

  if (-2 == choose_mode)
  {
    const char *mode = getenv ("TALER_POSTGRES_GET_READY_LOGIC");
    char dummy;

    if ( (NULL==mode) ||
         (1 != sscanf (mode,
                       "%d%c",
                       &choose_mode,
                       &dummy)) )
    {
      if (NULL != mode)
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Bad mode `%s' specified\n",
                    mode);
      choose_mode = 0;
    }
  }
  switch (choose_mode)
  {
  case 0:
    query = "deposits_get_ready-v5";
    PREPARE (pg,
             query,
             "SELECT"
             " payto_uri"
             ",merchant_pub"
             " FROM deposits dep"
             " JOIN wire_targets wt"
             "   USING (wire_target_h_payto)"
             " WHERE NOT (done OR policy_blocked)"
             "   AND dep.wire_deadline<=$1"
             "   AND dep.shard >= $2"
             "   AND dep.shard <= $3"
             " ORDER BY "
             "   dep.wire_deadline ASC"
             "  ,dep.shard ASC"
             " LIMIT 1;");
    break;
  case 1:
    query = "deposits_get_ready-v6";
    PREPARE (pg,
             query,
             "WITH rc AS MATERIALIZED ("
             " SELECT"
             " merchant_pub"
             ",wire_target_h_payto"
             " FROM deposits"
             " WHERE NOT (done OR policy_blocked)"
             "   AND wire_deadline<=$1"
             "   AND shard >= $2"
             "   AND shard <= $3"
             " ORDER BY wire_deadline ASC"
             "  ,shard ASC"
             "  LIMIT 1"
             ")"
             "SELECT"
             " wt.payto_uri"
             ",rc.merchant_pub"
             " FROM wire_targets wt"
             " JOIN rc"
             "   USING (wire_target_h_payto);");
    break;
  default:
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   query,
                                                   params,
                                                   rs);
}
