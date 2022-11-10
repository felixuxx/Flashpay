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
 * @file exchangedb/pg_insert_history_request.c
 * @brief Implementation of the insert_history_request function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_history_request.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_history_request (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig,
  struct GNUNET_TIME_Timestamp request_timestamp,
  const struct TALER_Amount *history_fee,
  bool *balance_ok,
  bool *idempotent)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (reserve_sig),
    GNUNET_PQ_query_param_timestamp (&request_timestamp),
    TALER_PQ_query_param_amount (history_fee),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("balance_ok",
                                balance_ok),
    GNUNET_PQ_result_spec_bool ("idempotent",
                                idempotent),
    GNUNET_PQ_result_spec_end
  };
    /* Used in #postgres_insert_history_request() */
  PREPARE (pg,
           "call_history_request",
           "SELECT"
           "  out_balance_ok AS balance_ok"
           " ,out_idempotent AS idempotent"
           " FROM exchange_do_history_request"
           "  ($1, $2, $3, $4, $5)");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_history_request",
                                                   params,
                                                   rs);
}
