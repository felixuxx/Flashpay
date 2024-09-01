/*
   This file is part of TALER
   Copyright (C) 2022-2023 Taler Systems SA

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
#include "pg_do_check_deposit_idempotent.h"
#include "pg_helper.h"
#include "pg_compute_shard.h"


enum GNUNET_DB_QueryStatus
TEH_PG_do_check_deposit_idempotent (
  void *cls,
  const struct TALER_EXCHANGEDB_BatchDeposit *bd,
  struct GNUNET_TIME_Timestamp *exchange_timestamp,
  bool *is_idempotent)
{
  struct PostgresClosure *pg = cls;
  uint64_t deposit_shard = TEH_PG_compute_shard (&bd->merchant_pub);
  const struct TALER_CoinSpendPublicKeyP *coin_pubs[GNUNET_NZL (bd->num_cdis)];
  const struct TALER_CoinSpendSignatureP *coin_sigs[GNUNET_NZL (bd->num_cdis)];
  struct TALER_Amount amounts_with_fee[GNUNET_NZL (bd->num_cdis)];
  struct GNUNET_PQ_QueryParam params[] = {
    /* data for batch_deposits */
    GNUNET_PQ_query_param_uint64 (&deposit_shard),
    GNUNET_PQ_query_param_auto_from_type (&bd->merchant_pub),
    GNUNET_PQ_query_param_timestamp (&bd->wallet_timestamp),
    GNUNET_PQ_query_param_timestamp (exchange_timestamp),
    GNUNET_PQ_query_param_timestamp (&bd->refund_deadline),
    GNUNET_PQ_query_param_timestamp (&bd->wire_deadline),
    GNUNET_PQ_query_param_auto_from_type (&bd->h_contract_terms),
    (bd->no_wallet_data_hash)
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_auto_from_type (&bd->wallet_data_hash),
    GNUNET_PQ_query_param_auto_from_type (&bd->wire_salt),
    GNUNET_PQ_query_param_auto_from_type (&bd->wire_target_h_payto),
    (0 == bd->policy_details_serial_id)
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_uint64 (&bd->policy_details_serial_id),
    GNUNET_PQ_query_param_bool (bd->policy_blocked),
    /* to create entry in wire_targets */
    GNUNET_PQ_query_param_string (bd->receiver_wire_account),
    /* arrays for coin_deposits */
    GNUNET_PQ_query_param_array_ptrs_auto_from_type (bd->num_cdis,
                                                     coin_pubs,
                                                     pg->conn),
    GNUNET_PQ_query_param_array_ptrs_auto_from_type (bd->num_cdis,
                                                     coin_sigs,
                                                     pg->conn),
    TALER_PQ_query_param_array_amount (bd->num_cdis,
                                       amounts_with_fee,
                                       pg->conn),
    GNUNET_PQ_query_param_end
  };
  bool no_time;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_timestamp ("exchange_timestamp",
                                       exchange_timestamp),
      &no_time),
    GNUNET_PQ_result_spec_bool ("is_idempotent",
                                is_idempotent),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  for (unsigned int i = 0; i < bd->num_cdis; i++)
  {
    const struct TALER_EXCHANGEDB_CoinDepositInformation *cdi
      = &bd->cdis[i];

    amounts_with_fee[i] = cdi->amount_with_fee;
    coin_pubs[i] = &cdi->coin.coin_pub;
    coin_sigs[i] = &cdi->csig;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Do deposit %u = %s\n",
                i,
                TALER_B2S (&cdi->coin.coin_pub));
  }
  PREPARE (pg,
           "call_check_deposit_idempotent",
           "SELECT "
           " out_exchange_timestamp AS exchange_timestamp"
           ",out_is_idempotent AS is_idempotent"
           " FROM exchange_do_check_deposit_idempotent"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16);");
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "call_check_deposit_idempotent",
                                                 params,
                                                 rs);
  GNUNET_PQ_cleanup_query_params_closures (params);
  return qs;
}
