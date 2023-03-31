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
 * @file exchangedb/pg_reserves_update.c
 * @brief Implementation of the reserves_update function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_reserves_update.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_reserves_update (void *cls,
                        const struct TALER_EXCHANGEDB_Reserve *reserve)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&reserve->expiry),
    GNUNET_PQ_query_param_timestamp (&reserve->gc),
    TALER_PQ_query_param_amount (&reserve->balance),
    GNUNET_PQ_query_param_auto_from_type (&reserve->pub),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "reserve_update",
           "UPDATE reserves"
           " SET"
           " expiration_date=$1"
           ",gc_date=$2"
           ",current_balance_val=$3"
           ",current_balance_frac=$4"
           " WHERE reserve_pub=$5;");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "reserve_update",
                                             params);
}
