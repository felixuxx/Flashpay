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
 * @file exchangedb/pg_insert_drain_profit.c
 * @brief Implementation of the insert_drain_profit function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_drain_profit.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_insert_drain_profit (
  void *cls,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const char *account_section,
  const char *payto_uri,
  struct GNUNET_TIME_Timestamp request_timestamp,
  const struct TALER_Amount *amount,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_string (account_section),
    GNUNET_PQ_query_param_string (payto_uri),
    GNUNET_PQ_query_param_timestamp (&request_timestamp),
    TALER_PQ_query_param_amount (amount),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_end
  };
 /* Used in #postgres_insert_drain_profit() */
  PREPARE (pg,
           "drain_profit_insert",
           "INSERT INTO profit_drains "
           "(wtid"
           ",account_section"
           ",payto_uri"
           ",trigger_date"
           ",amount_val"
           ",amount_frac"
           ",master_sig"
           ") VALUES ($1, $2, $3, $4, $5, $6, $7);");

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "drain_profit_insert",
                                             params);
}
