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
 * @file pg_select_reserve_closed_above_serial_id.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_reserve_history.h"
#include "plugin_exchangedb_common.h"
#include "pg_helper.h"

/**
 * Closure for #reserve_closed_serial_helper_cb().
 */
struct ReserveClosedSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_ReserveClosedCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin's context.
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
 * @param cls closure of type `struct ReserveClosedSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
reserve_closed_serial_helper_cb (void *cls,
                                 PGresult *result,
                                 unsigned int num_results)
{
  struct ReserveClosedSerialContext *rcsc = cls;
  struct PostgresClosure *pg = rcsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t rowid;
    struct TALER_ReservePublicKeyP reserve_pub;
    char *receiver_account;
    struct TALER_WireTransferIdentifierRawP wtid;
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount closing_fee;
    struct GNUNET_TIME_Timestamp execution_date;
    uint64_t close_request_row;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("close_uuid",
                                    &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_timestamp ("execution_date",
                                       &execution_date),
      GNUNET_PQ_result_spec_auto_from_type ("wtid",
                                            &wtid),
      GNUNET_PQ_result_spec_string ("receiver_account",
                                    &receiver_account),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &amount_with_fee),
      TALER_PQ_RESULT_SPEC_AMOUNT ("closing_fee",
                                   &closing_fee),
      GNUNET_PQ_result_spec_uint64 ("close_request_row",
                                    &close_request_row),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_GenericReturnValue ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      rcsc->status = GNUNET_SYSERR;
      return;
    }
    ret = rcsc->cb (rcsc->cb_cls,
                    rowid,
                    execution_date,
                    &amount_with_fee,
                    &closing_fee,
                    &reserve_pub,
                    receiver_account,
                    &wtid,
                    close_request_row);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_reserve_closed_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_ReserveClosedCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct ReserveClosedSerialContext rcsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  /* Used in #postgres_select_reserve_closed_above_serial_id() to
     obtain information about closed reserves */
  PREPARE (
    pg,
    "reserves_close_get_incr",
    "SELECT"
    " close_uuid"
    ",reserves.reserve_pub"
    ",execution_date"
    ",wtid"
    ",payto_uri AS receiver_account"
    ",amount_val"
    ",amount_frac"
    ",closing_fee_val"
    ",closing_fee_frac"
    ",close_request_row"
    " FROM reserves_close"
    "   JOIN wire_targets"
    "     USING (wire_target_h_payto)"
    "   JOIN reserves"
    "     USING (reserve_pub)"
    " WHERE close_uuid>=$1"
    " ORDER BY close_uuid ASC;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "reserves_close_get_incr",
                                             params,
                                             &reserve_closed_serial_helper_cb,
                                             &rcsc);
  if (GNUNET_OK != rcsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
