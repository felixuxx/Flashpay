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
 * @file exchangedb/pg_get_melt.c
 * @brief Implementation of the get_melt function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_melt.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_get_melt (void *cls,
                   const struct TALER_RefreshCommitmentP *rc,
                   struct TALER_EXCHANGEDB_Melt *melt,
                   uint64_t *melt_serial_id)
{
  struct PostgresClosure *pg = cls;
  bool h_age_commitment_is_null;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (rc),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          &melt->session.coin.
                                          denom_pub_hash),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refresh",
                                 &melt->melt_fee),
    GNUNET_PQ_result_spec_uint32 ("noreveal_index",
                                  &melt->session.noreveal_index),
    GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                          &melt->session.coin.coin_pub),
    GNUNET_PQ_result_spec_auto_from_type ("old_coin_sig",
                                          &melt->session.coin_sig),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                            &melt->session.coin.h_age_commitment),
      &h_age_commitment_is_null),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 &melt->session.amount_with_fee),
    GNUNET_PQ_result_spec_uint64 ("melt_serial_id",
                                  melt_serial_id),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  memset (&melt->session.coin.denom_sig,
          0,
          sizeof (melt->session.coin.denom_sig));

    /* Used in #postgres_get_melt() to fetch
       high-level information about a melt operation */
  PREPARE (pg,
           "get_melt",
           /* "SELECT"
              " denoms.denom_pub_hash"
              ",denoms.fee_refresh_val"
              ",denoms.fee_refresh_frac"
              ",old_coin_pub"
              ",old_coin_sig"
              ",kc.age_commitment_hash"
              ",amount_with_fee_val"
              ",amount_with_fee_frac"
              ",noreveal_index"
              ",melt_serial_id"
              " FROM refresh_commitments"
              "   JOIN known_coins kc"
              "     ON (old_coin_pub = kc.coin_pub)"
              "   JOIN denominations denoms"
              "     ON (kc.denominations_serial = denoms.denominations_serial)"
              " WHERE rc=$1;", */
           "WITH rc AS MATERIALIZED ( "
           " SELECT"
           "  * FROM refresh_commitments"
           " WHERE rc=$1"
           ")"
           "SELECT"
           " denoms.denom_pub_hash"
           ",denoms.fee_refresh_val"
           ",denoms.fee_refresh_frac"
           ",rc.old_coin_pub"
           ",rc.old_coin_sig"
           ",kc.age_commitment_hash"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",noreveal_index"
           ",melt_serial_id "
           "FROM ("
           " SELECT"
           "  * "
           " FROM known_coins"
           " WHERE coin_pub=(SELECT old_coin_pub from rc)"
           ") kc "
           "JOIN rc"
           "  ON (kc.coin_pub=rc.old_coin_pub) "
           "JOIN denominations denoms"
           "  USING (denominations_serial);");

  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "get_melt",
                                                 params,
                                                 rs);
  if (h_age_commitment_is_null)
    memset (&melt->session.coin.h_age_commitment,
            0,
            sizeof(melt->session.coin.h_age_commitment));

  melt->session.rc = *rc;
  return qs;
}
