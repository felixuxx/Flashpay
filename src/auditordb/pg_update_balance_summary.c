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
    TALER_PQ_query_param_amount (pg->conn,
                                 &dfb->total_escrowed),
    TALER_PQ_query_param_amount (pg->conn,
                                 &dfb->deposit_fee_balance),
    TALER_PQ_query_param_amount (pg->conn,
                                 &dfb->melt_fee_balance),
    TALER_PQ_query_param_amount (pg->conn,
                                 &dfb->refund_fee_balance),
    TALER_PQ_query_param_amount (pg->conn,
                                 &dfb->purse_fee_balance),
    TALER_PQ_query_param_amount (pg->conn,
                                 &dfb->open_deposit_fee_balance),
    TALER_PQ_query_param_amount (pg->conn,
                                 &dfb->risk),
    TALER_PQ_query_param_amount (pg->conn,
                                 &dfb->loss),
    TALER_PQ_query_param_amount (pg->conn,
                                 &dfb->irregular_loss),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_balance_summary_update",
           "UPDATE auditor_balance_summary SET"
           " denom_balance=$1"
           ",deposit_fee_balance=$2"
           ",melt_fee_balance=$3"
           ",refund_fee_balance=$4"
           ",purse_fee_balance=$5"
           ",open_deposit_fee_balance=$6"
           ",risk=$7"
           ",loss=$8"
           ",irregular_loss=$9"
           " WHERE master_pub=$10;");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_balance_summary_update",
                                             params);
}
