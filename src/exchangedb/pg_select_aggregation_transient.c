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
 * @file exchangedb/pg_select_aggregation_transient.c
 * @brief Implementation of the select_aggregation_transient function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_aggregation_transient.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_select_aggregation_transient (
  void *cls,
  const struct TALER_FullPaytoHashP *h_payto,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const char *exchange_account_section,
  struct TALER_WireTransferIdentifierRawP *wtid,
  struct TALER_Amount *total)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_string (exchange_account_section),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                 total),
    GNUNET_PQ_result_spec_auto_from_type ("wtid_raw",
                                          wtid),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "select_aggregation_transient",
           "SELECT"
           "  amount"
           " ,wtid_raw"
           " FROM aggregation_transient"
           " WHERE wire_target_h_payto=$1"
           "   AND merchant_pub=$2"
           "   AND exchange_account_section=$3;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_aggregation_transient",
                                                   params,
                                                   rs);
}
