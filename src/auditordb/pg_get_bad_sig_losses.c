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
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_helper.h"
#include "pg_get_bad_sig_losses.h"


struct BadSigLossesContext
{

  /**
   * Function to call for each bad sig loss.
   */
  TALER_AUDITORDB_BadSigLossesCallback cb;

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
 * Helper function for #TAH_PG_get_bad_sig_losses().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct BadSigLossesContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
bad_sig_losses_cb (void *cls,
                   PGresult *result,
                   unsigned int num_results)
{
  struct BadSigLossesContext *dcc = cls;
  struct PostgresClosure *pg = dcc->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_AUDITORDB_BadSigLosses dc;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("row_id",
                                    &dc.row_id),
      GNUNET_PQ_result_spec_uint64 ("problem_row_id",
                                    &dc.problem_row_id),
      GNUNET_PQ_result_spec_string ("operation",
                                    &dc.operation),
      TALER_PQ_RESULT_SPEC_AMOUNT ("loss",
                                   &dc.loss),
      GNUNET_PQ_result_spec_auto_from_type ("operation_specific_pub",
                                            &dc.operation_specific_pub),
      GNUNET_PQ_result_spec_bool ("suppressed",
                                  &dc.suppressed),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_GenericReturnValue rval;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      dcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    dcc->qs = i + 1;
    rval = dcc->cb (dcc->cb_cls,
                    &dc);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != rval)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TAH_PG_get_bad_sig_losses (
  void *cls,
  int64_t limit,
  uint64_t offset,
  bool return_suppressed,
  const struct GNUNET_CRYPTO_EddsaPublicKey *op_spec_pub,
  const char *op,
  TALER_AUDITORDB_BadSigLossesCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  uint64_t plimit = (uint64_t) ((limit < 0) ? -limit : limit);
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&offset),
    GNUNET_PQ_query_param_bool (return_suppressed),
    GNUNET_PQ_query_param_uint64 (&plimit),
    NULL == op_spec_pub
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_auto_from_type (op_spec_pub),
    NULL == op
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_string (op),
    GNUNET_PQ_query_param_end
  };
  struct BadSigLossesContext dcc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "auditor_bad_sig_losses_get_desc",
           "SELECT"
           " row_id"
           ",problem_row_id"
           ",operation"
           ",loss"
           ",operation_specific_pub"
           ",suppressed"
           " FROM auditor_bad_sig_losses"
           " WHERE (row_id < $1)"
           " AND ($2 OR NOT suppressed)"
           " AND ($4::BYTEA IS NULL OR operation_specific_pub = $4)"
           " AND ($5::TEXT IS NULL OR operation = $5)"
           " ORDER BY row_id DESC"
           " LIMIT $3"
           );
  PREPARE (pg,
           "auditor_bad_sig_losses_get_asc",
           "SELECT"
           " row_id"
           ",problem_row_id"
           ",operation"
           ",loss"
           ",operation_specific_pub"
           ",suppressed"
           " FROM auditor_bad_sig_losses"
           " WHERE (row_id > $1)"
           " AND ($2 OR NOT suppressed)"
           " AND ($4::BYTEA IS NULL OR operation_specific_pub = $4)"
           " AND ($5::TEXT IS NULL OR operation = $5)"
           " ORDER BY row_id ASC"
           " LIMIT $3"
           );
  qs = GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    (limit > 0)
    ? "auditor_bad_sig_losses_get_asc"
    : "auditor_bad_sig_losses_get_desc",
    params,
    &bad_sig_losses_cb,
    &dcc);
  if (qs > 0)
    return dcc.qs;
  GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
  return qs;
}
