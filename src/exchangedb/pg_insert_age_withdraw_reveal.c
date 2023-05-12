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
 * @file exchangedb/pg_insert_age_withdraw_reveal.c
 * @brief Implementation of the insert_age_withdraw_reveal function for Postgres
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_refresh_reveal.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_age_withdraw_reveal (
  void *cls,
  /*TODO:oec*/
  )
{
  struct PostgresClosure *pg = cls;

  if (TALER_CNC_KAPPA != num_tprivs + 1)
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  /* TODO */
#if 0
  PREPARE (pg,
           "insert_age_withdraw_revealed_coin",
           "INSERT INTO age_withdraw_reveals "
           "(h_commitment "
           ",freshcoin_index "
           ",denominations_serial "
           ",h_coin_ev "
           ",ev_sig"
           ") SELECT $1, $2, $3, "
           "         denominations_serial, $5, $6, $7, $8"
           "    FROM denominations"
           "   WHERE denom_pub_hash=$4"

           " ON CONFLICT DO NOTHING;");
  for (uint32_t i = 0; i<num_rrcs; i++)
  {
    const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &rrcs[i];
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_uint64 (&melt_serial_id),
      GNUNET_PQ_query_param_uint32 (&i),
      GNUNET_PQ_query_param_auto_from_type (&rrc->orig_coin_link_sig),
      GNUNET_PQ_query_param_auto_from_type (&rrc->h_denom_pub),
      TALER_PQ_query_param_blinded_planchet (&rrc->blinded_planchet),
      TALER_PQ_query_param_exchange_withdraw_values (&rrc->exchange_vals),
      GNUNET_PQ_query_param_auto_from_type (&rrc->coin_envelope_hash),
      TALER_PQ_query_param_blinded_denom_sig (&rrc->coin_sig),
      GNUNET_PQ_query_param_end
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_refresh_revealed_coin",
                                             params);
    if (0 > qs)
      return qs;
  }

  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_uint64 (&melt_serial_id),
      GNUNET_PQ_query_param_auto_from_type (tp),
      GNUNET_PQ_query_param_fixed_size (
        tprivs,
        num_tprivs * sizeof (struct TALER_TransferPrivateKeyP)),
      GNUNET_PQ_query_param_end
    };

    /* Used in #postgres_insert_refresh_reveal() to store the transfer
   keys we learned */
    PREPARE (pg,
             "insert_refresh_transfer_keys",
             "INSERT INTO refresh_transfer_keys "
             "(melt_serial_id"
             ",transfer_pub"
             ",transfer_privs"
             ") VALUES ($1, $2, $3)"
             " ON CONFLICT DO NOTHING;");
    return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                               "insert_refresh_transfer_keys",
                                               params);
  }
#endif
}
