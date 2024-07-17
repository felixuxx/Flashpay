/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

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
 * @file exchangedb/pg_kycauth_in_insert.c
 * @brief Implementation of the kycauth_in_insert function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_kycauth_in_insert.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_kycauth_in_insert (
  void *cls,
  const union TALER_AccountPublicKeyP *account_pub,
  const struct TALER_Amount *credit_amount,
  struct GNUNET_TIME_Timestamp execution_date,
  const char *debit_account_uri,
  const char *section_name,
  uint64_t serial_id)
{
  struct PostgresClosure *pg = cls;
  struct TALER_PaytoHashP h_payto;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (account_pub),
    GNUNET_PQ_query_param_uint64 (&serial_id),
    TALER_PQ_query_param_amount (pg->conn,
                                 credit_amount),
    GNUNET_PQ_query_param_auto_from_type (&h_payto),
    GNUNET_PQ_query_param_string (debit_account_uri),
    GNUNET_PQ_query_param_string (section_name),
    GNUNET_PQ_query_param_timestamp (&execution_date),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "kycauth_in_insert",
           "CALL"
           " exchange_do_kycauth_in_insert"
           " ($1,$2,$3,$4,$5,$6,$7);");
  TALER_payto_hash (debit_account_uri,
                    &h_payto);
  return GNUNET_PQ_eval_prepared_non_select (
    pg->conn,
    "kycauth_in_insert",
    params);
}
