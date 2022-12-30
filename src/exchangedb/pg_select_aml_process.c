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
 * @file exchangedb/pg_select_aml_process.c
 * @brief Implementation of the select_aml_process function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_aml_process.h"
#include "pg_helper.h"


/**
 * Closure for #handle_aml_result.
 */
struct AmlProcessResultContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_AmlStatusCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to #GNUNET_SYSERR on serious errors.
   */
  enum GNUNET_GenericReturnValue status;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.  Helper function
 * for #TEH_PG_select_aml_process().
 *
 * @param cls closure of type `struct AmlProcessResultContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
handle_aml_result (void *cls,
                   PGresult *result,
                   unsigned int num_results)
{
  struct AmlProcessResultContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_PaytoHashP h_payto;
    struct TALER_Amount threshold;
    uint64_t rowid;
    uint32_t sv;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("aml_status_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("h_payto",
                                            &h_payto),
      TALER_PQ_RESULT_SPEC_AMOUNT ("threshold",
                                   &threshold),
      GNUNET_PQ_result_spec_uint32 ("status",
                                    &sv),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->status = GNUNET_SYSERR;
      return;
    }
    ctx->cb (ctx->cb_cls,
             rowid,
             &h_payto,
             &threshold,
             (enum TALER_AmlDecisionState) sv);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_aml_process (
  void *cls,
  enum TALER_AmlDecisionState decision,
  uint64_t row_off,
  bool forward,
  TALER_EXCHANGEDB_AmlStatusCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint32 (&decision),
    GNUNET_PQ_query_param_uint64 (&row_off),
    GNUNET_PQ_query_param_end
  };
  struct AmlProcessResultContext ctx = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;
  const char *stmt = forward
    ? "select_aml_process_inc"
    : "select_aml_process_dec";

  PREPARE (pg,
           "select_aml_process_inc",
           "SELECT"
           " aml_status_serial_id"
           ",h_payto"
           ",threshold_var"
           ",threshold_frac"
           ",status"
           " FROM aml_status"
           " WHERE aml_status_serial_id > $2"
           "   AND $1 = status & $1"
           " ORDER BY aml_status_serial_id INC");
  PREPARE (pg,
           "select_aml_process_dec",
           "SELECT"
           " aml_status_serial_id"
           ",h_payto"
           ",threshold_var"
           ",threshold_frac"
           ",status"
           " FROM aml_status"
           " WHERE aml_status_serial_id < $2"
           "   AND $1 = status & $1"
           " ORDER BY aml_status_serial_id DESC");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             stmt,
                                             params,
                                             &handle_aml_result,
                                             &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
