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
 * @file exchangedb/pg_get_wire_fees.c
 * @brief Implementation of the get_wire_fees function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_wire_fees.h"
#include "pg_helper.h"

/**
 * Closure for #get_wire_fees_cb().
 */
struct GetWireFeesContext
{
  /**
   * Function to call per result.
   */
  TALER_EXCHANGEDB_WireFeeCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Flag set to #GNUNET_OK as long as everything is fine.
   */
  enum GNUNET_GenericReturnValue status;

};


/**
 * Invoke the callback for each result.
 *
 * @param cls a `struct GetWireFeesContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
get_wire_fees_cb (void *cls,
                  PGresult *result,
                  unsigned int num_results)
{
  struct GetWireFeesContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_MasterSignatureP master_sig;
    struct TALER_WireFeeSet fees;
    struct GNUNET_TIME_Timestamp start_date;
    struct GNUNET_TIME_Timestamp end_date;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("wire_fee",
                                   &fees.wire),
      TALER_PQ_RESULT_SPEC_AMOUNT ("closing_fee",
                                   &fees.closing),
      GNUNET_PQ_result_spec_timestamp ("start_date",
                                       &start_date),
      GNUNET_PQ_result_spec_timestamp ("end_date",
                                       &end_date),
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &master_sig),
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
             &fees,
             start_date,
             end_date,
             &master_sig);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_get_wire_fees (void *cls,
                        const char *wire_method,
                        TALER_EXCHANGEDB_WireFeeCallback cb,
                        void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (wire_method),
    GNUNET_PQ_query_param_end
  };
  struct GetWireFeesContext ctx = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;


  PREPARE (pg,
           "get_wire_fees",
           "SELECT"
           " wire_fee_val"
           ",wire_fee_frac"
           ",closing_fee_val"
           ",closing_fee_frac"
           ",start_date"
           ",end_date"
           ",master_sig"
           " FROM wire_fee"
           " WHERE wire_method=$1");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "get_wire_fees",
                                             params,
                                             &get_wire_fees_cb,
                                             &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
