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
 * @file exchangedb/pg_do_refund.c
 * @brief Implementation of the do_refund function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_do_refund.h"
#include "pg_helper.h"
#include "pg_compute_shard.h"


enum GNUNET_DB_QueryStatus
TEH_PG_do_refund (
  void *cls,
  const struct TALER_EXCHANGEDB_Refund *refund,
  const struct TALER_Amount *deposit_fee,
  uint64_t known_coin_id,
  bool *not_found,
  bool *refund_ok,
  bool *gone,
  bool *conflict)
{
  struct PostgresClosure *pg = cls;
  uint64_t deposit_shard = TEH_PG_compute_shard (&refund->details.merchant_pub);
  struct TALER_Amount amount_without_fee;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &refund->details.refund_amount),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &amount_without_fee),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       deposit_fee),
    GNUNET_PQ_query_param_auto_from_type (&refund->details.h_contract_terms),
    GNUNET_PQ_query_param_uint64 (&refund->details.rtransaction_id),
    GNUNET_PQ_query_param_uint64 (&deposit_shard),
    GNUNET_PQ_query_param_uint64 (&known_coin_id),
    GNUNET_PQ_query_param_auto_from_type (&refund->coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&refund->details.merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (&refund->details.merchant_sig),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("not_found",
                                not_found),
    GNUNET_PQ_result_spec_bool ("refund_ok",
                                refund_ok),
    GNUNET_PQ_result_spec_bool ("gone",
                                gone),
    GNUNET_PQ_result_spec_bool ("conflict",
                                conflict),
    GNUNET_PQ_result_spec_end
  };

  if (0 >
      TALER_amount_subtract (&amount_without_fee,
                             &refund->details.refund_amount,
                             &refund->details.refund_fee))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  PREPARE (pg,
           "call_refund",
           "SELECT "
           " out_not_found AS not_found"
           ",out_refund_ok AS refund_ok"
           ",out_gone AS gone"
           ",out_conflict AS conflict"
           " FROM exchange_do_refund"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10);");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_refund",
                                                   params,
                                                   rs);
}
