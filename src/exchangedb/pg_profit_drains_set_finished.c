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
 * @file exchangedb/pg_profit_drains_set_finished.c
 * @brief Implementation of the profit_drains_set_finished function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_profit_drains_set_finished.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_profit_drains_set_finished (
  void *cls,
  uint64_t serial)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "drain_profit_set_finished",
           "UPDATE profit_drains"
           " SET"
           " executed=TRUE"
           " WHERE profit_drain_serial_id=$1;");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "drain_profit_set_finished",
                                             params);
}
