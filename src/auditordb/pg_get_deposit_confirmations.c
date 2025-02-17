/*
   This file is part of TALER
   Copyright (C) 2022-2023 Taler Systems SA

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
 * @file pg_get_deposit_confirmations.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_deposit_confirmations.h"
#include "pg_helper.h"


/**
 * Closure for #deposit_confirmation_cb().
 */
struct DepositConfirmationContext
{

  /**
   * Function to call for each deposit confirmation.
   */
  TALER_AUDITORDB_DepositConfirmationCallback cb;

  /**
   * Closure for @e cb
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Query status to return.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Helper function for #TAH_PG_get_deposit_confirmations().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct DepositConfirmationContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
deposit_confirmation_cb (void *cls,
                         PGresult *result,
                         unsigned int num_results)
{
  struct DepositConfirmationContext *dcc = cls;
  struct PostgresClosure *pg = dcc->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_AUDITORDB_DepositConfirmation dc = { 0 };
    struct TALER_CoinSpendPublicKeyP *coin_pubs = NULL;
    struct TALER_CoinSpendSignatureP *coin_sigs = NULL;
    size_t num_pubs = 0;
    size_t num_sigs = 0;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("row_id",
                                    &dc.row_id),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                            &dc.h_contract_terms),
      GNUNET_PQ_result_spec_auto_from_type ("h_policy",
                                            &dc.h_policy),
      GNUNET_PQ_result_spec_auto_from_type ("h_wire",
                                            &dc.h_wire),
      GNUNET_PQ_result_spec_timestamp ("exchange_timestamp",
                                       &dc.exchange_timestamp),
      GNUNET_PQ_result_spec_timestamp ("refund_deadline",
                                       &dc.refund_deadline),
      GNUNET_PQ_result_spec_timestamp ("wire_deadline",
                                       &dc.wire_deadline),
      TALER_PQ_RESULT_SPEC_AMOUNT ("total_without_fee",
                                   &dc.total_without_fee),
      GNUNET_PQ_result_spec_auto_array_from_type (pg->conn,
                                                  "coin_pubs",
                                                  &num_pubs,
                                                  coin_pubs),
      GNUNET_PQ_result_spec_auto_array_from_type (pg->conn,
                                                  "coin_sigs",
                                                  &num_sigs,
                                                  coin_sigs),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                            &dc.merchant),
      GNUNET_PQ_result_spec_auto_from_type ("exchange_sig",
                                            &dc.exchange_sig),
      GNUNET_PQ_result_spec_auto_from_type ("exchange_pub",
                                            &dc.exchange_pub),
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &dc.master_sig),
      GNUNET_PQ_result_spec_bool ("suppressed",
                                  &dc.suppressed),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_GenericReturnValue rval;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      dcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    if (num_sigs != num_pubs)
    {
      GNUNET_break (0);
      dcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      GNUNET_PQ_cleanup_result (rs);
      return;
    }
    dcc->qs = i + 1;
    dc.coin_pubs = coin_pubs;
    dc.coin_sigs = coin_sigs;
    dc.num_coins = num_sigs;
    rval = dcc->cb (dcc->cb_cls,
                    &dc);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != rval)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TAH_PG_get_deposit_confirmations (
  void *cls,
  int64_t limit,
  uint64_t offset,
  bool return_suppressed,
  TALER_AUDITORDB_DepositConfirmationCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  uint64_t plimit = (uint64_t) ((limit < 0) ? -limit : limit);
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&offset),
    GNUNET_PQ_query_param_bool (return_suppressed),
    GNUNET_PQ_query_param_uint64 (&plimit),
    GNUNET_PQ_query_param_end
  };
  struct DepositConfirmationContext dcc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "auditor_deposit_confirmation_select_desc",
           "SELECT"
           " row_id"
           ",h_contract_terms"
           ",h_policy"
           ",h_wire"
           ",exchange_timestamp"
           ",wire_deadline"
           ",refund_deadline"
           ",total_without_fee"
           ",coin_pubs"
           ",coin_sigs"
           ",merchant_pub"
           ",exchange_sig"
           ",exchange_pub"
           ",master_sig"
           ",suppressed"
           " FROM auditor_deposit_confirmations"
           " WHERE (row_id < $1)"
           " AND ($2 OR NOT suppressed)"
           " ORDER BY row_id DESC"
           " LIMIT $3"
           );
  PREPARE (pg,
           "auditor_deposit_confirmation_select_asc",
           "SELECT"
           " row_id"
           ",h_contract_terms"
           ",h_policy"
           ",h_wire"
           ",exchange_timestamp"
           ",wire_deadline"
           ",refund_deadline"
           ",total_without_fee"
           ",coin_pubs"
           ",coin_sigs"
           ",merchant_pub"
           ",exchange_sig"
           ",exchange_pub"
           ",master_sig"
           ",suppressed"
           " FROM auditor_deposit_confirmations"
           " WHERE (row_id > $1)"
           " AND ($2 OR NOT suppressed)"
           " ORDER BY row_id ASC"
           " LIMIT $3"
           );
  qs = GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    (limit > 0)
    ? "auditor_deposit_confirmation_select_asc"
    : "auditor_deposit_confirmation_select_desc",
    params,
    &deposit_confirmation_cb,
    &dcc);
  if (qs > 0)
    return dcc.qs;
  GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
  return qs;
}
