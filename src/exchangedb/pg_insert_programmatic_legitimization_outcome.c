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
 * @file exchangedb/pg_insert_programmatic_legitimization_outcome.c
 * @brief Implementation of the insert_programmatic_legitimization_outcome function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_programmatic_legitimization_outcome.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_programmatic_legitimization_outcome (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  struct GNUNET_TIME_Timestamp decision_time,
  struct GNUNET_TIME_Absolute expiration_time,
  const json_t *account_properties,
  bool to_investigate,
  const json_t *new_rules,
  unsigned int num_events,
  const char **events)
{
  struct PostgresClosure *pg = cls;
  struct TALER_KycCompletedEventP rep = {
    .header.size = htons (sizeof (rep)),
    .header.type = htons (TALER_DBEVENT_EXCHANGE_KYC_COMPLETED),
    .h_payto = *h_payto
  };

  char *notify_s
    = GNUNET_PQ_get_event_notify_channel (&rep.header);
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_timestamp (&decision_time),
    GNUNET_PQ_query_param_absolute_time (&expiration_time),
    NULL != account_properties
    ? TALER_PQ_query_param_json (account_properties)
    : GNUNET_PQ_query_param_null (),
    TALER_PQ_query_param_json (new_rules),
    GNUNET_PQ_query_param_bool (to_investigate),
    GNUNET_PQ_query_param_array_ptrs_string (num_events,
                                             events,
                                             pg->conn),
    GNUNET_PQ_query_param_string (notify_s),
    GNUNET_PQ_query_param_end
  };
  bool unknown_account;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("out_account_unknown",
                                &unknown_account),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "do_insert_programmatic_legitimization_outcome",
           "SELECT"
           " out_account_unknown"
           " FROM exchange_do_insert_programmatic_legitimization_decision"
           "($1, $2, $3, $4, $5, $6, $7, $8);");
  qs = GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "do_insert_programmatic_legitimization_outcome",
    params,
    rs);
  GNUNET_PQ_cleanup_query_params_closures (params);
  GNUNET_free (notify_s);
  GNUNET_PQ_event_do_poll (pg->conn);
  if (qs <= 0)
    return qs;
  if (unknown_account)
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  return qs;
}
