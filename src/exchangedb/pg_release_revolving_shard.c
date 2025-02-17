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
 * @file exchangedb/pg_release_revolving_shard.c
 * @brief Implementation of the release_revolving_shard function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_release_revolving_shard.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_release_revolving_shard (void *cls,
                                const char *job_name,
                                uint32_t start_row,
                                uint32_t end_row)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (job_name),
    GNUNET_PQ_query_param_uint32 (&start_row),
    GNUNET_PQ_query_param_uint32 (&end_row),
    GNUNET_PQ_query_param_end
  };

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Releasing revolving shard %s %u-%u\n",
              job_name,
              (unsigned int) start_row,
              (unsigned int) end_row);


  PREPARE (pg,
           "release_revolving_shard",
           "UPDATE revolving_work_shards"
           " SET active=FALSE"
           " WHERE job_name=$1"
           "   AND start_row=$2"
           "   AND end_row=$3");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "release_revolving_shard",
                                             params);
}
