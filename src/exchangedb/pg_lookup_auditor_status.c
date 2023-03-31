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
 * @file exchangedb/pg_lookup_auditor_status.c
 * @brief Implementation of the lookup_auditor_status function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_auditor_status.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_lookup_auditor_status (
  void *cls,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  char **auditor_url,
  bool *enabled)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (auditor_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_string ("auditor_url",
                                  auditor_url),
    GNUNET_PQ_result_spec_bool ("is_active",
                                enabled),
    GNUNET_PQ_result_spec_end
  };

  /* Used in #postgres_lookup_auditor_status() */
  PREPARE (pg,
           "lookup_auditor_status",
           "SELECT"
           " auditor_url"
           ",is_active"
           " FROM auditors"
           " WHERE auditor_pub=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "lookup_auditor_status",
                                                   params,
                                                   rs);
}
