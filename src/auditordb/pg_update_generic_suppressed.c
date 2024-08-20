/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

   TALER is free software; you can redistribute it and/or modify it under the
   terms of the GNU General Public License as published by the Free Software
   Foundation; either version 3, or (at your option) any later version.

   TALER is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
   A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

   You should have received a copy of the GNU General Public License along with
   TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
 */


#include "platform.h"
#include "taler_pq_lib.h"
#include "pg_helper.h"
#include "pg_update_closure_lags.h"

struct Preparations
{
  /**
   * Database reconnect counter.
   */
  unsigned long long cnt;

  /**
   * Which DB did we do prepare for.
   */
  struct PostgresClosure *pg;

};


enum GNUNET_DB_QueryStatus
TAH_PG_update_generic_suppressed (
  void *cls,
  enum TALER_AUDITORDB_SuppressableTables table,
  uint64_t row_id,
  bool suppressed)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&row_id),
    GNUNET_PQ_query_param_bool (suppressed),
    GNUNET_PQ_query_param_end
  };
  static struct Preparations preps[
    TALER_AUDITORDB_SUPPRESSABLE_TABLES_MAX];

  struct Preparations *prep = &preps[table];
  const char *table_name = TAH_PG_get_table_name (table);
  char statement_name[256];

  GNUNET_snprintf (statement_name,
                   sizeof (statement_name),
                   "update_%s",
                   table_name);
  if ( (pg != prep->pg) ||
       (prep->cnt < pg->prep_gen) )
  {
    char sql[256];
    struct GNUNET_PQ_PreparedStatement ps[] = {
      GNUNET_PQ_make_prepare (statement_name,
                              sql),
      GNUNET_PQ_PREPARED_STATEMENT_END
    };

    GNUNET_snprintf (sql,
                     sizeof (sql),
                     "UPDATE %s SET"
                     " suppressed=$2"
                     " WHERE row_id=$1",
                     table_name);
    if (GNUNET_OK !=
        GNUNET_PQ_prepare_statements (pg->conn,
                                      ps))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    prep->pg = pg;
    prep->cnt = pg->prep_gen;
  }
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             statement_name,
                                             params);
}
