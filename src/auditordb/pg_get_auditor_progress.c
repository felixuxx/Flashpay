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
 * @file pg_get_auditor_progress.c
 * @brief Implementation of get_auditor_progress function
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_auditor_progress.h"
#include "pg_helper.h"


/**
 * Closure for #auditor_progress_cb().
 */
struct AuditorProgressContext
{

  /**
   * Where to store results.
   */
  uint64_t **dst;

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
 * Helper function for #TAH_PG_get_auditor_progress().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct AuditorProgressContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
auditor_progress_cb (void *cls,
                     PGresult *result,
                     unsigned int num_results)
{
  struct AuditorProgressContext *ctx = cls;

  GNUNET_assert (num_results == ctx->len);
  for (unsigned int i = 0; i < num_results; i++)
  {
    bool is_missing = false;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_uint64 ("progress_offset",
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
      *ctx->dst[i] = 0;
    ctx->off++;
  }
}


enum GNUNET_DB_QueryStatus
TAH_PG_get_auditor_progress (void *cls,
                             const char *progress_key,
                             uint64_t *progress_offset,
                             ...)
{
  struct PostgresClosure *pg = cls;
  unsigned int cnt = 1;
  va_list ap;

  va_start (ap,
            progress_offset);
  while (NULL != va_arg (ap,
                         const char *))
  {
    cnt++;
    (void) va_arg (ap,
                   uint64_t *);
  }
  va_end (ap);
  {
    const char *keys[cnt];
    uint64_t *dsts[cnt];
    unsigned int off = 1;
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_array_ptrs_string (cnt,
                                               keys,
                                               pg->conn),
      GNUNET_PQ_query_param_end
    };
    struct AuditorProgressContext ctx = {
      .dst = dsts,
      .len = cnt,
      .pg = pg
    };
    enum GNUNET_DB_QueryStatus qs;

    keys[0] = progress_key;
    dsts[0] = progress_offset;
    va_start (ap,
              progress_offset);
    while (off < cnt)
    {
      keys[off] = va_arg (ap,
                          const char *);
      dsts[off] = va_arg (ap,
                          uint64_t *);
      off++;
    }
    GNUNET_assert (NULL == va_arg (ap,
                                   const char *));
    va_end (ap);

    PREPARE (pg,
             "get_auditor_progress",
             "SELECT"
             " auditor_do_get_auditor_progress AS progress_offset"
             " FROM auditor_do_get_auditor_progress "
             "($1);");
    ctx.off = 0;
    qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               "get_auditor_progress",
                                               params,
                                               &auditor_progress_cb,
                                               &ctx);
    GNUNET_PQ_cleanup_query_params_closures (params);
    if (ctx.failure)
      return GNUNET_DB_STATUS_HARD_ERROR;
    if (qs < 0)
      return qs;
    GNUNET_assert (ctx.off == cnt);
    return qs;
  }
}
