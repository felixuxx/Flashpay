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
 * @file exchangedb/pg_lookup_wire_timestamp.c
 * @brief Implementation of the lookup_wire_timestamp function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_wire_timestamp.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_lookup_wire_timestamp (void *cls,
                              const char *payto_uri,
                              struct GNUNET_TIME_Timestamp *last_date)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (payto_uri),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("last_change",
                                     last_date),
    GNUNET_PQ_result_spec_end
  };


  PREPARE (pg,
           "lookup_wire_timestamp",
           "SELECT"
           " last_change"
           " FROM wire_accounts"
           " WHERE payto_uri=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "lookup_wire_timestamp",
                                                   params,
                                                   rs);
}
