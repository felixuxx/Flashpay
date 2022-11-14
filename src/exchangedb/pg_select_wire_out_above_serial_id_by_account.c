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
 * @file exchangedb/pg_select_wire_out_above_serial_id_by_account.c
 * @brief Implementation of the select_wire_out_above_serial_id_by_account function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_wire_out_above_serial_id_by_account.h"
#include "pg_helper.h"

/**
 * Closure for #wire_out_serial_helper_cb().
 */
struct WireOutSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_WireTransferOutCallback cb;

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
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct WireOutSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
wire_out_serial_helper_cb (void *cls,
                           PGresult *result,
                           unsigned int num_results)
{
  struct WireOutSerialContext *wosc = cls;
  struct PostgresClosure *pg = wosc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t rowid;
    struct GNUNET_TIME_Timestamp date;
    struct TALER_WireTransferIdentifierRawP wtid;
    char *payto_uri;
    struct TALER_Amount amount;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("wireout_uuid",
                                    &rowid),
      GNUNET_PQ_result_spec_timestamp ("execution_date",
                                       &date),
      GNUNET_PQ_result_spec_auto_from_type ("wtid_raw",
                                            &wtid),
      GNUNET_PQ_result_spec_string ("payto_uri",
                                    &payto_uri),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &amount),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      wosc->status = GNUNET_SYSERR;
      return;
    }
    ret = wosc->cb (wosc->cb_cls,
                    rowid,
                    date,
                    &wtid,
                    payto_uri,
                    &amount);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}

enum GNUNET_DB_QueryStatus
TEH_PG_select_wire_out_above_serial_id_by_account (
  void *cls,
  const char *account_name,
  uint64_t serial_id,
  TALER_EXCHANGEDB_WireTransferOutCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_string (account_name),
    GNUNET_PQ_query_param_end
  };
  struct WireOutSerialContext wosc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

    /* Used in #postgres_select_wire_out_above_serial_id_by_account() */
  PREPARE (pg,
           "audit_get_wire_incr_by_account",
           "SELECT"
           " wireout_uuid"
           ",execution_date"
           ",wtid_raw"
           ",payto_uri"
           ",amount_val"
           ",amount_frac"
           " FROM wire_out"
           "   JOIN wire_targets"
           "     USING (wire_target_h_payto)"
           " WHERE "
           "      wireout_uuid>=$1 "
           "  AND exchange_account_section=$2"
           " ORDER BY wireout_uuid ASC;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_wire_incr_by_account",
                                             params,
                                             &wire_out_serial_helper_cb,
                                             &wosc);
  if (GNUNET_OK != wosc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
