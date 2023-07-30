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
 * @file exchangedb/pg_do_melt.c
 * @brief Implementation of the do_melt function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_do_melt.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_do_melt (
  void *cls,
  const struct TALER_RefreshMasterSecretP *rms,
  struct TALER_EXCHANGEDB_Refresh *refresh,
  uint64_t known_coin_id,
  bool *zombie_required,
  bool *balance_ok)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    NULL == rms
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_auto_from_type (rms),
    TALER_PQ_query_param_amount (pg->conn,
                                 &refresh->amount_with_fee),
    GNUNET_PQ_query_param_auto_from_type (&refresh->rc),
    GNUNET_PQ_query_param_auto_from_type (&refresh->coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&refresh->coin_sig),
    GNUNET_PQ_query_param_uint64 (&known_coin_id),
    GNUNET_PQ_query_param_uint32 (&refresh->noreveal_index),
    GNUNET_PQ_query_param_bool (*zombie_required),
    GNUNET_PQ_query_param_end
  };
  bool is_null;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("balance_ok",
                                balance_ok),
    GNUNET_PQ_result_spec_bool ("zombie_required",
                                zombie_required),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_uint32 ("noreveal_index",
                                    &refresh->noreveal_index),
      &is_null),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "call_melt",
           "SELECT "
           " out_balance_ok AS balance_ok"
           ",out_zombie_bad AS zombie_required"
           ",out_noreveal_index AS noreveal_index"
           " FROM exchange_do_melt"
           " ($1,$2,$3,$4,$5,$6,$7,$8);");
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "call_melt",
                                                 params,
                                                 rs);
  if (is_null)
    refresh->noreveal_index = UINT32_MAX; /* set to very invalid value */
  return qs;
}
