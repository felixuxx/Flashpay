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
 * @file exchangedb/pg_lookup_pending_legitimization.c
 * @brief Implementation of the lookup_pending_legitimization function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_pending_legitimization.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_lookup_pending_legitimization (
  void *cls,
  uint64_t legitimization_measure_serial_id,
  const struct TALER_AccountAccessTokenP *access_token,
  struct TALER_PaytoHashP *h_payto,
  json_t **jmeasures)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&legitimization_measure_serial_id),
    GNUNET_PQ_query_param_auto_from_type (access_token),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_json ("jmeasures",
                               jmeasures),
    GNUNET_PQ_result_spec_auto_from_type ("wire_target_h_payto",
                                          h_payto),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "lookup_pending_legitimization",
           "SELECT "
           " lm.jmeasures"
           ",wt.wire_target_h_payto"
           " FROM legitimization_measures lm"
           " JOIN wire_targets wt"
           "   ON (lm.access_token = wt.access_token)"
           " WHERE legitimization_measure_serial_id=$1"
           "   AND access_token=$1"
           "   AND NOT is_finished;");
  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "lookup_pending_legitimization",
    params,
    rs);
}
