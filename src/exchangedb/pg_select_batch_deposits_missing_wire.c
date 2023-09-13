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
 * @file exchangedb/pg_select_batch_deposits_missing_wire.c
 * @brief Implementation of the select_batch_deposits_missing_wire function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_batch_deposits_missing_wire.h"
#include "pg_helper.h"

/**
 * Closure for #missing_wire_cb().
 */
struct MissingWireContext
{
  /**
   * Function to call per result.
   */
  TALER_EXCHANGEDB_WireMissingCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to #GNUNET_SYSERR on error.
   */
  enum GNUNET_GenericReturnValue status;
};


/**
 * Invoke the callback for each result.
 *
 * @param cls a `struct MissingWireContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
missing_wire_cb (void *cls,
                 PGresult *result,
                 unsigned int num_results)
{
  struct MissingWireContext *mwc = cls;
  struct PostgresClosure *pg = mwc->pg;

  while (0 < num_results)
  {
    struct TALER_Amount total_amount;
    struct TALER_Amount aml_limit;
    char *payto_uri = NULL;
    char *kyc_pending = NULL;
    uint32_t aml_status32 = TALER_AML_NORMAL;
    struct GNUNET_TIME_Timestamp deadline;
    bool no_aml_limit;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("total_amount_with_fee",
                                   &total_amount),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("payto_uri",
                                      &payto_uri),
        NULL),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("kyc_pending",
                                      &kyc_pending),
        NULL),
      GNUNET_PQ_result_spec_timestamp ("wire_deadline",
                                       &deadline),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_uint32 ("aml_status",
                                      &aml_status32),
        NULL),
      GNUNET_PQ_result_spec_allow_null (
        TALER_PQ_RESULT_SPEC_AMOUNT ("aml_limit",
                                     &aml_limit),
        &no_aml_limit),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  --num_results))
    {
      GNUNET_break (0);
      mwc->status = GNUNET_SYSERR;
      return;
    }
    mwc->cb (mwc->cb_cls,
             &total_amount,
             payto_uri,
             deadline,
             kyc_pending,
             (enum TALER_AmlDecisionState) aml_status32,
             no_aml_limit ? NULL : &aml_limit);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_batch_deposits_missing_wire (
  void *cls,
  struct GNUNET_TIME_Timestamp start_date,
  struct GNUNET_TIME_Timestamp end_date,
  TALER_EXCHANGEDB_WireMissingCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&start_date),
    GNUNET_PQ_query_param_timestamp (&end_date),
    GNUNET_PQ_query_param_end
  };
  struct MissingWireContext mwc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "deposits_get_overdue",
           "SELECT"
           " total_amount_with_fee"
           ",payto_uri"
           ",kyc_pending"
           ",wire_deadline"
           ",aml_status"
           ",aml_limit"
           " FROM exchange_do_select_deposits_missing_wire"
           " ($1,$2);");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "deposits_get_overdue",
                                             params,
                                             &missing_wire_cb,
                                             &mwc);
  if (GNUNET_OK != mwc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
