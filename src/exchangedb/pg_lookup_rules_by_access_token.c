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
 * @file exchangedb/pg_lookup_rules_by_access_token.c
 * @brief Implementation of the lookup_rules_by_access_token function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_rules_by_access_token.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_lookup_rules_by_access_token (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  json_t **jnew_rules,
  uint64_t *rowid)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_allow_null (
      TALER_PQ_result_spec_json (
        "jnew_rules",
        jnew_rules),
      NULL),
    GNUNET_PQ_result_spec_uint64 (
      "row_id",
      rowid),
    GNUNET_PQ_result_spec_end
  };

  *jnew_rules = NULL;
  PREPARE (pg,
           "lookup_rules_by_access_token",
           "SELECT"
           " jnew_rules"
           ",outcome_serial_id AS row_id"
           " FROM legitimization_outcomes"
           " WHERE h_payto=$1"
           "   AND is_active"
           " ORDER BY expiration_time DESC,"
           "          outcome_serial_id DESC"
           " LIMIT 1;");
  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "lookup_rules_by_access_token",
    params,
    rs);
}
