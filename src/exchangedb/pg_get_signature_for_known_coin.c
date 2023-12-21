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
 * @file exchangedb/pg_get_signature_for_known_coin.c
 * @brief Implementation of the get_signature_for_known_coin function for Postgres
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_signature_for_known_coin.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_get_signature_for_known_coin (
  void *cls,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct TALER_DenominationPublicKey *denom_pub,
  struct TALER_DenominationSignature *denom_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_denom_pub ("denom_pub",
                                    denom_pub),
    TALER_PQ_result_spec_denom_sig ("denom_sig",
                                    denom_sig),
    GNUNET_PQ_result_spec_end
  };

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting denomination and signature for (potentially) known coin %s\n",
              TALER_B2S (coin_pub));
  PREPARE (pg,
           "get_signature_for_known_coin",
           "SELECT"
           " denominations.denom_pub"
           ",denom_sig"
           " FROM known_coins"
           " JOIN denominations USING (denominations_serial)"
           " WHERE coin_pub=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_signature_for_known_coin",
                                                   params,
                                                   rs);
}
