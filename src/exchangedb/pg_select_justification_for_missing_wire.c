/*
   This file is part of TALER
   Copyright (C) 2022-2023 Taler Systems SA

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
 * @file exchangedb/pg_select_batch_deposits_missing_wire.c
 * @brief Implementation of the select_batch_deposits_missing_wire function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_batch_deposits_missing_wire.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_select_justification_for_missing_wire (
  void *cls,
  const struct TALER_PaytoHashP *wire_target_h_payto,
  char **payto_uri,
  char **kyc_pending,
  enum TALER_AmlDecisionState *status,
  struct TALER_Amount *aml_limit)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now
    = GNUNET_TIME_absolute_get ();
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (wire_target_h_payto),
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  uint32_t aml_status32;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_string ("payto_uri",
                                    payto_uri),
      NULL),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_string ("kyc_pending",
                                    kyc_pending),
      NULL),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_uint32 ("aml_status",
                                    &aml_status32),
      NULL),
    GNUNET_PQ_result_spec_allow_null (
      TALER_PQ_RESULT_SPEC_AMOUNT ("aml_limit",
                                   aml_limit),
      NULL),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "deposits_get_overdue",
           "SELECT"
           " out_payto_uri AS payto_uri"
           ",out_kyc_pending AS kyc_pending"
           ",out_deadline AS deadline"
           ",out_aml_status AS aml_status"
           ",out_aml_limit AS aml_limit"
           " FROM exchange_do_select_justification_missing_wire"
           " ($1, $2);");
  memset (aml_limit,
          0,
          sizeof (*aml_limit));
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "",
                                                 params,
                                                 rs);
  if (qs <= 0)
    return qs;
  *status = (enum TALER_AmlDecisionState) aml_status32;
  return qs;
}
