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
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_helper.h"
#include "pg_get_reserve_in_inconsistency.h"


struct ReserveInInconsistencyContext
{

  /**
   * Function to call for each bad sig loss.
   */
  TALER_AUDITORDB_ReserveInInconsistencyCallback cb;

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
 * Helper function for #TAH_PG_get_reserve_in_inconsistency().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct ReserveInInconsistencyContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
reserve_in_inconsistency_cb (void *cls,
                             PGresult *result,
                             unsigned int num_results)
{
  struct ReserveInInconsistencyContext *dcc = cls;
  struct PostgresClosure *pg = dcc->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_AUDITORDB_ReserveInInconsistency dc;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("row_id",
                                    &dc.serial_id),
      GNUNET_PQ_result_spec_uint64 ("bank_row_id",
                                    &dc.bank_row_id),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_exchange_expected",
                                   &dc.amount_exchange_expected),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_wired",
                                   &dc.amount_wired),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &dc.reserve_pub),
      GNUNET_PQ_result_spec_absolute_time ("timestamp",
                                           &dc.timestamp),
      GNUNET_PQ_result_spec_string ("account",
                                    &dc.account.full_payto),
      GNUNET_PQ_result_spec_string ("diagnostic",
                                    &dc.diagnostic),
      GNUNET_PQ_result_spec_bool ("suppressed",
                                  &dc.suppressed),
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
TAH_PG_get_reserve_in_inconsistency (
  void *cls,
  int64_t limit,
  uint64_t offset,
  bool return_suppressed,
  TALER_AUDITORDB_ReserveInInconsistencyCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  uint64_t plimit = (uint64_t) ((limit < 0) ? -limit : limit);
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&offset),
    GNUNET_PQ_query_param_bool (return_suppressed),
    GNUNET_PQ_query_param_uint64 (&plimit),
    GNUNET_PQ_query_param_end
  };
  struct ReserveInInconsistencyContext dcc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "auditor_reserve_in_inconsistency_get_desc",
           "SELECT"
           " row_id"
           ",bank_row_id"
           ",amount_exchange_expected"
           ",amount_wired"
           ",reserve_pub"
           ",timestamp"
           ",account"
           ",diagnostic"
           ",suppressed"
           " FROM auditor_reserve_in_inconsistency"
           " WHERE (row_id < $1)"
           " AND ($2 OR suppressed is false)"
           " ORDER BY row_id DESC"
           " LIMIT $3"
           );
  PREPARE (pg,
           "auditor_reserve_in_inconsistency_get_asc",
           "SELECT"
           " row_id"
           ",bank_row_id"
           ",amount_exchange_expected"
           ",amount_wired"
           ",reserve_pub"
           ",timestamp"
           ",account"
           ",diagnostic"
           ",suppressed"
           " FROM auditor_reserve_in_inconsistency"
           " WHERE (row_id > $1)"
           " AND ($2 OR suppressed is false)"
           " ORDER BY row_id ASC"
           " LIMIT $3"
           );
  qs = GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    (limit > 0)
    ? "auditor_reserve_in_inconsistency_get_asc"
    : "auditor_reserve_in_inconsistency_get_desc",
    params,
    &reserve_in_inconsistency_cb,
    &dcc);
  if (qs > 0)
    return dcc.qs;
  GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
  return qs;
}
