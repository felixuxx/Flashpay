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
 * @file exchangedb/pg_store_wire_transfer_out.c
 * @brief Implementation of the store_wire_transfer_out function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_store_wire_transfer_out.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_store_wire_transfer_out (
  void *cls,
  struct GNUNET_TIME_Timestamp date,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_PaytoHashP *h_payto,
  const char *exchange_account_section,
  const struct TALER_Amount *amount)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&date),
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_string (exchange_account_section),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       amount),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_wire_out",
           "INSERT INTO wire_out "
           "(execution_date"
           ",wtid_raw"
           ",wire_target_h_payto"
           ",exchange_account_section"
           ",amount"
           ") VALUES "
           "($1, $2, $3, $4, $5);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_wire_out",
                                             params);
}
