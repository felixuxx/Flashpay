/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

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
 * @file auditordb/pg_get_balance.c
 * @brief Implementation of the get_balance function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_balance.h"
#include "pg_helper.h"


/**
 * Closure for #balance_cb().
 */
struct BalanceContext
{

  /**
   * Where to store results.
   */
  struct TALER_Amount **dst;

  /**
   * Offset in @e dst.
   */
  unsigned int off;

  /**
   * Length of array at @e dst.
   */
  unsigned int len;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to true on failure.
   */
  bool failure;

};


/**
 * Helper function for #TAH_PG_get_balance().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct BalanceContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
balance_cb (void *cls,
            PGresult *result,
            unsigned int num_results)
{
  struct BalanceContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;

  GNUNET_assert (num_results <= ctx->len);
  for (unsigned int i = 0; i < num_results; i++)
  {
    bool is_missing = false;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_allow_null (
        TALER_PQ_result_spec_amount ("balance",
                                     pg->currency,
                                     ctx->dst[i]),
        &is_missing),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->failure = true;
      return;
    }
    if (is_missing)
    {
      TALER_amount_set_zero (pg->currency,
                             ctx->dst[i]);
    }
    ctx->off++;
  }
}


enum GNUNET_DB_QueryStatus
TAH_PG_get_balance (void *cls,
                    const char *balance_key,
                    struct TALER_Amount *balance_value,
                    ...)
{
  struct PostgresClosure *pg = cls;
  unsigned int cnt = 1;
  va_list ap;

  va_start (ap,
            balance_value);
  while (NULL != va_arg (ap,
                         const char *))
  {
    cnt++;
    (void) va_arg (ap,
                   struct TALER_Amount *);
  }
  va_end (ap);
  {
    const char *keys[cnt];
    struct TALER_Amount *dsts[cnt];
    unsigned int off = 1;
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_array_ptrs_string (cnt,
                                               keys,
                                               pg->conn),
      GNUNET_PQ_query_param_end
    };
    struct BalanceContext ctx = {
      .dst = dsts,
      .len = cnt,
      .pg = pg
    };
    enum GNUNET_DB_QueryStatus qs;

    keys[0] = balance_key;
    dsts[0] = balance_value;

    va_start (ap,
              balance_value);
    while (off < cnt)
    {
      keys[off] = va_arg (ap,
                          const char *);
      dsts[off] = va_arg (ap,
                          struct TALER_Amount *);
      off++;
    }
    GNUNET_assert (NULL == va_arg (ap,
                                   const char *));
    va_end (ap);

    PREPARE (pg,
             "get_balance",
             "SELECT "
             " auditor_do_get_balance AS balance"
             " FROM auditor_do_get_balance "
             "($1);");
    qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               "get_balance",
                                               params,
                                               &balance_cb,
                                               &ctx);
    GNUNET_PQ_cleanup_query_params_closures (params);
    if (ctx.failure)
      return GNUNET_DB_STATUS_HARD_ERROR;
    if (qs < 0)
      return qs;
    GNUNET_assert (qs == ctx.off);
    return qs;
  }
}
