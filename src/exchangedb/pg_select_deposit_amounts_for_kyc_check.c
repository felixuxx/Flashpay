/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

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
 * @file exchangedb/pg_select_deposit_amounts_for_kyc_check.c
 * @brief Implementation of the select_deposit_amounts_for_kyc_check function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_deposit_amounts_for_kyc_check.h"
#include "pg_helper.h"

/**
 * Closure for #get_kyc_amounts_cb().
 */
struct KycAmountCheckContext
{
  /**
   * Function to call per result.
   */
  TALER_EXCHANGEDB_KycAmountCallback cb;

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
 * @param cls a `struct KycAmountCheckContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
get_kyc_amounts_cb (void *cls,
                    PGresult *result,
                    unsigned int num_results)
{
  struct KycAmountCheckContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct GNUNET_TIME_Absolute date;
    struct TALER_Amount amount;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &amount),
      GNUNET_PQ_result_spec_absolute_time ("date",
                                           &date),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_GenericReturnValue ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->status = GNUNET_SYSERR;
      return;
    }
    ret = ctx->cb (ctx->cb_cls,
                   &amount,
                   date);
    GNUNET_PQ_cleanup_result (rs);
    switch (ret)
    {
    case GNUNET_OK:
      continue;
    case GNUNET_NO:
      break;
    case GNUNET_SYSERR:
      ctx->status = GNUNET_SYSERR;
      break;
    }
    break;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_deposit_amounts_for_kyc_check (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  struct GNUNET_TIME_Absolute time_limit,
  TALER_EXCHANGEDB_KycAmountCallback kac,
  void *kac_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_absolute_time (&time_limit),
    GNUNET_PQ_query_param_end
  };
  struct KycAmountCheckContext ctx = {
    .cb = kac,
    .cb_cls = kac_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "select_kyc_relevant_deposit_events",
           "SELECT"
           " cd.amount_with_fee AS amount"
           ",bd.exchange_timestamp AS date"
           " FROM batch_deposits bd"
           " JOIN coin_deposits cd"
           "   USING (batch_deposit_serial_id)"
           " WHERE wire_target_h_payto IN ("
           "   SELECT wire_target_h_payto"
           "     FROM wire_targets"
           "    WHERE h_normalized_payto=$1"
           "   )"
           "   AND bd.exchange_timestamp >= $2"
           " ORDER BY bd.exchange_timestamp DESC");
  qs = GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    "select_kyc_relevant_deposit_events",
    params,
    &get_kyc_amounts_cb,
    &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
