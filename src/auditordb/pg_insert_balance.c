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
 * @file pg_insert_balance.c
 * @brief Implementation of the insert_balance function
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_balance.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_insert_balance (void *cls,
                       const char *balance_key,
                       const struct TALER_Amount *balance_value,
                       ...)
{
  struct PostgresClosure *pg = cls;
  unsigned int cnt = 1;
  va_list ap;

  va_start (ap,
            balance_value);
  while (NULL != va_arg (ap,
                         const char *))
  {
    cnt++;
    (void) va_arg (ap,
                   const struct TALER_Amount *);
  }
  va_end (ap);
  {
    const char *keys[cnt];
    struct TALER_Amount amounts[cnt];
    unsigned int off = 1;
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_array_ptrs_string (cnt,
                                               keys,
                                               pg->conn),
      TALER_PQ_query_param_array_amount (cnt,
                                         amounts,
                                         pg->conn),
      GNUNET_PQ_query_param_end
    };
    enum GNUNET_DB_QueryStatus qs;

    keys[0] = balance_key;
    amounts[0] = *balance_value;

    va_start (ap,
              balance_value);
    while (off < cnt)
    {
      keys[off] = va_arg (ap,
                          const char *);
      amounts[off] = *va_arg (ap,
                              const struct TALER_Amount *);
      off++;
    }
    GNUNET_assert (NULL == va_arg (ap,
                                   const char *));
    va_end (ap);

    PREPARE (pg,
             "auditor_balance_insert",
             "INSERT INTO auditor_balances "
             "(balance_key"
             ",balance_value.val"
             ",balance_value.frac"
             ") SELECT *"
             " FROM UNNEST (CAST($1 AS TEXT[]),"
             "              CAST($2 AS taler_amount[]))"
             " ON CONFLICT DO NOTHING;");
    qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_balance_insert",
                                             params);
    GNUNET_PQ_cleanup_query_params_closures (params);
    return qs;
  }
}
