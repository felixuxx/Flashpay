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
 * @file exchangedb/pg_get_denomination_info.c
 * @brief Implementation of the get_denomination_info function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_denomination_info.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_get_denomination_info (
  void *cls,
  const struct TALER_DenominationHashP *denom_pub_hash,
  struct TALER_EXCHANGEDB_DenominationKeyInformation *issue)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                          &issue->signature),
    GNUNET_PQ_result_spec_timestamp ("valid_from",
                                     &issue->start),
    GNUNET_PQ_result_spec_timestamp ("expire_withdraw",
                                     &issue->expire_withdraw),
    GNUNET_PQ_result_spec_timestamp ("expire_deposit",
                                     &issue->expire_deposit),
    GNUNET_PQ_result_spec_timestamp ("expire_legal",
                                     &issue->expire_legal),
    TALER_PQ_RESULT_SPEC_AMOUNT ("coin",
                                 &issue->value),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_withdraw",
                                 &issue->fees.withdraw),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                 &issue->fees.deposit),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refresh",
                                 &issue->fees.refresh),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refund",
                                 &issue->fees.refund),
    GNUNET_PQ_result_spec_uint32 ("age_mask",
                                  &issue->age_mask.bits),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "denomination_get",
           "SELECT"
           " master_sig"
           ",valid_from"
           ",expire_withdraw"
           ",expire_deposit"
           ",expire_legal"
           ",coin"  /* value of this denom */
           ",fee_withdraw"
           ",fee_deposit"
           ",fee_refresh"
           ",fee_refund"
           ",age_mask"
           " FROM denominations"
           " WHERE denom_pub_hash=$1;");
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "denomination_get",
                                                 params,
                                                 rs);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    return qs;
  issue->denom_hash = *denom_pub_hash;
  return qs;
}
