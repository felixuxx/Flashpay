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
 * @file exchangedb/pg_update_auditor.c
 * @brief Implementation of the update_auditor function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_update_auditor.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_update_auditor (void *cls,
                         const struct TALER_AuditorPublicKeyP *auditor_pub,
                         const char *auditor_url,
                         const char *auditor_name,
                         struct GNUNET_TIME_Timestamp change_date,
                         bool enabled)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (auditor_pub),
    GNUNET_PQ_query_param_string (auditor_url),
    GNUNET_PQ_query_param_string (auditor_name),
    GNUNET_PQ_query_param_bool (enabled),
    GNUNET_PQ_query_param_timestamp (&change_date),
    GNUNET_PQ_query_param_end
  };
    /* used in #postgres_update_auditor() */
  PREPARE(pg,
          "update_auditor",
          "UPDATE auditors"
          " SET"
          "  auditor_url=$2"
          " ,auditor_name=$3"
          " ,is_active=$4"
          " ,last_change=$5"
          " WHERE auditor_pub=$1");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "update_auditor",
                                             params);
}
