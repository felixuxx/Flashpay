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
 * @file exchangedb/pg_get_age_withdraw.c
 * @brief Implementation of the get_age_withdraw function for Postgres
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_age_withdraw.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_get_age_withdraw (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_AgeWithdrawCommitmentHashP *ach,
  struct TALER_EXCHANGEDB_AgeWithdraw *aw)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (ach),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("h_commitment",
                                          &aw->h_commitment),
    GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                          &aw->reserve_sig),
    GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                          &aw->reserve_pub),
    GNUNET_PQ_result_spec_uint16 ("max_age",
                                  &aw->max_age),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 &aw->amount_with_fee),
    GNUNET_PQ_result_spec_uint16 ("noreveal_index",
                                  &aw->noreveal_index),
    TALER_PQ_result_spec_array_blinded_coin_hash (
      pg->conn,
      "h_blind_evs",
      &aw->num_coins,
      &aw->h_coin_evs),
    TALER_PQ_result_spec_array_blinded_denom_sig (
      pg->conn,
      "denom_sigs",
      NULL, /* we assume that this is the same size as h_coin_evs */
      &aw->denom_sigs),
    TALER_PQ_result_spec_array_denom_hash (
      pg->conn,
      "denom_pub_hashes",
      NULL, /* we assume that this is the same size as h_coin_evs */
      &aw->denom_pub_hashes),
    GNUNET_PQ_result_spec_end
  };

  GNUNET_assert (NULL != aw);

  /* Used in #postgres_get_age_withdraw() to
     locate the response for a /reserve/$RESERVE_PUB/age-withdraw request
     using the hash of the blinded message.  Also needed to ensure
     idempotency of /reserve/$RESERVE_PUB/age-withdraw requests. */
  PREPARE (pg,
           "get_age_withdraw",
           "SELECT"
           " h_commitment"
           ",reserve_sig"
           ",reserve_pub"
           ",max_age"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",noreveal_index"
           ",h_blind_evs"
           ",denom_sigs"
           ",ARRAY("
           "  SELECT denominations.denom_pub_hash FROM ("
           "    SELECT UNNEST(denom_serials) AS id,"
           "           generate_subscripts(denom_serials, 1) AS nr" /* for order */
           "  ) AS denoms"
           "  LEFT JOIN denominations ON denominations.denominations_serial=denoms.id"
           ") AS denom_pub_hashes"
           " FROM age_withdraw"
           " WHERE reserve_pub=$1 and h_commitment=$2;");

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_age_withdraw",
                                                   params,
                                                   rs);
}
