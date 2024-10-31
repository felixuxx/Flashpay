/*
   This file is part of TALER
   Copyright (C) 2022, 2024 Taler Systems SA

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
 * @file exchangedb/pg_lookup_kyc_requirement_by_row.c
 * @brief Implementation of the lookup_kyc_requirement_by_row function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_kyc_requirement_by_row.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_lookup_kyc_requirement_by_row (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  union TALER_AccountPublicKeyP *account_pub,
  struct TALER_ReservePublicKeyP *reserve_pub,
  struct TALER_AccountAccessTokenP *access_token,
  json_t **jrules,
  bool *aml_review,
  bool *kyc_required)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_end
  };
  bool not_found;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("account_pub",
                                            account_pub),
      NULL),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            reserve_pub),
      NULL),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("access_token",
                                            access_token),
      NULL),
    GNUNET_PQ_result_spec_allow_null (
      /* can be NULL due to LEFT JOIN */
      TALER_PQ_result_spec_json ("jrules",
                                 jrules),
      NULL),
    GNUNET_PQ_result_spec_allow_null (
      /* can be NULL due to LEFT JOIN */
      GNUNET_PQ_result_spec_bool ("aml_review",
                                  aml_review),
      NULL),
    GNUNET_PQ_result_spec_bool ("kyc_required",
                                kyc_required),
    GNUNET_PQ_result_spec_bool ("not_found",
                                &not_found),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  *jrules = NULL;
  *aml_review = false;
  memset (account_pub,
          0,
          sizeof (*account_pub));
  memset (reserve_pub,
          0,
          sizeof (*reserve_pub));
  memset (access_token,
          0,
          sizeof (*access_token));
  PREPARE (pg,
           "lookup_kyc_requirement_by_row",
           "SELECT "
           " out_account_pub AS account_pub"
           ",out_reserve_pub AS reserve_pub"
           ",out_access_token AS access_token"
           ",out_jrules AS jrules"
           ",out_not_found AS not_found"
           ",out_aml_review AS aml_review"
           ",out_kyc_required AS kyc_required"
           " FROM exchange_do_lookup_kyc_requirement_by_row"
           " ($1);");
  qs = GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "lookup_kyc_requirement_by_row",
    params,
    rs);
  if (qs <= 0)
    return qs;
  if (not_found)
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  return qs;
}
