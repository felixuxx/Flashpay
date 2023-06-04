/*
   This file is part of TALER
   Copyright (C) 2022, 2023 Taler Systems SA

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
 * @file exchangedb/pg_insert_wire.c
 * @brief Implementation of the insert_wire function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_wire.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_wire (void *cls,
                    const char *payto_uri,
                    const char *conversion_url,
                    const json_t *debit_restrictions,
                    const json_t *credit_restrictions,
                    struct GNUNET_TIME_Timestamp start_date,
                    const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (payto_uri),
    NULL == conversion_url
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_string (conversion_url),
    TALER_PQ_query_param_json (debit_restrictions),
    TALER_PQ_query_param_json (credit_restrictions),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_timestamp (&start_date),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_wire",
           "INSERT INTO wire_accounts "
           "(payto_uri"
           ",conversion_url"
           ",debit_restrictions"
           ",credit_restrictions"
           ",master_sig"
           ",is_active"
           ",last_change"
           ") VALUES "
           "($1, $2, $3, $4, $5, true, $6);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_wire",
                                             params);
}
