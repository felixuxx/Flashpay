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
 * @file exchangedb/pg_lookup_aml_history.c
 * @brief Implementation of the lookup_aml_history function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_aml_history.h"
#include "pg_helper.h"


/**
 * Closure for callbacks called from #TEH_PG_lookup_aml_history()
 */
struct AmlHistoryContext
{

  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_AmlHistoryCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to 'true' if the transaction failed.
   */
  bool failed;

};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct AmlHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
handle_aml_entry (void *cls,
                  PGresult *result,
                  unsigned int num_results)
{
  struct AmlHistoryContext *ahc = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct GNUNET_TIME_Timestamp decision_time;
    char *justification;
    struct TALER_AmlOfficerPublicKeyP decider_pub;
    json_t *jproperties;
    json_t *jnew_rules;
    bool to_investigate;
    bool is_active;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_timestamp ("decision_time",
                                       &decision_time),
      GNUNET_PQ_result_spec_string ("justification",
                                    &justification),
      GNUNET_PQ_result_spec_auto_from_type ("decider_pub",
                                            &decider_pub),
      TALER_PQ_result_spec_json ("properties",
                                 &jproperties),
      TALER_PQ_result_spec_json ("new_rules",
                                 &jnew_rules),
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
      ahc->failed = true;
      return;
    }
    ahc->cb (ahc->cb_cls,
             decision_time,
             justification,
             &decider_pub,
             jproperties,
             jnew_rules,
             to_investigate,
             is_active);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_lookup_aml_history (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  TALER_EXCHANGEDB_AmlHistoryCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct AmlHistoryContext ahc = {
    .pg = pg,
    .cb = cb,
    .cb_cls = cb_cls
  };
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "lookup_aml_history",
           "SELECT"
           " ah.decision_time"
           ",ah.justification"
           ",ah.decider_pub"
           ",lo.jproperties"
           ",lo.jnew_rules"
           ",lo.to_investigate"
           ".lo.is_active"
           " FROM aml_history ah"
           " JOIN legitimization_outcomes lo"
           "   USING (outcome_serial_id)"
           " WHERE h_payto=$1"
           " ORDER BY decision_time DESC;");
  qs = GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    "lookup_aml_history",
    params,
    &handle_aml_entry,
    &ahc);
  if (qs <= 0)
    return qs;
  if (ahc.failed)
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return qs;
}
