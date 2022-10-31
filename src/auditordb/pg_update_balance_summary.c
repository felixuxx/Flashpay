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
 * @file pg_update_balance_summary.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_update_balance_summary.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_update_balance_summary (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_AUDITORDB_GlobalCoinBalance *dfb)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (&dfb->total_escrowed),
    TALER_PQ_query_param_amount (&dfb->deposit_fee_balance),
    TALER_PQ_query_param_amount (&dfb->melt_fee_balance),
    TALER_PQ_query_param_amount (&dfb->refund_fee_balance),
    TALER_PQ_query_param_amount (&dfb->purse_fee_balance),
    TALER_PQ_query_param_amount (&dfb->open_deposit_fee_balance),
    TALER_PQ_query_param_amount (&dfb->risk),
    TALER_PQ_query_param_amount (&dfb->loss),
    TALER_PQ_query_param_amount (&dfb->irregular_loss),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_balance_summary_update",
           "UPDATE auditor_balance_summary SET"
           " denom_balance_val=$1"
           ",denom_balance_frac=$2"
           ",deposit_fee_balance_val=$3"
           ",deposit_fee_balance_frac=$4"
           ",melt_fee_balance_val=$5"
           ",melt_fee_balance_frac=$6"
           ",refund_fee_balance_val=$7"
           ",refund_fee_balance_frac=$8"
           ",purse_fee_balance_val=$9"
           ",purse_fee_balance_frac=$10"
           ",open_deposit_fee_balance_val=$11"
           ",open_deposit_fee_balance_frac=$12"
           ",risk_val=$13"
           ",risk_frac=$14"
           ",loss_val=$15"
           ",loss_frac=$16"
           ",irregular_loss_val=$17"
           ",irregular_loss_frac=$18"
           " WHERE master_pub=$19;");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_balance_summary_update",
                                             params);
}
