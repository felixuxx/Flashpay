/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

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
 * @file auditordb/pg_get_progress_points.c
 * @brief Implementation of the get_progress_points function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_progress_points.h"
#include "pg_helper.h"


struct ProgressContext
{

  /**
   * Function to call for each progress point.
   */
  TALER_AUDITORDB_ProgressPointsCallback cb;

  /**
   * Closure for @e cb
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Query status to return.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Helper function for #TAH_PG_get_progress_points().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct ProgressContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
progress_cb (void *cls,
             PGresult *result,
             unsigned int num_results)
{
  struct ProgressContext *dcc = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_AUDITORDB_Progress dc;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_string ("progress_key",
                                    &dc.progress_key),
      GNUNET_PQ_result_spec_uint64 ("progress_offset",
                                    &dc.progress_offset),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_GenericReturnValue rval;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      dcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    dcc->qs = i + 1;
    rval = dcc->cb (dcc->cb_cls,
                    &dc);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != rval)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TAH_PG_get_progress_points (
  void *cls,
  const char *progress_key,
  TALER_AUDITORDB_ProgressPointsCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    NULL == progress_key
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_string (progress_key),
    GNUNET_PQ_query_param_end
  };
  struct ProgressContext dcc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "auditor_progress_points_get",
           "SELECT"
           " progress_key"
           ",progress_offset"
           " FROM auditor_progress"
           " WHERE ($1::TEXT IS NULL OR progress_key = $1)"
           );
  qs = GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    "auditor_progress_points_get",
    params,
    &progress_cb,
    &dcc);
  if (qs > 0)
    return dcc.qs;
  GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
  return qs;
}
