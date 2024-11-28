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
 * @file exchangedb/pg_select_aml_measures.c
 * @brief Implementation of the select_aml_measures function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_aml_measures.h"
#include "pg_helper.h"


/**
 * Closure for #handle_aml_result.
 */
struct LegiMeasureResultContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_LegitimizationMeasureCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to #GNUNET_SYSERR on serious errors.
   */
  enum GNUNET_GenericReturnValue status;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.  Helper function
 * for #TEH_PG_select_aml_measures().
 *
 * @param cls closure of type `struct LegiMeasureResultContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
handle_aml_result (void *cls,
                   PGresult *result,
                   unsigned int num_results)
{
  struct LegiMeasureResultContext *ctx = cls;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_NormalizedPaytoHashP h_payto;
    uint64_t rowid;
    struct GNUNET_TIME_Timestamp start_time;
    json_t *jmeasures = NULL;
    bool is_finished;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("legitimization_measure_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("h_normalized_payto",
                                            &h_payto),
      GNUNET_PQ_result_spec_timestamp ("start_time",
                                       &start_time),
      TALER_PQ_result_spec_json ("jmeasures",
                                 &jmeasures),
      GNUNET_PQ_result_spec_bool ("is_finished",
                                  &is_finished),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->status = GNUNET_SYSERR;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &h_payto,
             start_time,
             jmeasures,
             is_finished,
             rowid);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_aml_measures (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  enum TALER_EXCHANGE_YesNoAll finished_only,
  uint64_t offset,
  int64_t limit,
  TALER_EXCHANGEDB_LegitimizationMeasureCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  uint64_t ulimit = (limit > 0) ? limit : -limit;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_bool (NULL == h_payto),
    NULL == h_payto
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_bool ((TALER_EXCHANGE_YNA_ALL ==
                                 finished_only)),
    GNUNET_PQ_query_param_bool ((TALER_EXCHANGE_YNA_YES ==
                                 finished_only)),
    GNUNET_PQ_query_param_uint64 (&offset),
    GNUNET_PQ_query_param_uint64 (&ulimit),
    GNUNET_PQ_query_param_end
  };
  struct LegiMeasureResultContext ctx = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;
  const char *stmt = (limit > 0)
    ? "select_aml_measures_inc"
    : "select_aml_measures_dec";

  PREPARE (pg,
           "select_aml_measures_inc",
           "SELECT"
           " lm.legitimization_measure_serial_id"
           ",wt.h_normalized_payto"
           ",lm.jmeasures"
           ",lm.start_time"
           ",lm.is_finished"
           " FROM wire_targets wt"
           " JOIN legitimization_measures lm"
           "   USING (access_token)"
           " WHERE (outcome_serial_id > $5)"
           "   AND ($1 OR (wt.h_normalized_payto = $2))"
           "   AND ($3 OR (lo.is_finished = $4))"
           " ORDER BY lo.outcome_serial_id ASC"
           " LIMIT $6");
  PREPARE (pg,
           "select_aml_measures_dec",
           "SELECT"
           " lm.legitimization_measure_serial_id"
           ",wt.h_normalized_payto"
           ",lm.jmeasures"
           ",lm.start_time"
           ",lm.is_finished"
           " FROM wire_targets wt"
           " JOIN legitimization_measures lm"
           "   USING (access_token)"
           " WHERE (outcome_serial_id < $5)"
           "   AND ($1 OR (wt.h_normalized_payto = $2))"
           "   AND ($3 OR (lo.is_finished = $4))"
           " ORDER BY lo.outcome_serial_id DESC"
           " LIMIT $6");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             stmt,
                                             params,
                                             &handle_aml_result,
                                             &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
