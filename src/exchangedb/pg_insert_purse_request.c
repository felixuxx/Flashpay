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
 * @file exchangedb/pg_insert_purse_request.c
 * @brief Implementation of the insert_purse_request function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_purse_request.h"
#include "pg_get_purse_request.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_purse_request (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  uint32_t age_limit,
  enum TALER_WalletAccountMergeFlags flags,
  const struct TALER_Amount *purse_fee,
  const struct TALER_Amount *amount,
  const struct TALER_PurseContractSignatureP *purse_sig,
  bool *in_conflict)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_TIME_Timestamp now = GNUNET_TIME_timestamp_get ();
  uint32_t flags32 = (uint32_t) flags;
  bool in_reserve_quota = (TALER_WAMF_MODE_CREATE_FROM_PURSE_QUOTA
                           == (flags & TALER_WAMF_MERGE_MODE_MASK));
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_auto_from_type (merge_pub),
    GNUNET_PQ_query_param_timestamp (&now),
    GNUNET_PQ_query_param_timestamp (&purse_expiration),
    GNUNET_PQ_query_param_auto_from_type (h_contract_terms),
    GNUNET_PQ_query_param_uint32 (&age_limit),
    GNUNET_PQ_query_param_uint32 (&flags32),
    GNUNET_PQ_query_param_bool (in_reserve_quota),
    TALER_PQ_query_param_amount (amount),
    TALER_PQ_query_param_amount (purse_fee),
    GNUNET_PQ_query_param_auto_from_type (purse_sig),
    GNUNET_PQ_query_param_end
  };

  *in_conflict = false;
  PREPARE (pg,
           "insert_purse_request",
           "INSERT INTO purse_requests"
           "  (purse_pub"
           "  ,merge_pub"
           "  ,purse_creation"
           "  ,purse_expiration"
           "  ,h_contract_terms"
           "  ,age_limit"
           "  ,flags"
           "  ,in_reserve_quota"
           "  ,amount_with_fee_val"
           "  ,amount_with_fee_frac"
           "  ,purse_fee_val"
           "  ,purse_fee_frac"
           "  ,purse_sig"
           "  ) VALUES "
           "  ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)"
           "  ON CONFLICT DO NOTHING;");
  qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                           "insert_purse_request",
                                           params);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs)
    return qs;
  {
    struct TALER_PurseMergePublicKeyP merge_pub2;
    struct GNUNET_TIME_Timestamp purse_expiration2;
    struct TALER_PrivateContractHashP h_contract_terms2;
    uint32_t age_limit2;
    struct TALER_Amount amount2;
    struct TALER_Amount balance;
    struct TALER_PurseContractSignatureP purse_sig2;

    qs = TEH_PG_get_purse_request (pg,
                                   purse_pub,
                                   &merge_pub2,
                                   &purse_expiration2,
                                   &h_contract_terms2,
                                   &age_limit2,
                                   &amount2,
                                   &balance,
                                   &purse_sig2);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if ( (age_limit2 == age_limit) &&
         (0 == TALER_amount_cmp (amount,
                                 &amount2)) &&
         (0 == GNUNET_memcmp (&h_contract_terms2,
                              h_contract_terms)) &&
         (0 == GNUNET_memcmp (&merge_pub2,
                              merge_pub)) )
    {
      return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
    }
    *in_conflict = true;
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }
}
