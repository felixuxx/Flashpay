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
 * @file exchangedb/pg_do_purse_deposit.c
 * @brief Implementation of the do_purse_deposit function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_do_purse_deposit.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_do_purse_deposit (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_Amount *amount,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  const struct TALER_Amount *amount_minus_fee,
  bool *balance_ok,
  bool *too_late,
  bool *conflict)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Timestamp now = GNUNET_TIME_timestamp_get ();
  struct GNUNET_TIME_Timestamp reserve_expiration;
  uint64_t partner_id = 0; /* FIXME #7271: WAD support... */
  struct GNUNET_PQ_QueryParam params[] = {
    (0 == partner_id)
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_uint64 (&partner_id),
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    TALER_PQ_query_param_amount (
      pg->conn,
      amount),
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_auto_from_type (coin_sig),
    TALER_PQ_query_param_amount (
      pg->conn,
      amount_minus_fee),
    GNUNET_PQ_query_param_timestamp (&reserve_expiration),
    GNUNET_PQ_query_param_timestamp (&now),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("balance_ok",
                                balance_ok),
    GNUNET_PQ_result_spec_bool ("too_late",
                                too_late),
    GNUNET_PQ_result_spec_bool ("conflict",
                                conflict),
    GNUNET_PQ_result_spec_end
  };

  reserve_expiration
    = GNUNET_TIME_absolute_to_timestamp (
        GNUNET_TIME_absolute_add (GNUNET_TIME_absolute_get (),
                                  pg->legal_reserve_expiration_time));

  PREPARE (pg,
           "call_purse_deposit",
           "SELECT "
           " out_balance_ok AS balance_ok"
           ",out_conflict AS conflict"
           ",out_late AS too_late"
           " FROM exchange_do_purse_deposit"
           " ($1,$2,$3,$4,$5,$6,$7,$8);");

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_purse_deposit",
                                                   params,
                                                   rs);
}
