/*
   This file is part of TALER
   Copyright (C) 2022 Taler Systems SA

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
 * @file exchangedb/pg_kyc_provider_account_lookup.c
 * @brief Implementation of the kyc_provider_account_lookup function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_kyc_provider_account_lookup.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_kyc_provider_account_lookup (
  void *cls,
  const char *provider_name,
  const char *provider_legitimization_id,
  struct TALER_NormalizedPaytoHashP *h_payto,
  uint64_t *process_row)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (provider_legitimization_id),
    GNUNET_PQ_query_param_string (provider_name),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("h_payto",
                                          h_payto),
    GNUNET_PQ_result_spec_uint64 ("legitimization_process_serial_id",
                                  process_row),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "get_wire_target_by_legitimization_id",
           "SELECT "
           " h_payto"
           ",legitimization_process_serial_id"
           " FROM legitimization_processes"
           " WHERE provider_legitimization_id=$1"
           "   AND provider_name=$2;");
  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "get_wire_target_by_legitimization_id",
    params,
    rs);
}
