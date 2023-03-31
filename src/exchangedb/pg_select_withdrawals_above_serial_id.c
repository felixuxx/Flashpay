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
 * @file exchangedb/pg_select_withdrawals_above_serial_id.c
 * @brief Implementation of the select_withdrawals_above_serial_id function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_withdrawals_above_serial_id.h"
#include "pg_helper.h"

/**
 * Closure for #reserves_out_serial_helper_cb().
 */
struct ReservesOutSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_WithdrawCallback cb;

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
 * @param cls closure of type `struct ReservesOutSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
reserves_out_serial_helper_cb (void *cls,
                               PGresult *result,
                               unsigned int num_results)
{
  struct ReservesOutSerialContext *rosc = cls;
  struct PostgresClosure *pg = rosc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_BlindedCoinHashP h_blind_ev;
    struct TALER_DenominationPublicKey denom_pub;
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_ReserveSignatureP reserve_sig;
    struct GNUNET_TIME_Timestamp execution_date;
    struct TALER_Amount amount_with_fee;
    uint64_t rowid;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                            &h_blind_ev),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                            &reserve_sig),
      GNUNET_PQ_result_spec_timestamp ("execution_date",
                                       &execution_date),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount_with_fee),
      GNUNET_PQ_result_spec_uint64 ("reserve_out_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_GenericReturnValue ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      rosc->status = GNUNET_SYSERR;
      return;
    }
    ret = rosc->cb (rosc->cb_cls,
                    rowid,
                    &h_blind_ev,
                    &denom_pub,
                    &reserve_pub,
                    &reserve_sig,
                    execution_date,
                    &amount_with_fee);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_withdrawals_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_WithdrawCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct ReservesOutSerialContext rosc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  /* Fetch deposits with rowid '\geq' the given parameter */

  PREPARE (pg,
           "audit_get_reserves_out_incr",
           "SELECT"
           " h_blind_ev"
           ",denom.denom_pub"
           ",reserve_sig"
           ",reserves.reserve_pub"
           ",execution_date"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",reserve_out_serial_id"
           " FROM reserves_out"
           "    JOIN reserves"
           "      USING (reserve_uuid)"
           "    JOIN denominations denom"
           "      USING (denominations_serial)"
           " WHERE reserve_out_serial_id>=$1"
           " ORDER BY reserve_out_serial_id ASC;");


  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_reserves_out_incr",
                                             params,
                                             &reserves_out_serial_helper_cb,
                                             &rosc);
  if (GNUNET_OK != rosc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
