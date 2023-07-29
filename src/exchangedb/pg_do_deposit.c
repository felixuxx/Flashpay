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
 * @file exchangedb/pg_do_deposit.c
 * @brief Implementation of the do_deposit function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_do_deposit.h"
#include "pg_helper.h"
#include "pg_compute_shard.h"


enum GNUNET_DB_QueryStatus
TEH_PG_do_deposit (
  void *cls,
  const struct TALER_EXCHANGEDB_Deposit *deposit,
  uint64_t known_coin_id,
  const struct TALER_PaytoHashP *h_payto,
  uint64_t *policy_details_serial_id,
  struct GNUNET_TIME_Timestamp *exchange_timestamp,
  bool *balance_ok,
  bool *in_conflict)
{
  struct PostgresClosure *pg = cls;
  uint64_t deposit_shard = TEH_PG_compute_shard (&deposit->merchant_pub);
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &deposit->amount_with_fee),
    GNUNET_PQ_query_param_auto_from_type (&deposit->h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (&deposit->wire_salt),
    GNUNET_PQ_query_param_timestamp (&deposit->timestamp),
    GNUNET_PQ_query_param_timestamp (exchange_timestamp),
    GNUNET_PQ_query_param_timestamp (&deposit->refund_deadline),
    GNUNET_PQ_query_param_timestamp (&deposit->wire_deadline),
    GNUNET_PQ_query_param_auto_from_type (&deposit->merchant_pub),
    GNUNET_PQ_query_param_string (deposit->receiver_wire_account),
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_uint64 (&known_coin_id),
    GNUNET_PQ_query_param_auto_from_type (&deposit->coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&deposit->csig),
    GNUNET_PQ_query_param_uint64 (&deposit_shard),
    GNUNET_PQ_query_param_bool (deposit->has_policy),
    (NULL == policy_details_serial_id)
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_uint64 (policy_details_serial_id),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("balance_ok",
                                balance_ok),
    GNUNET_PQ_result_spec_bool ("conflicted",
                                in_conflict),
    GNUNET_PQ_result_spec_timestamp ("exchange_timestamp",
                                     exchange_timestamp),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "call_deposit",
           "SELECT "
           " out_exchange_timestamp AS exchange_timestamp"
           ",out_balance_ok AS balance_ok"
           ",out_conflict AS conflicted"
           " FROM exchange_do_deposit"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16);");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_deposit",
                                                   params,
                                                   rs);
}
