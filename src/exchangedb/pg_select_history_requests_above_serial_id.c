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
 * @file exchangedb/pg_select_history_requests_above_serial_id.c
 * @brief Implementation of the select_history_requests_above_serial_id function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_history_requests_above_serial_id.h"
#include "pg_helper.h"

/**
 * Closure for #purse_deposit_serial_helper_cb().
 */
struct HistoryRequestSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_HistoryRequestCallback cb;

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
 * @param cls closure of type `struct HistoryRequestSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
history_request_serial_helper_cb (void *cls,
                                  PGresult *result,
                                  unsigned int num_results)
{
  struct HistoryRequestSerialContext *dsc = cls;
  struct PostgresClosure *pg = dsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t rowid;
    struct TALER_Amount history_fee;
    struct GNUNET_TIME_Timestamp ts;
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_ReserveSignatureP reserve_sig;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("history_fee",
                                   &history_fee),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                            &reserve_sig),
      GNUNET_PQ_result_spec_uint64 ("history_request_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_timestamp ("request_timestamp",
                                       &ts),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_GenericReturnValue ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      dsc->status = GNUNET_SYSERR;
      return;
    }
    ret = dsc->cb (dsc->cb_cls,
                   rowid,
                   &history_fee,
                   ts,
                   &reserve_pub,
                   &reserve_sig);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}




enum GNUNET_DB_QueryStatus
TEH_PG_select_history_requests_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_HistoryRequestCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct HistoryRequestSerialContext dsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;
  PREPARE (pg,
           "audit_get_history_requests_incr",
           "SELECT"
           " history_request_serial_id"
           ",history_fee_val"
           ",history_fee_frac"
           ",request_timestamp"
           ",reserve_pub"
           ",reserve_sig"
           " FROM history_requests"
           " WHERE ("
           "  (history_request_serial_id>=$1)"
           " )"
           " ORDER BY history_request_serial_id ASC;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_history_requests_incr",
                                             params,
                                             &history_request_serial_helper_cb,
                                             &dsc);
  if (GNUNET_OK != dsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
