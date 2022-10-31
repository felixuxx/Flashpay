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
 * @file pg_update_auditor_progress_coin.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_update_auditor_progress_coin.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_update_auditor_progress_coin (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_AUDITORDB_ProgressPointCoin *ppc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&ppc->last_withdraw_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_deposit_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_melt_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_refund_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_recoup_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_recoup_refresh_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_purse_deposits_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_purse_refunds_serial_id),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_progress_update_coin",
           "UPDATE auditor_progress_coin SET "
           " last_withdraw_serial_id=$1"
           ",last_deposit_serial_id=$2"
           ",last_melt_serial_id=$3"
           ",last_refund_serial_id=$4"
           ",last_recoup_serial_id=$5"
           ",last_recoup_refresh_serial_id=$6"
           ",last_purse_deposits_serial_id=$7"
           ",last_purse_decision_serial_id=$8"
           " WHERE master_pub=$9");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_progress_update_coin",
                                             params);
}
