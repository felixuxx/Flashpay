/*
   This file is part of TALER
   Copyright (C) 2023 Taler Systems SA

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
 * @file exchangedb/pg_get_pending_kyc_requirement_process.c
 * @brief Implementation of the get_pending_kyc_requirement_process function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_pending_kyc_requirement_process.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_get_pending_kyc_requirement_process (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const char *provider_section,
  char **redirect_url)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (provider_section),
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_string ("redirect_url",
                                    redirect_url),
      NULL),
    GNUNET_PQ_result_spec_end
  };

  *redirect_url = NULL;
  PREPARE (pg,
           "get_pending_kyc_requirement_process",
           "SELECT"
           "  redirect_url"
           " FROM legitimization_processes"
           " WHERE provider_section=$1"
           "  AND h_payto=$2"
           "  AND NOT finished"
           " ORDER BY start_time DESC"
           "  LIMIT 1");
  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "get_pending_kyc_requirement_process",
    params,
    rs);
}
