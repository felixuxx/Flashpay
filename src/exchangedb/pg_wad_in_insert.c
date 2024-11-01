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
 * @file exchangedb/pg_wad_in_insert.c
 * @brief Implementation of the wad_in_insert function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_wad_in_insert.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_wad_in_insert (
  void *cls,
  const struct TALER_WadIdentifierP *wad_id,
  const char *origin_exchange_url,
  const struct TALER_Amount *amount,
  struct GNUNET_TIME_Timestamp execution_date,
  const struct TALER_FullPayto debit_account_uri,
  const char *section_name,
  uint64_t serial_id)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (wad_id),
    GNUNET_PQ_query_param_string (origin_exchange_url),
    TALER_PQ_query_param_amount (pg->conn,
                                 amount),
    GNUNET_PQ_query_param_timestamp (&execution_date),
    GNUNET_PQ_query_param_end
  };

  // FIXME: should we keep the account data + serial_id?
  PREPARE (pg,
           "wad_in_insert",
           "INSERT INTO wads_in "
           "(wad_id"
           ",origin_exchange_url"
           ",amount"
           ",arrival_time"
           ") VALUES "
           "($1, $2, $3, $4);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "wad_in_insert",
                                             params);
}
