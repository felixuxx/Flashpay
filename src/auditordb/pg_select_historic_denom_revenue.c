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
 * @file pg_select_historic_denom_revenue.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_historic_denom_revenue.h"
#include "pg_helper.h"


/**
 * Closure for #historic_denom_revenue_cb().
 */
struct HistoricDenomRevenueContext
{
  /**
   * Function to call for each result.
   */
  TALER_AUDITORDB_HistoricDenominationRevenueDataCallback cb;

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
 * Helper function for #TEH_PG_select_historic_denom_revenue().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct HistoricRevenueContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
historic_denom_revenue_cb (void *cls,
                           PGresult *result,
                           unsigned int num_results)
{
  struct HistoricDenomRevenueContext *hrc = cls;
  struct PostgresClosure *pg = hrc->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_DenominationHashP denom_pub_hash;
    struct GNUNET_TIME_Timestamp revenue_timestamp;
    struct TALER_Amount revenue_balance;
    struct TALER_Amount loss;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &denom_pub_hash),
      GNUNET_PQ_result_spec_timestamp ("revenue_timestamp",
                                       &revenue_timestamp),
      TALER_PQ_RESULT_SPEC_AMOUNT ("revenue_balance",
                                   &revenue_balance),
      TALER_PQ_RESULT_SPEC_AMOUNT ("loss_balance",
                                   &loss),
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
                 &denom_pub_hash,
                 revenue_timestamp,
                 &revenue_balance,
                 &loss))
      break;
  }
}


enum GNUNET_DB_QueryStatus
TAH_PG_select_historic_denom_revenue (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  TALER_AUDITORDB_HistoricDenominationRevenueDataCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct HistoricDenomRevenueContext hrc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "auditor_historic_denomination_revenue_select",
           "SELECT"
           " denom_pub_hash"
           ",revenue_timestamp"
           ",revenue_balance_val"
           ",revenue_balance_frac"
           ",loss_balance_val"
           ",loss_balance_frac"
           " FROM auditor_historic_denomination_revenue"
           " WHERE master_pub=$1;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "auditor_historic_denomination_revenue_select",
                                             params,
                                             &historic_denom_revenue_cb,
                                             &hrc);
  if (qs <= 0)
    return qs;
  return hrc.qs;
}
