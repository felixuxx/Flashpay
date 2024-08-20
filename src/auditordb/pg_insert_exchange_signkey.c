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
 * @file pg_insert_exchange_signkey.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_exchange_signkey.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_insert_exchange_signkey (
  void *cls,
  const struct TALER_AUDITORDB_ExchangeSigningKey *sk)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&sk->ep_start),
    GNUNET_PQ_query_param_timestamp (&sk->ep_expire),
    GNUNET_PQ_query_param_timestamp (&sk->ep_end),
    GNUNET_PQ_query_param_auto_from_type (&sk->exchange_pub),
    GNUNET_PQ_query_param_auto_from_type (&sk->master_sig),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_insert_exchange_signkey",
           "INSERT INTO auditor_exchange_signkeys "
           "(ep_start"
           ",ep_expire"
           ",ep_end"
           ",exchange_pub"
           ",master_sig"
           ") VALUES ($1,$2,$3,$4,$5);"
           );
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_insert_exchange_signkey",
                                             params);
}
