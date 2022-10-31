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
 * @file pg_get_wire_fee_summary.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_wire_fee_summary.h"
#include "pg_helper.h"


/**
 * Get summary information about an exchanges wire fee balance.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master public key of the exchange
 * @param[out] wire_fee_balance set amount the exchange gained in wire fees
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_get_wire_fee_summary (void *cls,
                             const struct TALER_MasterPublicKeyP *master_pub,
                             struct TALER_Amount *wire_fee_balance)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("wire_fee_balance",
                                 wire_fee_balance),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "auditor_wire_fee_balance_select",
           "SELECT"
           " wire_fee_balance_val"
           ",wire_fee_balance_frac"
           " FROM auditor_wire_fee_balance"
           " WHERE master_pub=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_wire_fee_balance_select",
                                                   params,
                                                   rs);
}
