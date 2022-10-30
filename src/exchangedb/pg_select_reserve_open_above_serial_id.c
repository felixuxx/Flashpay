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
 * @file pg_select_reserve_open_above_serial_id.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_reserve_open_above_serial_id.h"
#include "plugin_exchangedb_common.h"
#include "pg_helper.h"


/**
 * Closure for #reserve_open_serial_helper_cb().
 */
struct ReserveOpenSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_ReserveOpenCallback cb;

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
 * @param cls closure of type `struct ReserveOpenSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
reserve_open_serial_helper_cb (void *cls,
                               PGresult *result,
                               unsigned int num_results)
{
  struct ReserveOpenSerialContext *rcsc = cls;
  struct PostgresClosure *pg = rcsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t rowid;
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_ReserveSignatureP reserve_sig;
    uint32_t requested_purse_limit;
    struct GNUNET_TIME_Timestamp request_timestamp;
    struct GNUNET_TIME_Timestamp reserve_expiration;
    struct TALER_Amount reserve_payment;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("open_request_uuid",
                                    &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                            &reserve_sig),
      GNUNET_PQ_result_spec_timestamp ("request_timestamp",
                                       &request_timestamp),
      GNUNET_PQ_result_spec_timestamp ("expiration_date",
                                       &reserve_expiration),
      GNUNET_PQ_result_spec_uint32 ("requested_purse_limit",
                                    &requested_purse_limit),
      TALER_PQ_RESULT_SPEC_AMOUNT ("reserve_payment",
                                   &reserve_payment),
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
                    &reserve_payment,
                    request_timestamp,
                    reserve_expiration,
                    requested_purse_limit,
                    &reserve_pub,
                    &reserve_sig);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_reserve_open_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_ReserveOpenCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct ReserveOpenSerialContext rcsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (
    pg,
    "reserves_open_get_incr",
    "SELECT"
    " open_request_uuid"
    ",reserve_pub"
    ",request_timestamp"
    ",expiration_date"
    ",reserve_sig"
    ",reserve_payment_val"
    ",reserve_payment_frac"
    ",requested_purse_limit"
    " FROM reserves_open_requests"
    " WHERE open_request_uuid>=$1"
    " ORDER BY open_request_uuid ASC;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "reserves_open_get_incr",
                                             params,
                                             &reserve_open_serial_helper_cb,
                                             &rcsc);
  if (GNUNET_OK != rcsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
