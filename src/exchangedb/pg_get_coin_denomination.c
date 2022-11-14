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
 * @file exchangedb/pg_get_coin_denomination.c
 * @brief Implementation of the get_coin_denomination function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_coin_denomination.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_get_coin_denomination (
  void *cls,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  uint64_t *known_coin_id,
  struct TALER_DenominationHashP *denom_hash)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          denom_hash),
    GNUNET_PQ_result_spec_uint64 ("known_coin_id",
                                  known_coin_id),
    GNUNET_PQ_result_spec_end
  };

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting coin denomination of coin %s\n",
              TALER_B2S (coin_pub));

    /* Used in #postgres_get_coin_denomination() to fetch
       the denomination public key hash for
       a coin known to the exchange. */
  PREPARE (pg,
           "get_coin_denomination",
           "SELECT"
           " denominations.denom_pub_hash"
           ",known_coin_id"
           " FROM known_coins"
           " JOIN denominations USING (denominations_serial)"
           " WHERE coin_pub=$1"
           " FOR SHARE;");

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_coin_denomination",
                                                   params,
                                                   rs);
}


