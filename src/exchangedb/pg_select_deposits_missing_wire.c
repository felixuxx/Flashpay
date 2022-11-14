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
 * @file exchangedb/pg_select_deposits_missing_wire.c
 * @brief Implementation of the select_deposits_missing_wire function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_deposits_missing_wire.h"
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
    uint64_t rowid;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_Amount amount;
    char *payto_uri;
    struct GNUNET_TIME_Timestamp deadline;
    bool done;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin_pub),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount),
      GNUNET_PQ_result_spec_string ("payto_uri",
                                    &payto_uri),
      GNUNET_PQ_result_spec_timestamp ("wire_deadline",
                                       &deadline),
      GNUNET_PQ_result_spec_bool ("done",
                                  &done),
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
             rowid,
             &coin_pub,
             &amount,
             payto_uri,
             deadline,
             done);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_deposits_missing_wire (void *cls,
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

      /* Used in #postgres_select_deposits_missing_wire */
    // FIXME: used by the auditor; can probably be done
    // smarter by checking if 'done' or 'blocked'
    // are set correctly when going over deposits, instead
    // of JOINing with refunds.
  PREPARE (pg,
           "deposits_get_overdue",
           "SELECT"
           " deposit_serial_id"
           ",coin_pub"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",payto_uri"
           ",wire_deadline"
           ",done"
           " FROM deposits d"
           "   JOIN known_coins"
           "     USING (coin_pub)"
           "   JOIN wire_targets"
           "     USING (wire_target_h_payto)"
           " WHERE wire_deadline >= $1"
           " AND wire_deadline < $2"
           " AND NOT (EXISTS (SELECT 1"
           "            FROM refunds r"
           "            WHERE (r.coin_pub = d.coin_pub) AND (r.deposit_serial_id = d.deposit_serial_id))"
           "       OR EXISTS (SELECT 1"
           "            FROM aggregation_tracking"
           "            WHERE (aggregation_tracking.deposit_serial_id = d.deposit_serial_id)))"
           " ORDER BY wire_deadline ASC");



  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "deposits_get_overdue",
                                             params,
                                             &missing_wire_cb,
                                             &mwc);
  if (GNUNET_OK != mwc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
