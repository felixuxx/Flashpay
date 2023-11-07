/*
   This file is part of TALER
   Copyright (C) 2023 Taler Systems SA

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
 * @file exchangedb/pg_do_batch_withdraw.c
 * @brief Implementation of the do_batch_withdraw function for Postgres
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_exchangedb_plugin.h"
#include "taler_pq_lib.h"
#include "taler_pq_lib.h"
#include "pg_do_batch_withdraw.h"
#include "pg_helper.h"
#include <gnunet/gnunet_time_lib.h>


enum GNUNET_DB_QueryStatus
TEH_PG_do_age_withdraw (
  void *cls,
  const struct TALER_EXCHANGEDB_AgeWithdraw *commitment,
  struct GNUNET_TIME_Timestamp now,
  bool *found,
  bool *balance_ok,
  struct TALER_Amount *reserve_balance,
  bool *age_ok,
  uint16_t *required_age,
  uint32_t *reserve_birthday,
  bool *conflict)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Timestamp gc;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (pg->conn,
                                 &commitment->amount_with_fee),
    GNUNET_PQ_query_param_auto_from_type (&commitment->reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (&commitment->reserve_sig),
    GNUNET_PQ_query_param_timestamp (&now),
    GNUNET_PQ_query_param_timestamp (&gc),
    GNUNET_PQ_query_param_auto_from_type (&commitment->h_commitment),
    GNUNET_PQ_query_param_uint16 (&commitment->max_age),
    GNUNET_PQ_query_param_uint16 (&commitment->noreveal_index),
    TALER_PQ_query_param_array_blinded_coin_hash (commitment->num_coins,
                                                  commitment->h_coin_evs,
                                                  pg->conn),
    GNUNET_PQ_query_param_array_uint64 (commitment->num_coins,
                                        commitment->denom_serials,
                                        pg->conn),
    TALER_PQ_query_param_array_blinded_denom_sig (commitment->num_coins,
                                                  commitment->denom_sigs,
                                                  pg->conn),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("reserve_found",
                                found),
    GNUNET_PQ_result_spec_bool ("balance_ok",
                                balance_ok),
    TALER_PQ_RESULT_SPEC_AMOUNT ("reserve_balance",
                                 reserve_balance),
    GNUNET_PQ_result_spec_bool ("age_ok",
                                age_ok),
    GNUNET_PQ_result_spec_uint16 ("required_age",
                                  required_age),
    GNUNET_PQ_result_spec_uint32 ("reserve_birthday",
                                  reserve_birthday),
    GNUNET_PQ_result_spec_bool ("conflict",
                                conflict),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  gc = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (now.abs_time,
                              pg->legal_reserve_expiration_time));
  PREPARE (pg,
           "call_age_withdraw",
           "SELECT "
           " reserve_found"
           ",balance_ok"
           ",reserve_balance"
           ",age_ok"
           ",required_age"
           ",reserve_birthday"
           ",conflict"
           " FROM exchange_do_age_withdraw"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11);");
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "call_age_withdraw",
                                                 params,
                                                 rs);
  GNUNET_PQ_cleanup_query_params_closures (params);
  return qs;
}
