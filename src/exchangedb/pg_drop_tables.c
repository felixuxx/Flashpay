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
 * @file exchangedb/pg_drop_tables.c
 * @brief Implementation of the drop_tables function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_drop_tables.h"
#include "pg_helper.h"


/**
 * Drop all Taler tables.  This should only be used by testcases.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
enum GNUNET_GenericReturnValue
TEH_PG_drop_tables (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_Context *conn;
  enum GNUNET_GenericReturnValue ret;

  if (NULL != pg->conn)
  {
    GNUNET_PQ_disconnect (pg->conn);
    pg->conn = NULL;
    pg->init = false;
  }
  conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                     "exchangedb-postgres",
                                     NULL,
                                     NULL,
                                     NULL);
  if (NULL == conn)
    return GNUNET_SYSERR;
  ret = GNUNET_PQ_exec_sql (conn,
                            "drop");
  GNUNET_PQ_disconnect (conn);
  return ret;
}
