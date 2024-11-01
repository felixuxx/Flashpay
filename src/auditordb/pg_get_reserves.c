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
#include "pg_get_reserves.h"


struct ReservesContext
{

  /**
   * Function to call for each bad sig loss.
   */
  TALER_AUDITORDB_ReservesCallback cb;

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
 * Helper function for #TAH_PG_get_reserves().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct ReservesContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
reserves_cb (void *cls,
             PGresult *result,
             unsigned int num_results)
{
  struct ReservesContext *dcc = cls;
  struct PostgresClosure *pg = dcc->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_AUDITORDB_Reserves dc;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("auditor_reserves_rowid",
                                    &dc.auditor_reserves_rowid),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &dc.reserve_pub),
      TALER_PQ_RESULT_SPEC_AMOUNT ("reserve_balance",
                                   &dc.reserve_balance),
      TALER_PQ_RESULT_SPEC_AMOUNT ("reserve_loss",
                                   &dc.reserve_loss),
      TALER_PQ_RESULT_SPEC_AMOUNT ("withdraw_fee_balance",
                                   &dc.withdraw_fee_balance),
      TALER_PQ_RESULT_SPEC_AMOUNT ("close_fee_balance",
                                   &dc.close_fee_balance),
      TALER_PQ_RESULT_SPEC_AMOUNT ("purse_fee_balance",
                                   &dc.purse_fee_balance),
      TALER_PQ_RESULT_SPEC_AMOUNT ("open_fee_balance",
                                   &dc.open_fee_balance),
      TALER_PQ_RESULT_SPEC_AMOUNT ("history_fee_balance",
                                   &dc.history_fee_balance),
      GNUNET_PQ_result_spec_absolute_time ("expiration_date",
                                           &dc.expiration_date),
      GNUNET_PQ_result_spec_string ("origin_account",
                                    &dc.origin_account.full_payto),
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
                    dc.auditor_reserves_rowid,
                    &dc);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != rval)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TAH_PG_get_reserves (
  void *cls,
  int64_t limit,
  uint64_t offset,
  TALER_AUDITORDB_ReservesCallback cb,
  void *cb_cls)
{
  uint64_t plimit = (uint64_t) ((limit < 0) ? -limit : limit);
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&offset),
    GNUNET_PQ_query_param_uint64 (&plimit),
    GNUNET_PQ_query_param_end
  };
  struct ReservesContext dcc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "auditor_reserves_get_desc",
           "SELECT"
           " auditor_reserves_rowid,"
           " reserve_pub,"
           " reserve_balance,"
           " reserve_loss,"
           " withdraw_fee_balance,"
           " close_fee_balance,"
           " purse_fee_balance,"
           " open_fee_balance,"
           " history_fee_balance,"
           " expiration_date,"
           " origin_account"
           " FROM auditor_reserves"
           " WHERE (auditor_reserves_rowid < $1)"
           " ORDER BY auditor_reserves_rowid DESC"
           " LIMIT $2"
           );
  PREPARE (pg,
           "auditor_reserves_get_asc",
           "SELECT"
           " auditor_reserves_rowid,"
           " reserve_pub,"
           " reserve_balance,"
           " reserve_loss,"
           " withdraw_fee_balance,"
           " close_fee_balance,"
           " purse_fee_balance,"
           " open_fee_balance,"
           " history_fee_balance,"
           " expiration_date,"
           " origin_account"
           " FROM auditor_reserves"
           " WHERE (auditor_reserves_rowid > $1)"
           " ORDER BY auditor_reserves_rowid ASC"
           " LIMIT $2"
           );
  qs = GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    (limit > 0)
    ? "auditor_reserves_get_asc"
    : "auditor_reserves_get_desc",
    params,
    &reserves_cb,
    &dcc);
  if (qs > 0)
    return dcc.qs;
  GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
  return qs;
}
