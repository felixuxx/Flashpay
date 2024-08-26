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
 * @file exchangedb/pg_inject_auditor_triggers.c
 * @brief Implementation of the inject_auditor_triggers function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_gc.h"
#include "pg_helper.h"
#include "pg_inject_auditor_triggers.h"


/**
 * Function called to inject auditor triggers into the
 * database, triggering the real-time auditor upon
 * relevant INSERTs.
 *
 * @param cls closure
 * @return #GNUNET_OK on success,
 *         #GNUNET_SYSERR on DB errors
 */
enum GNUNET_GenericReturnValue
TEH_PG_inject_auditor_triggers (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_Context *conn;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_try_execute ("SET search_path TO exchange;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                     "exchangedb-postgres",
                                     "auditor-triggers-",
                                     es,
                                     NULL);
  if (NULL == conn)
    return GNUNET_SYSERR;
  GNUNET_PQ_disconnect (conn);
  return GNUNET_OK;
}
