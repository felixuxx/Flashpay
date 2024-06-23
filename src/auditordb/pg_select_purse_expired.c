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
 * @file auditordb/pg_select_purse_expired.c
 * @brief Implementation of the select_purse_expired function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_purse_expired.h"
#include "pg_helper.h"


/**
 * Closure for #purse_expired_cb().
 */
struct PurseExpiredContext
{

  /**
   * Function to call for each expired purse.
   */
  TALER_AUDITORDB_ExpiredPurseCallback cb;

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
 * Helper function for #TAH_PG_select_purse_expired().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct PurseExpiredContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
purse_expired_cb (void *cls,
                  PGresult *result,
                  unsigned int num_results)
{
  struct PurseExpiredContext *eic = cls;
  struct PostgresClosure *pg = eic->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_PurseContractPublicKeyP purse_pub;
    struct GNUNET_TIME_Timestamp expiration_date;
    struct TALER_Amount balance;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                            &purse_pub),
      TALER_PQ_RESULT_SPEC_AMOUNT ("balance",
                                   &balance),
      GNUNET_PQ_result_spec_timestamp ("expiration_date",
                                       &expiration_date),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      eic->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    eic->qs = i + 1;
    if (GNUNET_OK !=
        eic->cb (eic->cb_cls,
                 &purse_pub,
                 &balance,
                 expiration_date))
      break;
  }
}


enum GNUNET_DB_QueryStatus
TAH_PG_select_purse_expired (
  void *cls,
  TALER_AUDITORDB_ExpiredPurseCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Timestamp now
    = GNUNET_TIME_timestamp_get ();
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&now),
    GNUNET_PQ_query_param_end
  };
  struct PurseExpiredContext eic = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "auditor_select_expired_purses",
           "SELECT"
           " purse_pub"
           ",expiration_date"
           ",balance"
           " FROM auditor_purses"
           " WHERE expiration_date<$1;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "auditor_select_expired_purses",
                                             params,
                                             &purse_expired_cb,
                                             &eic);
  if (qs > 0)
    return eic.qs;
  GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
  return qs;
}
