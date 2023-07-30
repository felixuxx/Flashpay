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
 * @file pg_update_reserve_summary.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_update_reserve_summary.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_update_reserve_summary (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_AUDITORDB_ReserveFeeBalance *rfb)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &rfb->reserve_balance),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &rfb->reserve_loss),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &rfb->withdraw_fee_balance),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &rfb->close_fee_balance),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &rfb->purse_fee_balance),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &rfb->open_fee_balance),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &rfb->history_fee_balance),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_reserve_balance_update",
           "UPDATE auditor_reserve_balance SET"
           " reserve_balance=$1"
           ",reserve_loss=$2"
           ",withdraw_fee_balance=$3"
           ",close_fee_balance=$4"
           ",purse_fee_balance=$5"
           ",open_fee_balance=$6"
           ",history_fee_balance=$7"
           " WHERE master_pub=$8;");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_reserve_balance_update",
                                             params);
}
