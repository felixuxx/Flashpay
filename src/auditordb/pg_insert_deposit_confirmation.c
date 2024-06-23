/*
   This file is part of TALER
   Copyright (C) 2022, 2023 Taler Systems SA

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
 * @file pg_insert_deposit_confirmation.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_deposit_confirmation.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_insert_deposit_confirmation (
  void *cls,
  const struct TALER_AUDITORDB_DepositConfirmation *dc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&dc->h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (&dc->h_policy),
    GNUNET_PQ_query_param_auto_from_type (&dc->h_wire),
    GNUNET_PQ_query_param_timestamp (&dc->exchange_timestamp),
    GNUNET_PQ_query_param_timestamp (&dc->wire_deadline),
    GNUNET_PQ_query_param_timestamp (&dc->refund_deadline),
    TALER_PQ_query_param_amount (pg->conn,
                                 &dc->total_without_fee),
    GNUNET_PQ_query_param_array_auto_from_type (dc->num_coins,
                                                dc->coin_pubs,
                                                pg->conn),
    GNUNET_PQ_query_param_array_auto_from_type (dc->num_coins,
                                                dc->coin_sigs,
                                                pg->conn),
    GNUNET_PQ_query_param_auto_from_type (&dc->merchant),
    GNUNET_PQ_query_param_auto_from_type (&dc->exchange_sig),
    GNUNET_PQ_query_param_auto_from_type (&dc->exchange_pub),
    GNUNET_PQ_query_param_auto_from_type (&dc->master_sig),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_deposit_confirmation_insert",
           "INSERT INTO auditor_deposit_confirmations "
           "(h_contract_terms"
           ",h_policy"
           ",h_wire"
           ",exchange_timestamp"
           ",wire_deadline"
           ",refund_deadline"
           ",total_without_fee"
           ",coin_pubs"
           ",coin_sigs"
           ",merchant_pub"
           ",exchange_sig"
           ",exchange_pub"
           ",master_sig"                  /* master_sig could be normalized... */
           ") VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_deposit_confirmation_insert",
                                             params);
}
