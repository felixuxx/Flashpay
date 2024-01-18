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
 * @file pg_get_reserve_info.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_reserve_info.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_get_reserve_info (void *cls,
                         const struct TALER_ReservePublicKeyP *reserve_pub,
                         uint64_t *rowid,
                         struct TALER_AUDITORDB_ReserveFeeBalance *rfb,
                         struct GNUNET_TIME_Timestamp *expiration_date,
                         char **sender_account)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
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
    GNUNET_PQ_result_spec_timestamp ("expiration_date",
                                     expiration_date),
    GNUNET_PQ_result_spec_uint64 ("auditor_reserves_rowid",
                                  rowid),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_string ("origin_account",
                                    sender_account),
      NULL),
    GNUNET_PQ_result_spec_end
  };

  *sender_account = NULL;
  PREPARE (pg,
           "auditor_get_reserve_info",
           "SELECT"
           " reserve_balance"
           ",reserve_loss"
           ",withdraw_fee_balance"
           ",close_fee_balance"
           ",purse_fee_balance"
           ",open_fee_balance"
           ",history_fee_balance"
           ",expiration_date"
           ",auditor_reserves_rowid"
           ",origin_account"
           " FROM auditor_reserves"
           " WHERE reserve_pub=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_get_reserve_info",
                                                   params,
                                                   rs);
}
