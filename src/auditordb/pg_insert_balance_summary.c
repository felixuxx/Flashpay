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
 * @file pg_insert_balance_summary.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_balance_summary.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_insert_balance_summary (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_AUDITORDB_GlobalCoinBalance *dfb)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    TALER_PQ_query_param_amount (&dfb->total_escrowed),
    TALER_PQ_query_param_amount (&dfb->deposit_fee_balance),
    TALER_PQ_query_param_amount (&dfb->melt_fee_balance),
    TALER_PQ_query_param_amount (&dfb->refund_fee_balance),
    TALER_PQ_query_param_amount (&dfb->purse_fee_balance),
    TALER_PQ_query_param_amount (&dfb->open_deposit_fee_balance),
    TALER_PQ_query_param_amount (&dfb->risk),
    TALER_PQ_query_param_amount (&dfb->loss),
    TALER_PQ_query_param_amount (&dfb->irregular_loss),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_balance_summary_insert",
           "INSERT INTO auditor_balance_summary "
           "(master_pub"
           ",denom_balance_val"
           ",denom_balance_frac"
           ",deposit_fee_balance_val"
           ",deposit_fee_balance_frac"
           ",melt_fee_balance_val"
           ",melt_fee_balance_frac"
           ",refund_fee_balance_val"
           ",refund_fee_balance_frac"
           ",purse_fee_balance_val"
           ",purse_fee_balance_frac"
           ",open_deposit_fee_balance_val"
           ",open_deposit_fee_balance_frac"
           ",risk_val"
           ",risk_frac"
           ",loss_val"
           ",loss_frac"
           ",irregular_loss_val"
           ",irregular_loss_frac"
           ") VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,"
           "          $11,$12,$13,$14,$15,$16,$17,$18,$19);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_balance_summary_insert",
                                             params);
}
