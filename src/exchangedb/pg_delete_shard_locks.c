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
 * @file exchangedb/pg_delete_shard_locks.c
 * @brief Implementation of the delete_shard_locks function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_delete_shard_locks.h"
#include "pg_helper.h"


enum GNUNET_GenericReturnValue
TEH_PG_delete_shard_locks (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("DELETE FROM work_shards;"),
    GNUNET_PQ_make_execute ("DELETE FROM revolving_work_shards;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  return GNUNET_PQ_exec_statements (pg->conn,
                                    es);
}
