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
 * @file exchangedb/pg_insert_kyc_requirement_process.c
 * @brief Implementation of the insert_kyc_requirement_process function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_kyc_requirement_process.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_insert_kyc_requirement_process (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const char *provider_section,
  const char *provider_account_id,
  const char *provider_legitimization_id,
  uint64_t *process_row)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_string (provider_section),
    (NULL != provider_account_id)
    ? GNUNET_PQ_query_param_string (provider_account_id)
    : GNUNET_PQ_query_param_null (),
    (NULL != provider_legitimization_id)
    ? GNUNET_PQ_query_param_string (provider_legitimization_id)
    : GNUNET_PQ_query_param_null (),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("legitimization_process_serial_id",
                                  process_row),
    GNUNET_PQ_result_spec_end
  };

  /* Used in #postgres_insert_kyc_requirement_process() */
  PREPARE (pg,
           "insert_legitimization_process",
           "INSERT INTO legitimization_processes"
           "  (h_payto"
           "  ,provider_section"
           "  ,provider_user_id"
           "  ,provider_legitimization_id"
           "  ) VALUES "
           "  ($1, $2, $3, $4)"
           " ON CONFLICT (h_payto,provider_section) "
           "   DO UPDATE SET"
           "      provider_user_id=$3"
           "     ,provider_legitimization_id=$4"
           " RETURNING legitimization_process_serial_id");
  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "insert_legitimization_process",
    params,
    rs);
}
