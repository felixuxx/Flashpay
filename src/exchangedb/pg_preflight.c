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
 * @file exchangedb/pg_preflight.c
 * @brief Implementation of the preflight function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_preflight.h"
#include "pg_helper.h"
#include "plugin_exchangedb_postgres.h"


/**
 * Connect to the database if the connection does not exist yet
 * and check that we are ready to operate.
 *
 * @param pg the plugin-specific state
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
internal_setup (struct PostgresClosure *pg)
{
  if (NULL == pg->conn)
  {
#if AUTO_EXPLAIN
    /* Enable verbose logging to see where queries do not
       properly use indices */
    struct GNUNET_PQ_ExecuteStatement es[] = {
      GNUNET_PQ_make_try_execute ("LOAD 'auto_explain';"),
      GNUNET_PQ_make_try_execute ("SET auto_explain.log_min_duration=50;"),
      GNUNET_PQ_make_try_execute ("SET auto_explain.log_timing=TRUE;"),
      GNUNET_PQ_make_try_execute ("SET auto_explain.log_analyze=TRUE;"),
      /* https://wiki.postgresql.org/wiki/Serializable suggests to really
         force the default to 'serializable' if SSI is to be used. */
      GNUNET_PQ_make_try_execute (
        "SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;"),
      GNUNET_PQ_make_try_execute ("SET enable_sort=OFF;"),
      GNUNET_PQ_make_try_execute ("SET enable_seqscan=OFF;"),
      GNUNET_PQ_make_try_execute ("SET search_path TO exchange;"),
      /* Mergejoin causes issues, see Postgres #18380 */
      GNUNET_PQ_make_try_execute ("SET enable_mergejoin=OFF;"),
      GNUNET_PQ_EXECUTE_STATEMENT_END
    };
#else
    struct GNUNET_PQ_ExecuteStatement es[] = {
      GNUNET_PQ_make_try_execute (
        "SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;"),
      GNUNET_PQ_make_try_execute ("SET enable_sort=OFF;"),
      GNUNET_PQ_make_try_execute ("SET enable_seqscan=OFF;"),
      /* Mergejoin causes issues, see Postgres #18380 */
      GNUNET_PQ_make_try_execute ("SET enable_mergejoin=OFF;"),
      GNUNET_PQ_make_try_execute ("SET search_path TO exchange;"),
      GNUNET_PQ_EXECUTE_STATEMENT_END
    };
#endif
    struct GNUNET_PQ_Context *db_conn;

    db_conn = GNUNET_PQ_connect_with_cfg2 (pg->cfg,
                                           "exchangedb-postgres",
                                           "exchange-", /* load_path_suffix */
                                           es,
                                           NULL /* prepared statements */,
                                           GNUNET_PQ_FLAG_CHECK_CURRENT);
    if (NULL == db_conn)
      return GNUNET_SYSERR;

    pg->prep_gen++;
    pg->conn = db_conn;
  }
  if (NULL == pg->transaction_name)
    GNUNET_PQ_reconnect_if_down (pg->conn);
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TEH_PG_preflight (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("ROLLBACK"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  if (GNUNET_OK !=
      internal_setup (pg))
    return GNUNET_SYSERR;
  if (NULL == pg->transaction_name)
    return GNUNET_OK; /* all good */
  if (GNUNET_OK ==
      GNUNET_PQ_exec_statements (pg->conn,
                                 es))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "BUG: Preflight check rolled back transaction `%s'!\n",
                pg->transaction_name);
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "BUG: Preflight check failed to rollback transaction `%s'!\n",
                pg->transaction_name);
  }
  pg->transaction_name = NULL;
  return GNUNET_NO;
}
