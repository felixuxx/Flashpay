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
 * @file exchangedb/pg_template.c
 * @brief Implementation of the template function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_purse_request.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_get_purse_request (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct TALER_PurseMergePublicKeyP *merge_pub,
  struct GNUNET_TIME_Timestamp *purse_expiration,
  struct TALER_PrivateContractHashP *h_contract_terms,
  uint32_t *age_limit,
  struct TALER_Amount *target_amount,
  struct TALER_Amount *balance,
  struct TALER_PurseContractSignatureP *purse_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("merge_pub",
                                          merge_pub),
    GNUNET_PQ_result_spec_timestamp ("purse_expiration",
                                     purse_expiration),
    GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                          h_contract_terms),
    GNUNET_PQ_result_spec_uint32 ("age_limit",
                                  age_limit),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 target_amount),
    TALER_PQ_RESULT_SPEC_AMOUNT ("balance",
                                 balance),
    GNUNET_PQ_result_spec_auto_from_type ("purse_sig",
                                          purse_sig),
    GNUNET_PQ_result_spec_end
  };
  
  PREPARE (pg,
           "get_purse_request",
           "SELECT "
           " merge_pub"
           ",purse_expiration"
           ",h_contract_terms"
           ",age_limit"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",balance_val"
           ",balance_frac"
           ",purse_sig"
           " FROM purse_requests"
           " WHERE purse_pub=$1;");

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_purse_request",
                                                   params,
                                                   rs);
}

