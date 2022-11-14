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
 * @file exchangedb/pg_do_recoup_refresh.c
 * @brief Implementation of the do_recoup_refresh function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_do_recoup_refresh.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_do_recoup_refresh (
  void *cls,
  const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  uint64_t rrc_serial,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  uint64_t known_coin_id,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  struct GNUNET_TIME_Timestamp *recoup_timestamp,
  bool *recoup_ok,
  bool *internal_failure)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (old_coin_pub),
    GNUNET_PQ_query_param_uint64 (&rrc_serial),
    GNUNET_PQ_query_param_auto_from_type (coin_bks),
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_uint64 (&known_coin_id),
    GNUNET_PQ_query_param_auto_from_type (coin_sig),
    GNUNET_PQ_query_param_timestamp (recoup_timestamp),
    GNUNET_PQ_query_param_end
  };
  bool is_null;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
                                       recoup_timestamp),
      &is_null),
    GNUNET_PQ_result_spec_bool ("recoup_ok",
                                recoup_ok),
    GNUNET_PQ_result_spec_bool ("internal_failure",
                                internal_failure),
    GNUNET_PQ_result_spec_end
  };


  PREPARE (pg,
           "call_recoup_refresh",
           "SELECT "
           " out_recoup_timestamp AS recoup_timestamp"
           ",out_recoup_ok AS recoup_ok"
           ",out_internal_failure AS internal_failure"
           " FROM exchange_do_recoup_to_coin"
           " ($1,$2,$3,$4,$5,$6,$7);");

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_recoup_refresh",
                                                   params,
                                                   rs);
}
