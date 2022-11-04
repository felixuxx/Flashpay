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
   * Master public key that is being used.
   */
  const struct TALER_MasterPublicKeyP *master_pub;

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
    uint64_t serial_id;
    struct TALER_AUDITORDB_DepositConfirmation dc = {
      .master_public_key = *dcc->master_pub
    };
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial_id",
                                    &serial_id),
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
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_without_fee",
                                   &dc.amount_without_fee),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &dc.coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                            &dc.merchant),
      GNUNET_PQ_result_spec_auto_from_type ("exchange_sig",
                                            &dc.exchange_sig),
      GNUNET_PQ_result_spec_auto_from_type ("exchange_pub",
                                            &dc.exchange_pub),
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &dc.master_sig),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      dcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    dcc->qs = i + 1;
    if (GNUNET_OK !=
        dcc->cb (dcc->cb_cls,
                 serial_id,
                 &dc))
      break;
  }
}


enum GNUNET_DB_QueryStatus
TAH_PG_get_deposit_confirmations (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_public_key,
  uint64_t start_id,
  TALER_AUDITORDB_DepositConfirmationCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_public_key),
    GNUNET_PQ_query_param_uint64 (&start_id),
    GNUNET_PQ_query_param_end
  };
  struct DepositConfirmationContext dcc = {
    .master_pub = master_public_key,
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "auditor_deposit_confirmation_select",
           "SELECT"
           " serial_id"
           ",h_contract_terms"
           ",h_policy"
           ",h_wire"
           ",exchange_timestamp"
           ",wire_deadline"
           ",refund_deadline"
           ",amount_without_fee_val"
           ",amount_without_fee_frac"
           ",coin_pub"
           ",merchant_pub"
           ",exchange_sig"
           ",exchange_pub"
           ",master_sig"                  /* master_sig could be normalized... */
           " FROM deposit_confirmations"
           " WHERE master_pub=$1"
           " AND serial_id>$2");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "auditor_deposit_confirmation_select",
                                             params,
                                             &deposit_confirmation_cb,
                                             &dcc);
  if (qs > 0)
    return dcc.qs;
  GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
  return qs;
}
