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
  uint32_t status = TALER_AML_NORMAL;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&requirement_row),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_string ("required_checks",
                                  requirements),
    GNUNET_PQ_result_spec_auto_from_type ("h_payto",
                                          h_payto),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_uint32 ("status",
                                    &status),
      NULL),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "lookup_legitimization_requirement_by_row",
           "SELECT "
           " lm.access_token"
           ",lo.to_investigate AS aml_review" // can be NULL => false!
           ",lo.jnew_rules AS jrules" // can be NULL! => default rules!
           ",lm.is_finished AS NOT kyc_required"
           ",wt.target_pub AS account_pub" // can be NULL!
           " FROM legitimization_measures lm"
           " JOIN wire_targets wt"
           "   USING (access_token)"
           " LEFT JOIN legitimization_outcomes lo"
           "   USING (h_payto)"
           " WHERE legitimization_measure_serial_id=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "lookup_legitimization_requirement_by_row",
    params,
    rs);
}
