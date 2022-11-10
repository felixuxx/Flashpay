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
 * @file exchangedb/pg_setup_partitions.c
 * @brief Implementation of the setup_partitions function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_setup_partitions.h"
#include "pg_helper.h"

/**
 * Setup partitions of already existing tables
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param num the number of partitions to create for each partitioned table
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
enum GNUNET_GenericReturnValue
TEH_PG_setup_partitions (void *cls,
                           uint32_t num)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_Context *conn;
  enum GNUNET_GenericReturnValue ret = GNUNET_OK;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint32 (&num),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_PreparedStatement ps[] = {
    GNUNET_PQ_make_prepare ("setup_partitions",
                            "SELECT"
                            " create_partitions"
                            " ($1);"),
    GNUNET_PQ_PREPARED_STATEMENT_END
  };
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_try_execute ("SET search_path TO exchange;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                     "exchangedb-postgres",
                                     NULL,
                                     es,
                                     ps);
  if (NULL == conn)
    return GNUNET_SYSERR;
  ret = GNUNET_OK;
  if (0 > GNUNET_PQ_eval_prepared_non_select (conn,
                                              "setup_partitions",
                                              params))
    ret = GNUNET_SYSERR;
  GNUNET_PQ_disconnect (conn);
  return ret;
}

