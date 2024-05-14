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
 * @file exchangedb/pg_lookup_kyc_process_by_account.c
 * @brief Implementation of the lookup_kyc_process_by_account function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_kyc_process_by_account.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_lookup_kyc_process_by_account (
  void *cls,
  const char *provider_name,
  const struct TALER_PaytoHashP *h_payto,
  uint64_t *process_row,
  struct GNUNET_TIME_Absolute *expiration,
  char **provider_account_id,
  char **provider_legitimization_id)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_string (provider_name),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("legitimization_process_serial_id",
                                  process_row),
    GNUNET_PQ_result_spec_absolute_time ("expiration_time",
                                         expiration),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_string ("provider_user_id",
                                    provider_account_id),
      NULL),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_string ("provider_legitimization_id",
                                    provider_legitimization_id),
      NULL),
    GNUNET_PQ_result_spec_end
  };

  *provider_account_id = NULL;
  *provider_legitimization_id = NULL;
  PREPARE (pg,
           "lookup_process_by_account",
           "SELECT "
           " legitimization_process_serial_id"
           ",expiration_time"
           ",provider_user_id"
           ",provider_legitimization_id"
           " FROM legitimization_processes"
           " WHERE h_payto=$1"
           "   AND provider_name=$2"
           "   AND NOT finished"
           /* Note: there *should* only be one unfinished
              match, so this is just to be safe(r): */
           " ORDER BY expiration_time DESC"
           " LIMIT 1;");
  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "lookup_process_by_account",
    params,
    rs);
}
