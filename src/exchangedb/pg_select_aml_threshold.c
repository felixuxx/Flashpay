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
 * @file exchangedb/pg_select_aml_threshold.c
 * @brief Implementation of the select_aml_threshold function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_aml_threshold.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_select_aml_threshold (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  enum TALER_AmlDecisionState *decision,
  struct TALER_EXCHANGEDB_KycStatus *kyc,
  struct TALER_Amount *threshold)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_end
  };
  uint32_t status32 = TALER_AML_NORMAL;
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("threshold",
                                 threshold),
    GNUNET_PQ_result_spec_uint32 ("status",
                                  &status32),
    GNUNET_PQ_result_spec_uint64 ("kyc_requirement",
                                  &kyc->requirement_row),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "select_aml_threshold",
           "SELECT"
           " threshold"
           ",status"
           ",kyc_requirement"
           " FROM aml_status"
           " WHERE h_payto=$1;");
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "select_aml_threshold",
                                                 params,
                                                 rs);
  *decision = (enum TALER_AmlDecisionState) status32;
  kyc->ok = (TALER_AML_FROZEN != *decision)
            || (0 != kyc->requirement_row);
  return qs;
}
