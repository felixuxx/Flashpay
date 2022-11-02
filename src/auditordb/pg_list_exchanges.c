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
 * @file pg_list_exchanges.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_list_exchanges.h"
#include "pg_helper.h"


/**
 * Closure for #exchange_info_cb().
 */
struct ExchangeInfoContext
{

  /**
   * Function to call for each exchange.
   */
  TALER_AUDITORDB_ExchangeCallback cb;

  /**
   * Closure for @e cb
   */
  void *cb_cls;

  /**
   * Query status to return.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Helper function for #TAH_PG_list_exchanges().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct ExchangeInfoContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
exchange_info_cb (void *cls,
                  PGresult *result,
                  unsigned int num_results)
{
  struct ExchangeInfoContext *eic = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_MasterPublicKeyP master_pub;
    char *exchange_url;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("master_pub", &master_pub),
      GNUNET_PQ_result_spec_string ("exchange_url", &exchange_url),
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
    eic->cb (eic->cb_cls,
             &master_pub,
             exchange_url);
    GNUNET_free (exchange_url);
  }
}


enum GNUNET_DB_QueryStatus
TAH_PG_list_exchanges (void *cls,
                       TALER_AUDITORDB_ExchangeCallback cb,
                       void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct ExchangeInfoContext eic = {
    .cb = cb,
    .cb_cls = cb_cls
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "auditor_list_exchanges",
           "SELECT"
           " master_pub"
           ",exchange_url"
           " FROM auditor_exchanges");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "auditor_list_exchanges",
                                             params,
                                             &exchange_info_cb,
                                             &eic);
  if (qs > 0)
    return eic.qs;
  GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
  return qs;
}
