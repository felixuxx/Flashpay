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
 * @file exchangedb/pg_get_withdraw_info.c
 * @brief Implementation of the get_withdraw_info function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_withdraw_info.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_get_withdraw_info (
  void *cls,
  const struct TALER_BlindedCoinHashP *bch,
  struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (bch),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          &collectable->denom_pub_hash),
    TALER_PQ_result_spec_blinded_denom_sig ("denom_sig",
                                            &collectable->sig),
    GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                          &collectable->reserve_sig),
    GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                          &collectable->reserve_pub),
    GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                          &collectable->h_coin_envelope),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 &collectable->amount_with_fee),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_withdraw",
                                 &collectable->withdraw_fee),
    GNUNET_PQ_result_spec_end
  };

  /* Used in #postgres_get_withdraw_info() to
      locate the response for a /reserve/withdraw request
      using the hash of the blinded message.  Used to
      make sure /reserve/withdraw requests are idempotent. */
  PREPARE (pg,
           "get_withdraw_info",
           "SELECT"
           " denom.denom_pub_hash"
           ",denom_sig"
           ",reserve_sig"
           ",reserves.reserve_pub"
           ",execution_date"
           ",h_blind_ev"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",denom.fee_withdraw_val"
           ",denom.fee_withdraw_frac"
           " FROM reserves_out"
           "    JOIN reserves"
           "      USING (reserve_uuid)"
           "    JOIN denominations denom"
           "      USING (denominations_serial)"
           " WHERE h_blind_ev=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_withdraw_info",
                                                   params,
                                                   rs);
}
