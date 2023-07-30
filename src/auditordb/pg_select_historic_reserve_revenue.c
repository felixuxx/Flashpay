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
 * @file pg_select_historic_reserve_revenue.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_historic_reserve_revenue.h"
#include "pg_helper.h"


/**
 * Closure for #historic_reserve_revenue_cb().
 */
struct HistoricReserveRevenueContext
{
  /**
   * Function to call for each result.
   */
  TALER_AUDITORDB_HistoricReserveRevenueDataCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Number of results processed.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Helper function for #TAH_PG_select_historic_reserve_revenue().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct HistoricRevenueContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
historic_reserve_revenue_cb (void *cls,
                             PGresult *result,
                             unsigned int num_results)
{
  struct HistoricReserveRevenueContext *hrc = cls;
  struct PostgresClosure *pg = hrc->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct GNUNET_TIME_Timestamp start_date;
    struct GNUNET_TIME_Timestamp end_date;
    struct TALER_Amount reserve_profits;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_timestamp ("start_date",
                                       &start_date),
      GNUNET_PQ_result_spec_timestamp ("end_date",
                                       &end_date),
      TALER_PQ_RESULT_SPEC_AMOUNT ("reserve_profits",
                                   &reserve_profits),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      hrc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    hrc->qs = i + 1;
    if (GNUNET_OK !=
        hrc->cb (hrc->cb_cls,
                 start_date,
                 end_date,
                 &reserve_profits))
      break;
  }
}


enum GNUNET_DB_QueryStatus
TAH_PG_select_historic_reserve_revenue (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  TALER_AUDITORDB_HistoricReserveRevenueDataCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;
  struct HistoricReserveRevenueContext hrc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };

  PREPARE (pg,
           "auditor_historic_reserve_summary_select",
           "SELECT"
           " start_date"
           ",end_date"
           ",reserve_profits"
           " FROM auditor_historic_reserve_summary"
           " WHERE master_pub=$1;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "auditor_historic_reserve_summary_select",
                                             params,
                                             &historic_reserve_revenue_cb,
                                             &hrc);
  if (0 >= qs)
    return qs;
  return hrc.qs;
}
