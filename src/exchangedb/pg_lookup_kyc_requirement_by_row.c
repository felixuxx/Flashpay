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
  uint64_t requirement_row,
  union TALER_AccountPublicKeyP *account_pub,
  struct TALER_AccountAccessTokenP *access_token,
  json_t **jrules,
  bool *aml_review,
  bool *kyc_required)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&requirement_row),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("account_pub",
                                            account_pub),
      NULL),
    GNUNET_PQ_result_spec_auto_from_type ("access_token",
                                          access_token),
    GNUNET_PQ_result_spec_allow_null (
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
    GNUNET_PQ_result_spec_end
  };

  *jrules = NULL;
  *aml_review = false;
  memset (account_pub,
          0,
          sizeof (*account_pub));
  PREPARE (pg,
           "lookup_kyc_requirement_by_row",
           "SELECT "
           " wt.target_pub AS account_pub"
           ",lm.access_token"
           ",lo.jnew_rules AS jrules"
           ",lo.to_investigate AS aml_review"
           ",NOT lm.is_finished AS kyc_required"
           " FROM legitimization_measures lm"
           " JOIN wire_targets wt"
           "   USING (access_token)"
           " LEFT JOIN legitimization_outcomes lo"
           "   ON (wt.wire_target_h_payto = lo.h_payto)"
           " WHERE lm.legitimization_measure_serial_id=$1"
           "   AND ( (lo.is_active IS NULL)"
           "          OR lo.is_active);");
  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "lookup_kyc_requirement_by_row",
    params,
    rs);
}
