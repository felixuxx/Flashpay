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
 * @file exchangedb/pg_insert_kyc_failure.c
 * @brief Implementation of the insert_kyc_failure function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_kyc_failure.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_insert_kyc_failure (
  void *cls,
  uint64_t process_row,
  const struct TALER_PaytoHashP *h_payto,
  const char *provider_section,
  const char *provider_account_id,
  const char *provider_legitimization_id)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&process_row),
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_string (provider_section),
    NULL != provider_account_id
    ? GNUNET_PQ_query_param_string (provider_account_id)
    : GNUNET_PQ_query_param_null (),
    NULL != provider_legitimization_id
    ? GNUNET_PQ_query_param_string (provider_legitimization_id)
    : GNUNET_PQ_query_param_null (),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_kyc_failure",
           "UPDATE legitimization_processes"
           " SET"
           "  finished=TRUE"
           " ,provider_account_id=$4"
           " ,provider_legitimization_id=$5"
           " WHERE h_payto=$2"
           "   AND legitimization_process_serial_id=$1"
           "   AND provider_section=$3;");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_kyc_failure",
                                             params);
}
