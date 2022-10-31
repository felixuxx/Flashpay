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
 * @file pg_get_balance_summary.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_balance_summary.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_get_balance_summary (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct TALER_AUDITORDB_GlobalCoinBalance *dfb)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("denom_balance",
                                 &dfb->total_escrowed),
    TALER_PQ_RESULT_SPEC_AMOUNT ("deposit_fee_balance",
                                 &dfb->deposit_fee_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("melt_fee_balance",
                                 &dfb->melt_fee_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("refund_fee_balance",
                                 &dfb->refund_fee_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("purse_fee_balance",
                                 &dfb->purse_fee_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("open_deposit_fee_balance",
                                 &dfb->open_deposit_fee_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("risk",
                                 &dfb->risk),
    TALER_PQ_RESULT_SPEC_AMOUNT ("loss",
                                 &dfb->loss),
    TALER_PQ_RESULT_SPEC_AMOUNT ("irregular_loss",
                                 &dfb->irregular_loss),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "auditor_balance_summary_select",
           "SELECT"
           " denom_balance_val"
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
           " FROM auditor_balance_summary"
           " WHERE master_pub=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_balance_summary_select",
                                                   params,
                                                   rs);
}
