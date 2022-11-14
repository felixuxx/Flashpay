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
 * @file exchangedb/pg_select_purse_decisions_above_serial_id.c
 * @brief Implementation of the select_purse_decisions_above_serial_id function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_purse_decisions_above_serial_id.h"
#include "pg_helper.h"

/**
 * Closure for #purse_decision_serial_helper_cb().
 */
struct PurseDecisionSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_PurseDecisionCallback cb;

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
 * @param cls closure of type `struct PurseRefundSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
purse_decision_serial_helper_cb (void *cls,
                                 PGresult *result,
                                 unsigned int num_results)
{
  struct PurseDecisionSerialContext *dsc = cls;
  struct PostgresClosure *pg = dsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_PurseContractPublicKeyP purse_pub;
    struct TALER_ReservePublicKeyP reserve_pub;
    bool no_reserve = true;
    uint64_t rowid;
    struct TALER_Amount val;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                            &purse_pub),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                              &reserve_pub),
        &no_reserve),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &val),
      GNUNET_PQ_result_spec_uint64 ("purse_deposit_serial_id",
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
      dsc->status = GNUNET_SYSERR;
      return;
    }
    ret = dsc->cb (dsc->cb_cls,
                   rowid,
                   &purse_pub,
                   no_reserve ? NULL : &reserve_pub,
                   &val);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}



enum GNUNET_DB_QueryStatus
TEH_PG_select_purse_decisions_above_serial_id (
  void *cls,
  uint64_t serial_id,
  bool refunded,
  TALER_EXCHANGEDB_PurseDecisionCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_bool (refunded),
    GNUNET_PQ_query_param_end
  };
  struct PurseDecisionSerialContext dsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "audit_get_purse_decisions_incr",
           "SELECT"
           " pd.purse_pub"
           ",pm.reserve_pub"
           ",pd.purse_decision_serial_id"
           ",pr.amount_with_fee_val"
           ",pr.amount_with_fee_frac"
           " FROM purse_decision pd"
           " JOIN purse_requests pr ON (pd.purse_pub = pr.purse_pub)"
           " LEFT JOIN purse_merges pm ON (pm.purse_pub = pd.purse_pub)"
           " WHERE ("
           "  (purse_decision_serial_id>=$1) AND "
           "  (refunded=$2)"
           " )"
           " ORDER BY purse_decision_serial_id ASC;");


  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_purse_decisions_incr",
                                             params,
                                             &purse_decision_serial_helper_cb,
                                             &dsc);
  if (GNUNET_OK != dsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
