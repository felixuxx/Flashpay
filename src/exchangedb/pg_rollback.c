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
 * @file exchangedb/pg_rollback.c
 * @brief Implementation of the rollback function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_rollback.h"
#include "pg_helper.h"


void
TEH_PG_rollback (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("ROLLBACK"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  if (NULL == pg->transaction_name)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Skipping rollback, no transaction active\n");
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Rolling back transaction\n");
  GNUNET_break (GNUNET_OK ==
                GNUNET_PQ_exec_statements (pg->conn,
                                           es));
  pg->transaction_name = NULL;
}
