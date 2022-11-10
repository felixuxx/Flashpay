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
 * @file exchangedb/pg_get_purse_deposit.c
 * @brief Implementation of the get_purse_deposit function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_purse_deposit.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_get_purse_deposit (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct TALER_Amount *amount,
  struct TALER_DenominationHashP *h_denom_pub,
  struct TALER_AgeCommitmentHash *phac,
  struct TALER_CoinSpendSignatureP *coin_sig,
  char **partner_url)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  bool is_null;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          h_denom_pub),
    GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                          phac),
    GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                          coin_sig),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 amount),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_string ("partner_base_url",
                                    partner_url),
      &is_null),
    GNUNET_PQ_result_spec_end
  };


  *partner_url = NULL;
 /* Used in #postgres_get_purse_deposit */
  PREPARE (pg,
           "select_purse_deposit_by_coin_pub",
           "SELECT "
           " coin_sig"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",denom_pub_hash"
           ",age_commitment_hash"
           ",partner_base_url"
           " FROM purse_deposits"
           " LEFT JOIN partners USING (partner_serial_id)"
           " JOIN known_coins kc USING (coin_pub)"
           " JOIN denominations USING (denominations_serial)"
           " WHERE coin_pub=$2"
           "   AND purse_pub=$1;");

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_purse_deposit_by_coin_pub",
                                                   params,
                                                   rs);
}
