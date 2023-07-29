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
 * @file pg_select_purse.c
 * @brief Implementation of the select_purse function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_purse.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_select_purse (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct GNUNET_TIME_Timestamp *purse_creation,
  struct GNUNET_TIME_Timestamp *purse_expiration,
  struct TALER_Amount *amount,
  struct TALER_Amount *deposited,
  struct TALER_PrivateContractHashP *h_contract_terms,
  struct GNUNET_TIME_Timestamp *merge_timestamp,
  bool *purse_deleted)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("purse_expiration",
                                     purse_expiration),
    GNUNET_PQ_result_spec_timestamp ("purse_creation",
                                     purse_creation),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 amount),
    TALER_PQ_RESULT_SPEC_AMOUNT ("balance",
                                 deposited),
    GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                          h_contract_terms),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_timestamp ("merge_timestamp",
                                       merge_timestamp),
      NULL),
    GNUNET_PQ_result_spec_bool ("purse_deleted",
                                purse_deleted),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "select_purse",
           "SELECT "
           " pr.merge_pub"
           ",pr.purse_creation"
           ",pr.purse_expiration"
           ",pr.h_contract_terms"
           ",pr.amount_with_fee"
           ",pr.balance"
           ",pm.merge_timestamp"
           ",pd.purse_sig IS NOT NULL AS purse_deleted"
           " FROM purse_requests pr"
           " LEFT JOIN purse_merges pm ON (pm.purse_pub = pr.purse_pub)"
           " LEFT JOIN purse_deletion pd ON (pd.purse_pub = pr.purse_pub)"
           " WHERE pr.purse_pub=$1;");
  *merge_timestamp = GNUNET_TIME_UNIT_FOREVER_TS;
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_purse",
                                                   params,
                                                   rs);
}
