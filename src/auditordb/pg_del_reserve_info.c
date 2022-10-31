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
 * @file pg_del_reserve_info.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_del_reserve_info.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_del_reserve_info (void *cls,
                         const struct TALER_ReservePublicKeyP *reserve_pub,
                         const struct TALER_MasterPublicKeyP *master_pub)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_reserves_delete",
           "DELETE"
           " FROM auditor_reserves"
           " WHERE reserve_pub=$1"
           " AND master_pub=$2;");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_reserves_delete",
                                             params);
}
