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
 * @file exchangedb/pg_create_aggregation_transient.c
 * @brief Implementation of the create_aggregation_transient function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_create_aggregation_transient.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_create_aggregation_transient (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const char *exchange_account_section,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  uint64_t kyc_requirement_row,
  const struct TALER_Amount *total)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (total),
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_uint64 (&kyc_requirement_row),
    GNUNET_PQ_query_param_string (exchange_account_section),
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_end
  };
    /* Used in #postgres_create_aggregation_transient() */
  PREPARE (pg,
      "create_aggregation_transient",
      "INSERT INTO aggregation_transient"
      " (amount_val"
      " ,amount_frac"
      " ,merchant_pub"
      " ,wire_target_h_payto"
      " ,legitimization_requirement_serial_id"
      " ,exchange_account_section"
      " ,wtid_raw)"
      " VALUES ($1, $2, $3, $4, $5, $6, $7);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "create_aggregation_transient",
                                             params);
}
