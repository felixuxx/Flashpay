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
 * @file exchangedb/pg_select_satisfied_kyc_processes.c
 * @brief Implementation of the select_satisfied_kyc_processes function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_satisfied_kyc_processes.h"
#include "pg_helper.h"


/**
 * Closure for #get_legitimizations_cb().
 */
struct GetLegitimizationsContext
{
  /**
   * Function to call per result.
   */
  TALER_EXCHANGEDB_SatisfiedProviderCallback cb;

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
 * @param cls a `struct GetLegitimizationsContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
get_legitimizations_cb (void *cls,
                        PGresult *result,
                        unsigned int num_results)
{
  struct GetLegitimizationsContext *ctx = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    char *provider_section;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_string ("provider_section",
                                    &provider_section),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->status = GNUNET_SYSERR;
      return;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Found satisfied LEGI: %s\n",
                provider_section);
    ctx->cb (ctx->cb_cls,
             provider_section);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_satisfied_kyc_processes (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  TALER_EXCHANGEDB_SatisfiedProviderCallback spc,
  void *spc_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now
    = GNUNET_TIME_absolute_get ();
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  struct GetLegitimizationsContext ctx = {
    .cb = spc,
    .cb_cls = spc_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "get_satisfied_legitimizations",
           "SELECT "
           " provider_section"
           " FROM legitimization_processes"
           " WHERE h_payto=$1"
           "   AND expiration_time>=$2;");
  qs = GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    "get_satisfied_legitimizations",
    params,
    &get_legitimizations_cb,
    &ctx);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Satisfied LEGI check returned %d\n",
              qs);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
