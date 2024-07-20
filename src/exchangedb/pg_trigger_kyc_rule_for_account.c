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
 * @file exchangedb/pg_trigger_kyc_rule_for_account.c
 * @brief Implementation of the trigger_kyc_rule_for_account function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_trigger_kyc_rule_for_account.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_trigger_kyc_rule_for_account (
  void *cls,
  const char *payto_uri,
  const struct TALER_PaytoHashP *h_payto,
  const json_t *jmeasures,
  uint32_t display_priority,
  uint64_t *requirement_row)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now
    = GNUNET_TIME_absolute_get ();
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_string (payto_uri),
    GNUNET_PQ_query_param_absolute_time (&now),
    TALER_PQ_query_param_json (jmeasures),
    GNUNET_PQ_query_param_uint32 (&display_priority),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 (
      "legitimization_measure_serial_id",
      requirement_row),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "trigger_kyc_rule_for_account",
           "SELECT"
           "  out_legitimization_measure_serial_id"
           "    AS legitimization_measure_serial_id"
           " FROM exchange_do_trigger_kyc_rule_for_account"
           "($1, $2, $3, $4, $5);");

  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "trigger_kyc_rule_for_account",
    params,
    rs);
}
