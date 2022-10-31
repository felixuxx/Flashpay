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
 * @file pg_get_reserve_summary.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_reserve_summary.h"
#include "pg_helper.h"


/**
 * Get summary information about all reserves.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master public key of the exchange
 * @param[out] rfb balances are returned here
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_get_reserve_summary (void *cls,
                            const struct TALER_MasterPublicKeyP *master_pub,
                            struct TALER_AUDITORDB_ReserveFeeBalance *rfb)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("reserve_balance",
                                 &rfb->reserve_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("reserve_loss",
                                 &rfb->reserve_loss),
    TALER_PQ_RESULT_SPEC_AMOUNT ("withdraw_fee_balance",
                                 &rfb->withdraw_fee_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("close_fee_balance",
                                 &rfb->close_fee_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("purse_fee_balance",
                                 &rfb->purse_fee_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("open_fee_balance",
                                 &rfb->open_fee_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("history_fee_balance",
                                 &rfb->history_fee_balance),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "auditor_reserve_balance_select",
           "SELECT"
           " reserve_balance_val"
           ",reserve_balance_frac"
           ",reserve_loss_val"
           ",reserve_loss_frac"
           ",withdraw_fee_balance_val"
           ",withdraw_fee_balance_frac"
           ",close_fee_balance_val"
           ",close_fee_balance_frac"
           ",purse_fee_balance_val"
           ",purse_fee_balance_frac"
           ",open_fee_balance_val"
           ",open_fee_balance_frac"
           ",history_fee_balance_val"
           ",history_fee_balance_frac"
           " FROM auditor_reserve_balance"
           " WHERE master_pub=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_reserve_balance_select",
                                                   params,
                                                   rs);
}
