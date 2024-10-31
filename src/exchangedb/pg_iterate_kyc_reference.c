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
 * @file pg_iterate_kyc_reference.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_iterate_kyc_reference.h"
#include "pg_helper.h"


/**
 * Closure for #iterate_kyc_reference_cb()
 */
struct IteratorContext
{
  /**
   * Function to call with the results.
   */
  TALER_EXCHANGEDB_LegitimizationProcessCallback cb;

  /**
   * Closure to pass to @e cb
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;
};


/**
 * Helper function for #TEH_PG_iterate_kyc_reference().
 * Calls the callback with each denomination key.
 *
 * @param cls a `struct IteratorContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
iterate_kyc_reference_cb (void *cls,
                          PGresult *result,
                          unsigned int num_results)
{
  struct IteratorContext *ic = cls;

  for (unsigned int i = 0; i<num_results; i++)
  {
    char *kyc_provider_name_name;
    char *provider_user_id;
    char *legitimization_id;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_string ("provider_name",
                                    &kyc_provider_name_name),
      GNUNET_PQ_result_spec_string ("provider_user_id",
                                    &provider_user_id),
      GNUNET_PQ_result_spec_string ("provider_legitimization_id",
                                    &legitimization_id),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      return;
    }
    ic->cb (ic->cb_cls,
            kyc_provider_name_name,
            provider_user_id,
            legitimization_id);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_iterate_kyc_reference (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  TALER_EXCHANGEDB_LegitimizationProcessCallback lpc,
  void *lpc_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_end
  };
  struct IteratorContext ic = {
    .cb = lpc,
    .cb_cls = lpc_cls,
    .pg = pg
  };

  PREPARE (pg,
           "iterate_kyc_reference",
           "SELECT "
           " provider_name"
           ",provider_user_id"
           ",provider_legitimization_id"
           " FROM legitimization_processes"
           " WHERE h_payto=$1;");
  return GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    "iterate_kyc_reference",
    params,
    &iterate_kyc_reference_cb,
    &ic);
}
