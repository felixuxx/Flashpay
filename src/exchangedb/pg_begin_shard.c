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
 * @file exchangedb/pg_begin_shard.c
 * @brief Implementation of the begin_shard function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_begin_shard.h"
#include "pg_helper.h"
#include "pg_start.h"
#include "pg_rollback.h"
#include "pg_commit.h"

enum GNUNET_DB_QueryStatus
TEH_PG_begin_shard (void *cls,
                      const char *job_name,
                      struct GNUNET_TIME_Relative delay,
                      uint64_t shard_size,
                      uint64_t *start_row,
                      uint64_t *end_row)
{
  struct PostgresClosure *pg = cls;

  for (unsigned int retries = 0; retries<10; retries++)
  {
    if (GNUNET_OK !=
        TEH_PG_start (pg,
                        "begin_shard"))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }

    {
      struct GNUNET_TIME_Absolute past;
      enum GNUNET_DB_QueryStatus qs;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_string (job_name),
        GNUNET_PQ_query_param_absolute_time (&past),
        GNUNET_PQ_query_param_end
      };
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_uint64 ("start_row",
                                      start_row),
        GNUNET_PQ_result_spec_uint64 ("end_row",
                                      end_row),
        GNUNET_PQ_result_spec_end
      };

      past = GNUNET_TIME_absolute_get ();

      PREPARE (pg,
               "get_open_shard",
               "SELECT"
               " start_row"
               ",end_row"
               " FROM work_shards"
               " WHERE job_name=$1"
               "   AND completed=FALSE"
               "   AND last_attempt<$2"
               " ORDER BY last_attempt ASC"
               " LIMIT 1;");

      qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                     "get_open_shard",
                                                     params,
                                                     rs);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        TEH_PG_rollback (pg);
        return qs;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        TEH_PG_rollback (pg);
        continue;
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        {
          enum GNUNET_DB_QueryStatus qs;
          struct GNUNET_TIME_Absolute now;
          struct GNUNET_PQ_QueryParam params[] = {
            GNUNET_PQ_query_param_string (job_name),
            GNUNET_PQ_query_param_absolute_time (&now),
            GNUNET_PQ_query_param_uint64 (start_row),
            GNUNET_PQ_query_param_uint64 (end_row),
            GNUNET_PQ_query_param_end
          };

          now = GNUNET_TIME_relative_to_absolute (delay);


          PREPARE (pg,
                   "reclaim_shard",
                   "UPDATE work_shards"
                   " SET last_attempt=$2"
                   " WHERE job_name=$1"
                   "   AND start_row=$3"
                   "   AND end_row=$4");

          qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                                   "reclaim_shard",
                                                   params);
          switch (qs)
          {
          case GNUNET_DB_STATUS_HARD_ERROR:
            GNUNET_break (0);
            TEH_PG_rollback (pg);
            return qs;
          case GNUNET_DB_STATUS_SOFT_ERROR:
            TEH_PG_rollback (pg);
            continue;
          case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
            goto commit;
          case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
            GNUNET_break (0); /* logic error, should be impossible */
            TEH_PG_rollback (pg);
            return GNUNET_DB_STATUS_HARD_ERROR;
          }
        }
        break; /* actually unreachable */
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        break; /* continued below */
      }
    } /* get_open_shard */

    /* No open shard, find last 'end_row' */
    {
      enum GNUNET_DB_QueryStatus qs;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_string (job_name),
        GNUNET_PQ_query_param_end
      };
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_uint64 ("end_row",
                                      start_row),
        GNUNET_PQ_result_spec_end
      };

      PREPARE (pg,
               "get_last_shard",
               "SELECT"
               " end_row"
               " FROM work_shards"
               " WHERE job_name=$1"
               " ORDER BY end_row DESC"
               " LIMIT 1;");
      qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                     "get_last_shard",
                                                     params,
                                                     rs);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        TEH_PG_rollback (pg);
        return qs;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        TEH_PG_rollback (pg);
        continue;
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        break;
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        *start_row = 0; /* base-case: no shards yet */
        break; /* continued below */
      }
      *end_row = *start_row + shard_size;
    } /* get_last_shard */

    /* Claim fresh shard */
    {
      enum GNUNET_DB_QueryStatus qs;
      struct GNUNET_TIME_Absolute now;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_string (job_name),
        GNUNET_PQ_query_param_absolute_time (&now),
        GNUNET_PQ_query_param_uint64 (start_row),
        GNUNET_PQ_query_param_uint64 (end_row),
        GNUNET_PQ_query_param_end
      };

      now = GNUNET_TIME_relative_to_absolute (delay);
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Trying to claim shard (%llu-%llu]\n",
                  (unsigned long long) *start_row,
                  (unsigned long long) *end_row);

      PREPARE (pg,
               "claim_next_shard",
               "INSERT INTO work_shards"
               "(job_name"
               ",last_attempt"
               ",start_row"
               ",end_row"
               ") VALUES "
               "($1, $2, $3, $4);");
      qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                               "claim_next_shard",
                                               params);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        TEH_PG_rollback (pg);
        return qs;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        TEH_PG_rollback (pg);
        continue;
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        /* continued below */
        break;
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        /* someone else got this shard already,
           try again */
        TEH_PG_rollback (pg);
        continue;
      }
    } /* claim_next_shard */

    /* commit */
commit:
    {
      enum GNUNET_DB_QueryStatus qs;

      qs = TEH_PG_commit (pg);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        TEH_PG_rollback (pg);
        return qs;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        TEH_PG_rollback (pg);
        continue;
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
      }
    }
  } /* retry 'for' loop */
  return GNUNET_DB_STATUS_SOFT_ERROR;
}
