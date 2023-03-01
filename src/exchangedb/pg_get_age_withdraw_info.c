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
 * @file exchangedb/pg_get_age_withdraw_info.c
 * @brief Implementation of the get_age_withdraw_info function for Postgres
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_age_withdraw_info.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_get_age_withdraw_info (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_AgeWithdrawCommitmentHashP *ach,
  struct TALER_EXCHANGEDB_AgeWithdrawCommitment *awc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (ach),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("h_commitment",
                                          &awc->h_commitment),
    GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                          &awc->reserve_sig),
    GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                          &awc->reserve_pub),
    GNUNET_PQ_result_spec_uint32 ("max_age_group",
                                  &awc->max_age_group),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 &awc->amount_with_fee),
    GNUNET_PQ_result_spec_uint32 ("noreveal_index",
                                  &awc->noreveal_index),
    GNUNET_PQ_result_spec_timestamp ("timtestamp",
                                     &awc->timestamp),
    GNUNET_PQ_result_spec_end
  };

  /* Used in #postgres_get_age_withdraw_info() to
     locate the response for a /reserve/$RESERVE_PUB/age-withdraw request using
     the hash of the blinded message.  Used to make sure
     /reserve/$RESERVE_PUB/age-withdraw requests are idempotent. */
  PREPARE (pg,
           "get_age_withdraw_info",
           "SELECT"
           " h_commitment"
           ",reserve_sig"
           ",reserve_pub"
           ",max_age_group"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",noreveal_index"
           ",timestamp"
           " FROM withdraw_age_commitments"
           " WHERE h_commitment=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_age_withdraw_info",
                                                   params,
                                                   rs);
}
