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
 * @file exchangedb/pg_lookup_denomination_key.c
 * @brief Implementation of the lookup_denomination_key function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_denomination_key.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_lookup_denomination_key (
  void *cls,
  const struct TALER_DenominationHashP *h_denom_pub,
  struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_denom_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("valid_from",
                                     &meta->start),
    GNUNET_PQ_result_spec_timestamp ("expire_withdraw",
                                     &meta->expire_withdraw),
    GNUNET_PQ_result_spec_timestamp ("expire_deposit",
                                     &meta->expire_deposit),
    GNUNET_PQ_result_spec_timestamp ("expire_legal",
                                     &meta->expire_legal),
    TALER_PQ_RESULT_SPEC_AMOUNT ("coin",
                                 &meta->value),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_withdraw",
                                 &meta->fees.withdraw),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                 &meta->fees.deposit),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refresh",
                                 &meta->fees.refresh),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refund",
                                 &meta->fees.refund),
    GNUNET_PQ_result_spec_uint32 ("age_mask",
                                  &meta->age_mask.bits),
    GNUNET_PQ_result_spec_end
  };

      /* used in #postgres_lookup_denomination_key() */
  PREPARE (pg,
           "lookup_denomination_key",
           "SELECT"
           " valid_from"
           ",expire_withdraw"
           ",expire_deposit"
           ",expire_legal"
           ",coin_val"
           ",coin_frac"
           ",fee_withdraw_val"
           ",fee_withdraw_frac"
           ",fee_deposit_val"
           ",fee_deposit_frac"
           ",fee_refresh_val"
           ",fee_refresh_frac"
           ",fee_refund_val"
           ",fee_refund_frac"
           ",age_mask"
           " FROM denominations"
           " WHERE denom_pub_hash=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "lookup_denomination_key",
                                                   params,
                                                   rs);
}
