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
  const struct TALER_Amount *closing_fee,
  struct TALER_Amount *final_balance)
{
  struct PostgresClosure *pg = cls;
  // FIXME: deal with payto_uri and closing_fee!!
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_timestamp (&request_timestamp),
    GNUNET_PQ_query_param_auto_from_type (reserve_sig),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("out_final_balance",
                                 final_balance),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "call_account_close",
           "SELECT "
           " out_final_balance_val"
           ",out_final_balance_frac"
           " FROM exchange_do_close_request"
           "  ($1, $2, $3)");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_account_close",
                                                   params,
                                                   rs);
}
