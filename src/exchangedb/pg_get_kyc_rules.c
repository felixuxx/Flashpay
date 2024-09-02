/*
   This file is part of TALER
   Copyright (C) 2022-2024 Taler Systems SA

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
 * @file exchangedb/pg_get_kyc_rules.c
 * @brief Implementation of the get_kyc_rules function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_kyc_rules.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_get_kyc_rules (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  union TALER_AccountPublicKeyP *account_pub,
  json_t **jrules)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Timestamp now
    = GNUNET_TIME_timestamp_get ();
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_timestamp (&now),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("target_pub",
                                          account_pub),
    TALER_PQ_result_spec_json ("jnew_rules",
                               jrules),
    GNUNET_PQ_result_spec_end
  };

  memset (account_pub,
          0,
          sizeof (*account_pub));
  PREPARE (pg,
           "get_kyc_rules",
           "SELECT"
           "  wt.target_pub"
           " ,lo.jnew_rules"
           "  FROM legitimization_outcomes lo"
           "  JOIN wire_targets wt"
           "    ON (lo.h_payto = wt.wire_target_h_payto)"
           " WHERE h_payto=$1"
           "   AND expiration_time >= $2"
           "   AND is_active;");
  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "get_kyc_rules",
    params,
    rs);
}
