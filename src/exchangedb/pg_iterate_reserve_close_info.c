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
 * @file pg_iterate_reserve_close_info.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_iterate_reserve_close_info.h"
#include "pg_helper.h"

/**
 * Closure for #iterate_reserve_close_info_cb()
 */
struct IteratorContext
{
  /**
   * Function to call with the results.
   */
  TALER_EXCHANGEDB_KycAmountCallback cb;

  /**
   * Closure to pass to @e cb
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;
};


/**
 * Helper function for #TEH_PG_iterate_reserve_close_info().
 * Calls the callback with each denomination key.
 *
 * @param cls a `struct IteratorContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
iterate_reserve_close_info_cb (void *cls,
                               PGresult *result,
                               unsigned int num_results)
{
  struct IteratorContext *ic = cls;
  struct PostgresClosure *pg = ic->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_Amount amount;
    struct GNUNET_TIME_Absolute ts;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_absolute_time ("execution_date",
                                           &ts),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &amount),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      return;
    }
    ic->cb (ic->cb_cls,
            &amount,
            ts);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_iterate_reserve_close_info (
  void *cls,
  const struct TALER_FullPaytoHashP *h_payto,
  struct GNUNET_TIME_Absolute time_limit,
  TALER_EXCHANGEDB_KycAmountCallback kac,
  void *kac_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_absolute_time (&time_limit),
    GNUNET_PQ_query_param_end
  };
  struct IteratorContext ic = {
    .cb = kac,
    .cb_cls = kac_cls,
    .pg = pg
  };

  PREPARE (pg,
           "iterate_reserve_close_info",
           "SELECT"
           " amount"
           ",execution_date"
           " FROM reserves_close"
           " WHERE wire_target_h_payto=$1"
           "   AND execution_date >= $2"
           " ORDER BY execution_date DESC");
  return GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    "iterate_reserve_close_info",
    params,
    &iterate_reserve_close_info_cb,
    &ic);
}
