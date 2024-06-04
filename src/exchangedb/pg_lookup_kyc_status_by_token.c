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
 * @file exchangedb/pg_lookup_kyc_status_by_token.c
 * @brief Implementation of the lookup_kyc_status_by_token function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_kyc_status_by_token.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_lookup_kyc_status_by_token (
  void *cls,
  const struct TALER_AccountAccessTokenP *access_token,
  uint64_t *row,
  json_t **jmeasures)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (access_token),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 (
      "legitimization_measure_serial_id",
      row),
    TALER_PQ_result_spec_json (
      "jmeasures",
      jmeasures),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "lookup_kyc_status_by_token",
           "SELECT"
           " legitimization_measure_serial_id"
           ",jmeasures"
           " FROM legitimization_measures"
           " WHERE access_token=$1"
           "   AND NOT is_finished"
           " ORDER BY display_priority DESC"
           " LIMIT 1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "lookup_kyc_status_by_token",
                                                   params,
                                                   rs);
}
