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
 * @file exchangedb/pg_do_withdraw.c
 * @brief Implementation of the do_withdraw function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_do_withdraw.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_do_withdraw (
  void *cls,
  const struct TALER_CsNonce *nonce,
  const struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable,
  struct GNUNET_TIME_Timestamp now,
  bool *found,
  bool *balance_ok,
  bool *nonce_ok,
  uint64_t *ruuid)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Timestamp gc;
  struct GNUNET_PQ_QueryParam params[] = {
    NULL == nonce
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_auto_from_type (nonce),
    TALER_PQ_query_param_amount (&collectable->amount_with_fee),
    GNUNET_PQ_query_param_auto_from_type (&collectable->denom_pub_hash),
    GNUNET_PQ_query_param_auto_from_type (&collectable->reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (&collectable->reserve_sig),
    GNUNET_PQ_query_param_auto_from_type (&collectable->h_coin_envelope),
    TALER_PQ_query_param_blinded_denom_sig (&collectable->sig),
    GNUNET_PQ_query_param_timestamp (&now),
    GNUNET_PQ_query_param_timestamp (&gc),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("reserve_found",
                                found),
    GNUNET_PQ_result_spec_bool ("balance_ok",
                                balance_ok),
    GNUNET_PQ_result_spec_bool ("nonce_ok",
                                nonce_ok),
    GNUNET_PQ_result_spec_uint64 ("ruuid",
                                  ruuid),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "call_withdraw",
           "SELECT "
           " reserve_found"
           ",balance_ok"
           ",nonce_ok"
           ",ruuid"
           " FROM exchange_do_withdraw"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10);");
  gc = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (now.abs_time,
                              pg->legal_reserve_expiration_time));
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_withdraw",
                                                   params,
                                                   rs);
}


