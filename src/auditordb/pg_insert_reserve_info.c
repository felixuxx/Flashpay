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
 * @file pg_insert_reserve_info.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_reserve_info.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_insert_reserve_info (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_AUDITORDB_ReserveFeeBalance *rfb,
  struct GNUNET_TIME_Timestamp expiration_date,
  const char *origin_account)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    TALER_PQ_query_param_amount (pg->conn,
                                 &rfb->reserve_balance),
    TALER_PQ_query_param_amount (pg->conn,
                                 &rfb->reserve_loss),
    TALER_PQ_query_param_amount (pg->conn,
                                 &rfb->withdraw_fee_balance),
    TALER_PQ_query_param_amount (pg->conn,
                                 &rfb->close_fee_balance),
    TALER_PQ_query_param_amount (pg->conn,
                                 &rfb->purse_fee_balance),
    TALER_PQ_query_param_amount (pg->conn,
                                 &rfb->open_fee_balance),
    TALER_PQ_query_param_amount (pg->conn,
                                 &rfb->history_fee_balance),
    GNUNET_PQ_query_param_timestamp (&expiration_date),
    NULL == origin_account
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_string (origin_account),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_reserves_insert",
           "INSERT INTO auditor_reserves "
           "(reserve_pub"
           ",master_pub"
           ",reserve_balance"
           ",reserve_loss"
           ",withdraw_fee_balance"
           ",close_fee_balance"
           ",purse_fee_balance"
           ",open_fee_balance"
           ",history_fee_balance"
           ",expiration_date"
           ",origin_account"

           ") VALUES "
           "($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_reserves_insert",
                                             params);
}
