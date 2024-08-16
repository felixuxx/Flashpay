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
 * @file exchangedb/pg_select_reserves_in_above_serial_id.c
 * @brief Implementation of the select_reserves_in_above_serial_id function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_reserves_in_above_serial_id.h"
#include "pg_helper.h"

/**
 * Closure for #reserves_in_serial_helper_cb().
 */
struct ReservesInSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_ReserveInCallback cb;

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
 * @param cls closure of type `struct ReservesInSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
reserves_in_serial_helper_cb (void *cls,
                              PGresult *result,
                              unsigned int num_results)
{
  struct ReservesInSerialContext *risc = cls;
  struct PostgresClosure *pg = risc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_Amount credit;
    char *sender_account_details;
    struct GNUNET_TIME_Timestamp execution_date;
    uint64_t rowid;
    uint64_t wire_reference;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_uint64 ("wire_reference",
                                    &wire_reference),
      TALER_PQ_RESULT_SPEC_AMOUNT ("credit",
                                   &credit),
      GNUNET_PQ_result_spec_timestamp ("execution_date",
                                       &execution_date),
      GNUNET_PQ_result_spec_string ("sender_account_details",
                                    &sender_account_details),
      GNUNET_PQ_result_spec_uint64 ("reserve_in_serial_id",
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
      risc->status = GNUNET_SYSERR;
      return;
    }
    ret = risc->cb (risc->cb_cls,
                    rowid,
                    &reserve_pub,
                    &credit,
                    sender_account_details,
                    wire_reference,
                    execution_date);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_reserves_in_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_ReserveInCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct ReservesInSerialContext risc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "audit_reserves_in_get_transactions_incr",
           "SELECT"
           " reserves.reserve_pub"
           ",wire_reference"
           ",credit"
           ",execution_date"
           ",payto_uri AS sender_account_details"
           ",reserve_in_serial_id"
           " FROM reserves_in"
           " JOIN reserves"
           "   USING (reserve_pub)"
           " JOIN wire_targets"
           "   ON (wire_source_h_payto = wire_target_h_payto)"
           " WHERE reserve_in_serial_id>=$1"
           " ORDER BY reserve_in_serial_id;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_reserves_in_get_transactions_incr",
                                             params,
                                             &reserves_in_serial_helper_cb,
                                             &risc);
  if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    return qs;
  if (GNUNET_OK != risc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
