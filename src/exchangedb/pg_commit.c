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
 * @file exchangedb/pg_commit.c
 * @brief Implementation of the commit function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_commit.h"
#include "pg_helper.h"


/**
 * Commit the current transaction of a database connection.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return final transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_commit (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_break (NULL != pg->transaction_name);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Committing transaction `%s'\n",
              pg->transaction_name);
   /* used in #postgres_commit */
  PREPARE (pg,
           "do_commit",
           "COMMIT");

  qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                           "do_commit",
                                           params);
  pg->transaction_name = NULL;
  return qs;
}
