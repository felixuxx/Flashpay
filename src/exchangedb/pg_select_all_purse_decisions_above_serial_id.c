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
 * @file pg_select_all_purse_decisions_above_serial_id.c
 * @brief Implementation of the select_all_purse_decisions_above_serial_id function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_all_purse_decisions_above_serial_id.h"
#include "pg_helper.h"


/**
 * Closure for #all_purse_decision_serial_helper_cb().
 */
struct AllPurseDecisionSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_AllPurseDecisionCallback cb;

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
all_purse_decision_serial_helper_cb (void *cls,
                                     PGresult *result,
                                     unsigned int num_results)
{
  struct AllPurseDecisionSerialContext *dsc = cls;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_PurseContractPublicKeyP purse_pub;
    bool refunded;
    uint64_t rowid;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                            &purse_pub),
      GNUNET_PQ_result_spec_bool ("refunded",
                                  &refunded),
      GNUNET_PQ_result_spec_uint64 ("purse_decision_serial_id",
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
                   refunded);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_all_purse_decisions_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_AllPurseDecisionCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct AllPurseDecisionSerialContext dsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "audit_get_all_purse_decisions_incr",
           "SELECT"
           " purse_pub"
           ",refunded"
           ",purse_decision_serial_id"
           " FROM purse_decision"
           " WHERE purse_decision_serial_id>=$1"
           " ORDER BY purse_decision_serial_id ASC;");
  qs = GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    "audit_get_all_purse_decision_incr",
    params,
    &all_purse_decision_serial_helper_cb,
    &dsc);
  if (GNUNET_OK != dsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
