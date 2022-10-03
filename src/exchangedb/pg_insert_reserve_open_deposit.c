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
 * @file pg_insert_reserve_open_deposit.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_reserve_open_deposit.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_reserve_open_deposit (
  void *cls,
  const struct TALER_CoinPublicInfo *cpi,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  uint64_t known_coin_id,
  const struct TALER_Amount *coin_total,
  const struct TALER_ReserveSignatureP *reserve_sig,
  bool *insufficient_funds)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&cpi->coin_pub),
    GNUNET_PQ_query_param_uint64 (&known_coin_id),
    GNUNET_PQ_query_param_auto_from_type (coin_sig),
    GNUNET_PQ_query_param_auto_from_type (reserve_sig),
    TALER_PQ_query_param_amount (coin_total),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("insufficient_funds",
                                insufficient_funds),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "insert_reserve_open_deposit",
           "SELECT "
           " insufficient_funds"
           " FROM exchange_do_reserve_open_deposit"
           " ($1,$2,$3,$4,$5,$6);");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "insert_reserve_open_deposit",
                                                   params,
                                                   rs);
}
