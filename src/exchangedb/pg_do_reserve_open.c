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
 * @file pg_do_reserve_open.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_do_reserve_open.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_do_reserve_open (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_Amount *total_paid,
  const struct TALER_Amount *reserve_payment,
  uint32_t min_purse_limit,
  const struct TALER_ReserveSignatureP *reserve_sig,
  struct GNUNET_TIME_Timestamp desired_expiration,
  struct GNUNET_TIME_Timestamp now,
  const struct TALER_Amount *open_fee,
  bool *no_funds,
  struct TALER_Amount *open_cost,
  struct GNUNET_TIME_Timestamp *final_expiration)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    TALER_PQ_query_param_amount_tuple (
      pg->conn,
      total_paid),
    TALER_PQ_query_param_amount_tuple (
      pg->conn,
      reserve_payment),
    GNUNET_PQ_query_param_uint32 (&min_purse_limit),
    GNUNET_PQ_query_param_uint32 (&pg->def_purse_limit),
    GNUNET_PQ_query_param_auto_from_type (reserve_sig),
    GNUNET_PQ_query_param_timestamp (&desired_expiration),
    GNUNET_PQ_query_param_relative_time (&pg->legal_reserve_expiration_time),
    GNUNET_PQ_query_param_timestamp (&now),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       open_fee),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_amount_tuple ("out_open_cost",
                                       pg->currency,
                                       open_cost),
    GNUNET_PQ_result_spec_timestamp ("out_final_expiration",
                                     final_expiration),
    GNUNET_PQ_result_spec_bool ("out_no_funds",
                                no_funds),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "do_reserve_open",
           "SELECT "
           " out_open_cost"
           ",out_final_expiration"
           ",out_no_funds"
           " FROM exchange_do_reserve_open"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10);");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "do_reserve_open",
                                                   params,
                                                   rs);
}
