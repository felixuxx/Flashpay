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
 * @file exchangedb/pg_select_aml_decisions.c
 * @brief Implementation of the select_aml_decisions function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_aml_decisions.h"
#include "pg_helper.h"


/**
 * Closure for #handle_aml_result.
 */
struct AmlProcessResultContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_AmlDecisionCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to #GNUNET_SYSERR on serious errors.
   */
  enum GNUNET_GenericReturnValue status;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.  Helper function
 * for #TEH_PG_select_aml_process().
 *
 * @param cls closure of type `struct AmlProcessResultContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
handle_aml_result (void *cls,
                   PGresult *result,
                   unsigned int num_results)
{
  struct AmlProcessResultContext *ctx = cls;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_PaytoHashP h_payto;
    uint64_t rowid;
    char *justification = NULL;
    struct GNUNET_TIME_Timestamp decision_time;
    struct GNUNET_TIME_Absolute expiration_time;
    json_t *jproperties = NULL;
    bool to_investigate;
    bool is_active;
    json_t *account_rules;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("outcome_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("h_payto",
                                            &h_payto),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("justification",
                                      &justification),
        NULL),
      GNUNET_PQ_result_spec_timestamp ("decision_time",
                                       &decision_time),
      GNUNET_PQ_result_spec_absolute_time ("expiration_time",
                                           &expiration_time),
      GNUNET_PQ_result_spec_allow_null (
        TALER_PQ_result_spec_json ("jproperties",
                                   &jproperties),
        NULL),
      TALER_PQ_result_spec_json ("jnew_rules",
                                 &account_rules),
      GNUNET_PQ_result_spec_bool ("to_investigate",
                                  &to_investigate),
      GNUNET_PQ_result_spec_bool ("is_active",
                                  &is_active),
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
    if (GNUNET_TIME_absolute_is_past (expiration_time))
      is_active = false;
    ctx->cb (ctx->cb_cls,
             rowid,
             justification,
             &h_payto,
             decision_time,
             expiration_time,
             jproperties,
             to_investigate,
             is_active,
             account_rules);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_aml_decisions (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  enum TALER_EXCHANGE_YesNoAll investigation_only,
  enum TALER_EXCHANGE_YesNoAll active_only,
  uint64_t offset,
  int64_t limit,
  TALER_EXCHANGEDB_AmlDecisionCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  uint64_t ulimit = (limit > 0) ? limit : -limit;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_bool (NULL == h_payto),
    NULL == h_payto
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_bool ((TALER_EXCHANGE_YNA_ALL ==
                                 investigation_only)),
    GNUNET_PQ_query_param_bool ((TALER_EXCHANGE_YNA_YES ==
                                 investigation_only)),
    GNUNET_PQ_query_param_bool ((TALER_EXCHANGE_YNA_ALL ==
                                 active_only)),
    GNUNET_PQ_query_param_bool ((TALER_EXCHANGE_YNA_YES ==
                                 active_only)),
    GNUNET_PQ_query_param_uint64 (&offset),
    GNUNET_PQ_query_param_uint64 (&ulimit),
    GNUNET_PQ_query_param_end
  };
  struct AmlProcessResultContext ctx = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;
  const char *stmt = (limit > 0)
    ? "select_aml_decisions_inc"
    : "select_aml_decisions_dec";

  PREPARE (pg,
           "select_aml_decisions_inc",
           "SELECT"
           " lo.outcome_serial_id"
           ",lo.h_payto"
           ",ah.justification"
           ",lo.decision_time"
           ",lo.expiration_time"
           ",lo.jproperties"
           ",lo.to_investigate"
           ",lo.is_active"
           ",lo.jnew_rules"
           " FROM legitimization_outcomes lo"
           " LEFT JOIN aml_history ah"
           "   USING (outcome_serial_id)"
           " WHERE (outcome_serial_id > $7)"
           "   AND ($1 OR (lo.h_payto = $2))"
           "   AND ($3 OR (lo.to_investigate = $4))"
           "   AND ($5 OR (lo.is_active = $6))"
           " ORDER BY lo.outcome_serial_id ASC"
           " LIMIT $8");
  PREPARE (pg,
           "select_aml_decisions_dec",
           "SELECT"
           " lo.outcome_serial_id"
           ",lo.h_payto"
           ",ah.justification"
           ",lo.decision_time"
           ",lo.expiration_time"
           ",lo.jproperties"
           ",lo.to_investigate"
           ",lo.is_active"
           ",lo.jnew_rules"
           " FROM legitimization_outcomes lo"
           " LEFT JOIN aml_history ah"
           "   USING (outcome_serial_id)"
           " WHERE lo.outcome_serial_id < $7"
           "  AND ($1 OR (lo.h_payto = $2))"
           "  AND ($3 OR (lo.to_investigate = $4))"
           "  AND ($5 OR (lo.is_active = $6))"
           " ORDER BY lo.outcome_serial_id DESC"
           " LIMIT $8");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             stmt,
                                             params,
                                             &handle_aml_result,
                                             &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
