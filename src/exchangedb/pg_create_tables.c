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
 * @file exchangedb/pg_create_tables.c
 * @brief Implementation of the create_tables function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_create_tables.h"
#include "pg_helper.h"


enum GNUNET_GenericReturnValue
TEH_PG_create_tables (void *cls,
                      bool support_partitions,
                      uint32_t num_partitions)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_Context *conn;
  enum GNUNET_GenericReturnValue ret;
  struct GNUNET_PQ_QueryParam params[] = {
    support_partitions
    ? GNUNET_PQ_query_param_uint32 (&num_partitions)
    : GNUNET_PQ_query_param_null (),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_try_execute ("SET search_path TO exchange;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                     "exchangedb-postgres",
                                     "exchange-",
                                     es,
                                     NULL);
  if (NULL == conn)
    return GNUNET_SYSERR;
  ret = GNUNET_PQ_exec_sql (conn,
                            "procedures");
  GNUNET_break (GNUNET_OK == ret);
  if (GNUNET_OK == ret)
  {
    struct GNUNET_PQ_Context *tconn;

    tconn = pg->conn;
    pg->conn = conn;
    PREPARE (pg,
             "create_tables",
             "SELECT"
             " exchange_do_create_tables"
             " ($1::INTEGER);");
    pg->conn = tconn;
    if (0 >
        GNUNET_PQ_eval_prepared_non_select (conn,
                                            "create_tables",
                                            params))
      ret = GNUNET_SYSERR;
  }
  GNUNET_PQ_disconnect (conn);
  return ret;
}
