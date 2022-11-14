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
 * @file exchangedb/pg_get_known_coin.c
 * @brief Implementation of the get_known_coin function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_known_coin.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_get_known_coin (void *cls,
                         const struct TALER_CoinSpendPublicKeyP *coin_pub,
                         struct TALER_CoinPublicInfo *coin_info)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          &coin_info->denom_pub_hash),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                            &coin_info->h_age_commitment),
      &coin_info->no_age_commitment),
    TALER_PQ_result_spec_denom_sig ("denom_sig",
                                    &coin_info->denom_sig),
    GNUNET_PQ_result_spec_end
  };

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting known coin data for coin %s\n",
              TALER_B2S (coin_pub));
  coin_info->coin_pub = *coin_pub;
    /* Used in #postgres_get_known_coin() to fetch
       the denomination public key and signature for
       a coin known to the exchange. */
  PREPARE (pg,
           "get_known_coin",
           "SELECT"
           " denominations.denom_pub_hash"
           ",age_commitment_hash"
           ",denom_sig"
           " FROM known_coins"
           " JOIN denominations USING (denominations_serial)"
           " WHERE coin_pub=$1;");

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_known_coin",
                                                   params,
                                                   rs);
}
