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
/**
 * @file pg_update_auditor_progress.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_update_auditor_progress.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_update_auditor_progress (
  void *cls,
  const char *progress_key,
  uint64_t progress_offset,
  ...)
{
  struct PostgresClosure *pg = cls;
  unsigned int cnt = 1;
  va_list ap;

  va_start (ap,
            progress_offset);
  while (NULL != va_arg (ap,
                         const char *))
  {
    cnt++;
    (void) va_arg (ap,
                   uint64_t);
  }
  va_end (ap);
  {
    const char *keys[cnt];
    uint64_t offsets[cnt];
    unsigned int off = 1;
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_array_ptrs_string (cnt,
                                               keys,
                                               pg->conn),
      GNUNET_PQ_query_param_array_uint64 (cnt,
                                          offsets,
                                          pg->conn),
      GNUNET_PQ_query_param_end
    };
    enum GNUNET_DB_QueryStatus qs;

    keys[0] = progress_key;
    offsets[0] = progress_offset;

    va_start (ap,
              progress_offset);
    while (off < cnt)
    {
      keys[off] = va_arg (ap,
                          const char *);
      offsets[off] = va_arg (ap,
                             uint64_t);
      off++;
    }
    GNUNET_assert (NULL == va_arg (ap,
                                   const char *));
    va_end (ap);

    PREPARE (pg,
             "auditor_progress_update",
             "UPDATE auditor_progress"
             "  SET progress_offset=data.off"
             "  FROM ("
             "    SELECT *"
             "      FROM UNNEST (CAST($1 AS TEXT[]),"
             "                   CAST($2 AS INT8[]))"
             "      AS t(key,off)"
             "  ) AS data"
             " WHERE auditor_progress.progress_key=data.key;");
    qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_progress_update",
                                             params);
    GNUNET_PQ_cleanup_query_params_closures (params);
    return qs;
  }
}
