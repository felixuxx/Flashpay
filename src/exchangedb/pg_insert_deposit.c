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
 * @file exchangedb/pg_insert_deposit.c
 * @brief Implementation of the insert_deposit function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_deposit.h"
#include "pg_helper.h"
#include "pg_setup_wire_target.h"
#include "pg_compute_shard.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_deposit (void *cls,
                       struct GNUNET_TIME_Timestamp exchange_timestamp,
                       const struct TALER_EXCHANGEDB_Deposit *deposit)
{
  struct PostgresClosure *pg = cls;
  struct TALER_PaytoHashP h_payto;
  enum GNUNET_DB_QueryStatus qs;

  qs = TEH_PG_setup_wire_target (pg,
                                 deposit->receiver_wire_account,
                                 &h_payto);
  if (qs < 0)
    return qs;
  if (GNUNET_TIME_timestamp_cmp (deposit->wire_deadline,
                                 <,
                                 deposit->refund_deadline))
  {
    GNUNET_break (0);
  }
  {
    uint64_t shard = TEH_PG_compute_shard (&deposit->merchant_pub);
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&deposit->coin.coin_pub),
      TALER_PQ_query_param_amount (&deposit->amount_with_fee),
      GNUNET_PQ_query_param_timestamp (&deposit->timestamp),
      GNUNET_PQ_query_param_timestamp (&deposit->refund_deadline),
      GNUNET_PQ_query_param_timestamp (&deposit->wire_deadline),
      GNUNET_PQ_query_param_auto_from_type (&deposit->merchant_pub),
      GNUNET_PQ_query_param_auto_from_type (&deposit->h_contract_terms),
      GNUNET_PQ_query_param_auto_from_type (&deposit->wire_salt),
      GNUNET_PQ_query_param_auto_from_type (&h_payto),
      GNUNET_PQ_query_param_auto_from_type (&deposit->csig),
      GNUNET_PQ_query_param_timestamp (&exchange_timestamp),
      GNUNET_PQ_query_param_uint64 (&shard),
      GNUNET_PQ_query_param_end
    };

    GNUNET_assert (shard <= INT32_MAX);
    GNUNET_log (
      GNUNET_ERROR_TYPE_INFO,
      "Inserting deposit to be executed at %s (%llu/%llu)\n",
      GNUNET_TIME_timestamp2s (deposit->wire_deadline),
      (unsigned long long) deposit->wire_deadline.abs_time.abs_value_us,
      (unsigned long long) deposit->refund_deadline.abs_time.abs_value_us);
    /* Store information about a /deposit the exchange is to execute.
       Used in #postgres_insert_deposit().  Only used in test cases. */
    PREPARE (pg,
             "insert_deposit",
             "INSERT INTO deposits "
             "(known_coin_id"
             ",coin_pub"
             ",amount_with_fee_val"
             ",amount_with_fee_frac"
             ",wallet_timestamp"
             ",refund_deadline"
             ",wire_deadline"
             ",merchant_pub"
             ",h_contract_terms"
             ",wire_salt"
             ",wire_target_h_payto"
             ",coin_sig"
             ",exchange_timestamp"
             ",shard"
             ") SELECT known_coin_id, $1, $2, $3, $4, $5, $6, "
             " $7, $8, $9, $10, $11, $12, $13"
             "    FROM known_coins"
             "   WHERE coin_pub=$1"
             " ON CONFLICT DO NOTHING;");


    return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                               "insert_deposit",
                                               params);
  }
}
