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
 * @file pg_insert_close_request.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_close_request.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_close_request (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const char *payto_uri,
  const struct TALER_ReserveSignatureP *reserve_sig,
  struct GNUNET_TIME_Timestamp request_timestamp,
  const struct TALER_Amount *balance,
  const struct TALER_Amount *closing_fee)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_timestamp (&request_timestamp),
    GNUNET_PQ_query_param_auto_from_type (reserve_sig),
    TALER_PQ_query_param_amount (balance),
    TALER_PQ_query_param_amount (closing_fee),
    GNUNET_PQ_query_param_string (payto_uri),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_account_close",
           "INSERT INTO close_requests"
           "(reserve_pub"
           ",close_timestamp"
           ",reserve_sig"
           ",close_val"
           ",close_frac"
           ",close_fee_val"
           ",close_fee_frac"
           ",payto_uri"
           ")"
           "VALUES ($1, $2, $3, $4, $5, $6, $7, $8)"
           " ON CONFLICT DO NOTHING;");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_account_close",
                                             params);
}
