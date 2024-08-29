/*
   This file is part of TALER
   Copyright (C) 2023, 2024 Taler Systems SA

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
 * @file exchangedb/pg_select_aggregations_above_serial.c
 * @brief Implementation of the select_aggregations_above_serial function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_aggregations_above_serial.h"
#include "pg_helper.h"

/**
 * Closure for #aggregation_serial_helper_cb().
 */
struct AggregationSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_AggregationCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  enum GNUNET_GenericReturnValue status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct AggregationSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
aggregation_serial_helper_cb (void *cls,
                              PGresult *result,
                              unsigned int num_results)
{
  struct AggregationSerialContext *dsc = cls;
  struct PostgresClosure *pg = dsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t tracking_rowid;
    uint64_t batch_deposit_serial_id;
    struct TALER_Amount amount;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &amount),
      GNUNET_PQ_result_spec_uint64 ("aggregation_serial_id",
                                    &tracking_rowid),
      GNUNET_PQ_result_spec_uint64 ("batch_deposit_serial_id",
                                    &batch_deposit_serial_id),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      dsc->status = GNUNET_SYSERR;
      return;
    }
    dsc->cb (dsc->cb_cls,
             &amount,
             tracking_rowid,
             batch_deposit_serial_id);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_aggregations_above_serial (
  void *cls,
  uint64_t min_tracking_serial_id,
  TALER_EXCHANGEDB_AggregationCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&min_tracking_serial_id),
    GNUNET_PQ_query_param_end
  };
  struct AggregationSerialContext asc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  /* Fetch aggregations with rowid '\geq' the given parameter */
  PREPARE (pg,
           "select_aggregations_above_serial",
           "SELECT"
           " aggregation_serial_id"
           ",batch_deposit_serial_id"
           " FROM aggregation_tracking"
           " WHERE aggregation_serial_id>=$1"
           " ORDER BY aggregation_serial_id ASC;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "select_aggregations_above_serial",
                                             params,
                                             &aggregation_serial_helper_cb,
                                             &asc);
  if (GNUNET_OK != asc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
