/*
   This file is part of TALER
   Copyright (C) 2023 Taler Systems SA

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
 * @file auditordb/pg_select_pending_deposits.c
 * @brief Implementation of the select_pending_deposits function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_pending_deposits.h"
#include "pg_helper.h"


/**
 * Closure for #wire_missing_cb().
 */
struct WireMissingContext
{

  /**
   * Function to call for each pending deposit.
   */
  TALER_AUDITORDB_WireMissingCallback cb;

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
 * Helper function for #TAH_PG_select_purse_expired().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct WireMissingContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
wire_missing_cb (void *cls,
                 PGresult *result,
                 unsigned int num_results)
{
  struct WireMissingContext *eic = cls;
  struct PostgresClosure *pg = eic->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    uint64_t batch_deposit_serial_id;
    struct TALER_Amount total_amount;
    struct TALER_FullPaytoHashP wire_target_h_payto;
    struct GNUNET_TIME_Timestamp deadline;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("batch_deposit_serial_id",
                                    &batch_deposit_serial_id),
      TALER_PQ_RESULT_SPEC_AMOUNT ("total_amount",
                                   &total_amount),
      GNUNET_PQ_result_spec_auto_from_type ("wire_target_h_payto",
                                            &wire_target_h_payto),
      GNUNET_PQ_result_spec_timestamp ("deadline",
                                       &deadline),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      eic->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    eic->cb (eic->cb_cls,
             batch_deposit_serial_id,
             &total_amount,
             &wire_target_h_payto,
             deadline);
  }
  eic->qs = num_results;
}


enum GNUNET_DB_QueryStatus
TAH_PG_select_pending_deposits (
  void *cls,
  struct GNUNET_TIME_Absolute deadline,
  TALER_AUDITORDB_WireMissingCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_absolute_time (&deadline),
    GNUNET_PQ_query_param_end
  };
  struct WireMissingContext eic = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "auditor_select_pending_deposits",
           "SELECT"
           " batch_deposit_serial_id"
           ",total_amount"
           ",wire_target_h_payto"
           ",deadline"
           " FROM auditor_pending_deposits"
           " WHERE deadline<$1;");
  qs = GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    "auditor_select_pending_deposits",
    params,
    &wire_missing_cb,
    &eic);
  if (0 > qs)
    return qs;
  GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != eic.qs);
  return eic.qs;
}
