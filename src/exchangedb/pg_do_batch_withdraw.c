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
 * @file exchangedb/pg_do_batch_withdraw.c
 * @brief Implementation of the do_batch_withdraw function for Postgres
 * @author Christian Grothoff
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_do_batch_withdraw.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_do_batch_withdraw (
  void *cls,
  struct GNUNET_TIME_Timestamp now,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_Amount *amount,
  bool do_age_check,
  bool *found,
  bool *balance_ok,
  bool *age_ok,
  uint16_t *allowed_maximum_age,
  uint64_t *ruuid)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Timestamp gc;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       amount),
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_timestamp (&now),
    GNUNET_PQ_query_param_timestamp (&gc),
    GNUNET_PQ_query_param_bool (do_age_check),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("reserve_found",
                                found),
    GNUNET_PQ_result_spec_bool ("balance_ok",
                                balance_ok),
    GNUNET_PQ_result_spec_bool ("age_ok",
                                age_ok),
    GNUNET_PQ_result_spec_uint16 ("allowed_maximum_age",
                                  allowed_maximum_age),
    GNUNET_PQ_result_spec_uint64 ("ruuid",
                                  ruuid),
    GNUNET_PQ_result_spec_end
  };

  gc = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (now.abs_time,
                              pg->legal_reserve_expiration_time));


  /* Used in #postgres_do_batch_withdraw() to
        update the reserve balance and check its status */
  PREPARE (pg,
           "call_batch_withdraw",
           "SELECT "
           " reserve_found"
           ",balance_ok"
           ",age_ok"
           ",allowed_maximum_age"
           ",ruuid"
           " FROM exchange_do_batch_withdraw"
           " ($1,$2,$3,$4,$5);");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_batch_withdraw",
                                                   params,
                                                   rs);
}
