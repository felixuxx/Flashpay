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
 * @file exchangedb/pg_get_old_coin_by_h_blind.c
 * @brief Implementation of the get_old_coin_by_h_blind function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_old_coin_by_h_blind.h"
#include "pg_helper.h"



enum GNUNET_DB_QueryStatus
TEH_PG_get_old_coin_by_h_blind (
  void *cls,
  const struct TALER_BlindedCoinHashP *h_blind_ev,
  struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  uint64_t *rrc_serial)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_blind_ev),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                          old_coin_pub),
    GNUNET_PQ_result_spec_uint64 ("rrc_serial",
                                  rrc_serial),
    GNUNET_PQ_result_spec_end
  };

      /* Used in #postgres_get_old_coin_by_h_blind() */
  PREPARE (pg,
           "old_coin_by_h_blind",
           "SELECT"
           " okc.coin_pub AS old_coin_pub"
           ",rrc_serial"
           " FROM refresh_revealed_coins rrc"
           " JOIN refresh_commitments rcom USING (melt_serial_id)"
           " JOIN known_coins okc ON (rcom.old_coin_pub = okc.coin_pub)"
           " WHERE h_coin_ev=$1"
           " LIMIT 1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "old_coin_by_h_blind",
                                                   params,
                                                   rs);
}
