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
 * @file exchangedb/pg_select_aml_history.c
 * @brief Implementation of the select_aml_history function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_aml_history.h"
#include "pg_helper.h"


/**
 * Closure for #handle_aml_result.
 */
struct AmlHistoryResultContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_AmlHistoryCallback cb;

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
 * for #TEH_PG_select_aml_history().
 *
 * @param cls closure of type `struct AmlHistoryResultContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
handle_aml_result (void *cls,
                   PGresult *result,
                   unsigned int num_results)
{
  struct AmlHistoryResultContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_Amount new_threshold;
    uint32_t ns;
    struct GNUNET_TIME_Absolute decision_time;
    char *justification;
    struct TALER_AmlOfficerPublicKeyP decider_pub;
    struct TALER_AmlOfficerSignatureP decider_sig;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("new_threshold",
                                   &new_threshold),
      GNUNET_PQ_result_spec_uint32 ("new_status",
                                    &ns),
      GNUNET_PQ_result_spec_absolute_time ("decision_time",
                                           &decision_time),
      GNUNET_PQ_result_spec_string ("justification",
                                    &justification),
      GNUNET_PQ_result_spec_auto_from_type ("decider_pub",
                                            &decider_pub),
      GNUNET_PQ_result_spec_auto_from_type ("decider_sig",
                                            &decider_sig),
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
             &new_threshold,
             (enum TALER_AmlDecisionState) ns,
             decision_time,
             justification,
             &decider_pub,
             &decider_sig);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_aml_history (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  TALER_EXCHANGEDB_AmlHistoryCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_end
  };
  struct AmlHistoryResultContext ctx = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "lookup_aml_history",
           "SELECT"
           " aggregation_serial_id"
           ",deposits.h_contract_terms"
           ",payto_uri"
           ",wire_targets.wire_target_h_payto"
           ",kc.coin_pub"
           ",deposits.merchant_pub"
           ",wire_out.execution_date"
           ",deposits.amount_with_fee_val"
           ",deposits.amount_with_fee_frac"
           ",denom.fee_deposit_val"
           ",denom.fee_deposit_frac"
           ",denom.denom_pub"
           " FROM aml_history"
           " WHERE h_payto=$1;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "lookup_aml_history",
                                             params,
                                             &handle_aml_result,
                                             &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
