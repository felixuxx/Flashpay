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
 * @file exchangedb/pg_insert_auditor.c
 * @brief Implementation of the insert_auditor function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_auditor.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_insert_auditor (void *cls,
                         const struct TALER_AuditorPublicKeyP *auditor_pub,
                         const char *auditor_url,
                         const char *auditor_name,
                         struct GNUNET_TIME_Timestamp start_date)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (auditor_pub),
    GNUNET_PQ_query_param_string (auditor_name),
    GNUNET_PQ_query_param_string (auditor_url),
    GNUNET_PQ_query_param_timestamp (&start_date),
    GNUNET_PQ_query_param_end
  };

      /* used in #postgres_insert_auditor() */
  PREPARE (pg,
           "insert_auditor",
           "INSERT INTO auditors "
           "(auditor_pub"
           ",auditor_name"
           ",auditor_url"
           ",is_active"
           ",last_change"
           ") VALUES "
           "($1, $2, $3, true, $4);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_auditor",
                                             params);
}
