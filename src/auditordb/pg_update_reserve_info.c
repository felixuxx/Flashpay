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
 * @file pg_update_reserve_info.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_update_reserve_info.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_update_reserve_info (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_AUDITORDB_ReserveFeeBalance *rfb,
  struct GNUNET_TIME_Timestamp expiration_date)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (pg->conn,
                                 &rfb->reserve_balance),
    TALER_PQ_query_param_amount (pg->conn,
                                 &rfb->reserve_loss),
    TALER_PQ_query_param_amount (pg->conn,
                                 &rfb->withdraw_fee_balance),
    TALER_PQ_query_param_amount (pg->conn,
                                 &rfb->purse_fee_balance),
    TALER_PQ_query_param_amount (pg->conn,
                                 &rfb->open_fee_balance),
    TALER_PQ_query_param_amount (pg->conn,
                                 &rfb->history_fee_balance),
    GNUNET_PQ_query_param_timestamp (&expiration_date),
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_update_reserve_info",
           "UPDATE auditor_reserves SET"
           " reserve_balance=$1"
           ",reserve_loss=$2"
           ",withdraw_fee_balance=$3"
           ",purse_fee_balance=$4"
           ",open_fee_balance=$5"
           ",history_fee_balance=$6"
           ",expiration_date=$7"
           " WHERE reserve_pub=$8");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_update_reserve_info",
                                             params);
}
