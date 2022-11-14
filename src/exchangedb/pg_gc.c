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
 * @file exchangedb/pg_gc.c
 * @brief Implementation of the gc function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_gc.h"
#include "pg_helper.h"


enum GNUNET_GenericReturnValue
TEH_PG_gc (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now = GNUNET_TIME_absolute_get ();
  struct GNUNET_TIME_Absolute long_ago;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_absolute_time (&long_ago),
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_Context *conn;
  enum GNUNET_GenericReturnValue ret;

  /* Keep wire fees for 10 years, that should always
     be enough _and_ they are tiny so it does not
     matter to make this tight */
  long_ago = GNUNET_TIME_absolute_subtract (
    now,
    GNUNET_TIME_relative_multiply (
      GNUNET_TIME_UNIT_YEARS,
      10));
  {
    struct GNUNET_PQ_ExecuteStatement es[] = {
      GNUNET_PQ_make_try_execute ("SET search_path TO exchange;"),
      GNUNET_PQ_EXECUTE_STATEMENT_END
    };
    struct GNUNET_PQ_PreparedStatement ps[] = {
      /* Used in #postgres_gc() */
      GNUNET_PQ_make_prepare ("run_gc",
                              "CALL"
                              " exchange_do_gc"
                              " ($1,$2);"),
      GNUNET_PQ_PREPARED_STATEMENT_END
    };

    conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                       "exchangedb-postgres",
                                       NULL,
                                       es,
                                       ps);
  }
  if (NULL == conn)
    return GNUNET_SYSERR;
  ret = GNUNET_OK;
  if (0 > GNUNET_PQ_eval_prepared_non_select (conn,
                                              "run_gc",
                                              params))
    ret = GNUNET_SYSERR;
  GNUNET_PQ_disconnect (conn);
  return ret;
}
