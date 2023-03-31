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
 * @file exchangedb/pg_begin_revolving_shard.c
 * @brief Implementation of the begin_revolving_shard function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_begin_revolving_shard.h"
#include "pg_commit.h"
#include "pg_helper.h"
#include "pg_start.h"
#include "pg_rollback.h"

enum GNUNET_DB_QueryStatus
TEH_PG_begin_revolving_shard (void *cls,
                              const char *job_name,
                              uint32_t shard_size,
                              uint32_t shard_limit,
                              uint32_t *start_row,
                              uint32_t *end_row)
{
  struct PostgresClosure *pg = cls;

  GNUNET_assert (shard_limit <= 1U + (uint32_t) INT_MAX);
  GNUNET_assert (shard_limit > 0);
  GNUNET_assert (shard_size > 0);
  for (unsigned int retries = 0; retries<3; retries++)
  {
    if (GNUNET_OK !=
        TEH_PG_start (pg,
                      "begin_revolving_shard"))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }

    /* First, find last 'end_row' */
    {
      enum GNUNET_DB_QueryStatus qs;
      uint32_t last_end;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_string (job_name),
        GNUNET_PQ_query_param_end
      };
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_uint32 ("end_row",
                                      &last_end),
        GNUNET_PQ_result_spec_end
      };
      /* Used in #postgres_begin_revolving_shard() */
      PREPARE (pg,
               "get_last_revolving_shard",
               "SELECT"
               " end_row"
               " FROM revolving_work_shards"
               " WHERE job_name=$1"
               " ORDER BY end_row DESC"
               " LIMIT 1;");
      qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                     "get_last_revolving_shard",
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
        *start_row = 1U + last_end;
        break;
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        *start_row = 0; /* base-case: no shards yet */
        break; /* continued below */
      }
    } /* get_last_shard */

    if (*start_row < shard_limit)
    {
      /* Claim fresh shard */
      enum GNUNET_DB_QueryStatus qs;
      struct GNUNET_TIME_Absolute now;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_string (job_name),
        GNUNET_PQ_query_param_absolute_time (&now),
        GNUNET_PQ_query_param_uint32 (start_row),
        GNUNET_PQ_query_param_uint32 (end_row),
        GNUNET_PQ_query_param_end
      };

      *end_row = GNUNET_MIN (shard_limit,
                             *start_row + shard_size - 1);
      now = GNUNET_TIME_absolute_get ();
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Trying to claim shard %llu-%llu\n",
                  (unsigned long long) *start_row,
                  (unsigned long long) *end_row);

      /* Used in #postgres_claim_revolving_shard() */
      PREPARE (pg,
               "create_revolving_shard",
               "INSERT INTO revolving_work_shards"
               "(job_name"
               ",last_attempt"
               ",start_row"
               ",end_row"
               ",active"
               ") VALUES "
               "($1, $2, $3, $4, TRUE);");
      qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                               "create_revolving_shard",
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
        /* continued below (with commit) */
        break;
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        /* someone else got this shard already,
           try again */
        TEH_PG_rollback (pg);
        continue;
      }
    } /* end create fresh reovlving shard */
    else
    {
      /* claim oldest existing shard */
      enum GNUNET_DB_QueryStatus qs;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_string (job_name),
        GNUNET_PQ_query_param_end
      };
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_uint32 ("start_row",
                                      start_row),
        GNUNET_PQ_result_spec_uint32 ("end_row",
                                      end_row),
        GNUNET_PQ_result_spec_end
      };
      /* Used in #postgres_begin_revolving_shard() */
      PREPARE (pg,
               "get_open_revolving_shard",
               "SELECT"
               " start_row"
               ",end_row"
               " FROM revolving_work_shards"
               " WHERE job_name=$1"
               "   AND active=FALSE"
               " ORDER BY last_attempt ASC"
               " LIMIT 1;");
      qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                     "get_open_revolving_shard",
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
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        /* no open shards available */
        TEH_PG_rollback (pg);
        return qs;
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        {
          enum GNUNET_DB_QueryStatus qs;
          struct GNUNET_TIME_Timestamp now;
          struct GNUNET_PQ_QueryParam params[] = {
            GNUNET_PQ_query_param_string (job_name),
            GNUNET_PQ_query_param_timestamp (&now),
            GNUNET_PQ_query_param_uint32 (start_row),
            GNUNET_PQ_query_param_uint32 (end_row),
            GNUNET_PQ_query_param_end
          };

          now = GNUNET_TIME_timestamp_get ();

          /* Used in #postgres_begin_revolving_shard() */
          PREPARE (pg,
                   "reclaim_revolving_shard",
                   "UPDATE revolving_work_shards"
                   " SET last_attempt=$2"
                   "    ,active=TRUE"
                   " WHERE job_name=$1"
                   "   AND start_row=$3"
                   "   AND end_row=$4");
          qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                                   "reclaim_revolving_shard",
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
            break; /* continue with commit */
          case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
            GNUNET_break (0); /* logic error, should be impossible */
            TEH_PG_rollback (pg);
            return GNUNET_DB_STATUS_HARD_ERROR;
          }
        }
        break; /* continue with commit */
      }
    } /* end claim oldest existing shard */

    /* commit */
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
