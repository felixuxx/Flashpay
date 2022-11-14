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
 * @file exchangedb/pg_start_deferred_wire_out.c
 * @brief Implementation of the start_deferred_wire_out function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_start_deferred_wire_out.h"
#include "pg_helper.h"
#include "pg_preflight.h"
#include "pg_rollback.h"

enum GNUNET_GenericReturnValue
TEH_PG_start_deferred_wire_out (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute (
      "START TRANSACTION ISOLATION LEVEL READ COMMITTED;"),
    GNUNET_PQ_make_execute ("SET CONSTRAINTS ALL DEFERRED;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  if (GNUNET_SYSERR ==
      TEH_PG_preflight (pg))
    return GNUNET_SYSERR;
  if (GNUNET_OK !=
      GNUNET_PQ_exec_statements (pg->conn,
                                 es))
  {
    TALER_LOG_ERROR (
      "Failed to defer wire_out_ref constraint on transaction\n");
    GNUNET_break (0);
    TEH_PG_rollback (pg);
    return GNUNET_SYSERR;
  }
  pg->transaction_name = "deferred wire out";
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting READ COMMITTED DEFERRED transaction `%s'\n",
              pg->transaction_name);
  return GNUNET_OK;
}
