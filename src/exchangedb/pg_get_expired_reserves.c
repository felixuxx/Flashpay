/*
   This file is part of TALER
   Copyright (C) 2022, 2024 Taler Systems SA

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
 * @file pg_get_expired_reserves.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_expired_reserves.h"
#include "pg_helper.h"


/**
 * Closure for #reserve_expired_cb().
 */
struct ExpiredReserveContext
{
  /**
   * Function to call for each expired reserve.
   */
  TALER_EXCHANGEDB_ReserveExpiredCallback rec;

  /**
   * Closure to give to @e rec.
   */
  void *rec_cls;

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
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
reserve_expired_cb (void *cls,
                    PGresult *result,
                    unsigned int num_results)
{
  struct ExpiredReserveContext *erc = cls;
  struct PostgresClosure *pg = erc->pg;
  enum GNUNET_GenericReturnValue ret = GNUNET_OK;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_TIME_Timestamp exp_date;
    struct TALER_FullPayto account_details;
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_Amount remaining_balance;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_timestamp ("expiration_date",
                                       &exp_date),
      GNUNET_PQ_result_spec_string ("account_details",
                                    &account_details.full_payto),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      TALER_PQ_result_spec_amount ("current_balance",
                                   pg->currency,
                                   &remaining_balance),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ret = GNUNET_SYSERR;
      break;
    }
    ret = erc->rec (erc->rec_cls,
                    &reserve_pub,
                    &remaining_balance,
                    account_details,
                    exp_date,
                    0);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
  erc->status = ret;
}


enum GNUNET_DB_QueryStatus
TEH_PG_get_expired_reserves (
  void *cls,
  struct GNUNET_TIME_Timestamp now,
  TALER_EXCHANGEDB_ReserveExpiredCallback rec,
  void *rec_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&now),
    GNUNET_PQ_query_param_end
  };
  struct ExpiredReserveContext ectx = {
    .rec = rec,
    .rec_cls = rec_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "get_expired_reserves",
           "WITH ed AS MATERIALIZED ( "
           " SELECT expiration_date"
           "       ,wire_source_h_payto"
           "       ,current_balance"
           "       ,r.reserve_pub"
           " FROM reserves r"
           " JOIN reserves_in"
           "   USING (reserve_pub)"
           " WHERE expiration_date <= $1 "
           "   AND ((current_balance).val != 0 OR (current_balance).frac != 0) "
           " ORDER BY expiration_date ASC "
           " LIMIT 1 "
           ") "
           "SELECT"
           "  wt.payto_uri AS account_details"
           " ,ed.expiration_date"
           " ,ed.reserve_pub"
           " ,ed.current_balance"
           " FROM wire_targets wt"
           " JOIN ed"
           "   ON (ed.wire_source_h_payto=wt.wire_target_h_payto);");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "get_expired_reserves",
                                             params,
                                             &reserve_expired_cb,
                                             &ectx);
  switch (ectx.status)
  {
  case GNUNET_SYSERR:
    return GNUNET_DB_STATUS_HARD_ERROR;
  case GNUNET_NO:
    return GNUNET_DB_STATUS_SOFT_ERROR;
  case GNUNET_OK:
    break;
  }
  return qs;
}
