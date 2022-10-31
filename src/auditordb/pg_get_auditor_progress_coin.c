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
 * @file pg_get_auditor_progress_coin.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_auditor_progress_coin.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_get_auditor_progress_coin (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct TALER_AUDITORDB_ProgressPointCoin *ppc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("last_withdraw_serial_id",
                                  &ppc->last_withdraw_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_deposit_serial_id",
                                  &ppc->last_deposit_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_melt_serial_id",
                                  &ppc->last_melt_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_refund_serial_id",
                                  &ppc->last_refund_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_recoup_serial_id",
                                  &ppc->last_recoup_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_recoup_refresh_serial_id",
                                  &ppc->last_recoup_refresh_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_purse_deposits_serial_id",
                                  &ppc->last_purse_deposits_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_purse_decision_serial_id",
                                  &ppc->last_purse_refunds_serial_id),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "auditor_progress_select_coin",
           "SELECT"
           " last_withdraw_serial_id"
           ",last_deposit_serial_id"
           ",last_melt_serial_id"
           ",last_refund_serial_id"
           ",last_recoup_serial_id"
           ",last_recoup_refresh_serial_id"
           ",last_purse_deposits_serial_id"
           ",last_purse_decision_serial_id"
           " FROM auditor_progress_coin"
           " WHERE master_pub=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_progress_select_coin",
                                                   params,
                                                   rs);
}
