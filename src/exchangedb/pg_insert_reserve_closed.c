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
 * @file exchangedb/pg_insert_reserve_closed.c
 * @brief Implementation of the insert_reserve_closed function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_reserve_closed.h"
#include "pg_helper.h"
#include "pg_reserves_get.h"
#include "pg_reserves_update.h"

enum GNUNET_DB_QueryStatus
TEH_PG_insert_reserve_closed (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct GNUNET_TIME_Timestamp execution_date,
  const char *receiver_account,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *closing_fee,
  uint64_t close_request_row)
{
  struct PostgresClosure *pg = cls;
  struct TALER_EXCHANGEDB_Reserve reserve;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_PaytoHashP h_payto;

  TALER_payto_hash (receiver_account,
                    &h_payto);
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (reserve_pub),
      GNUNET_PQ_query_param_timestamp (&execution_date),
      GNUNET_PQ_query_param_auto_from_type (wtid),
      GNUNET_PQ_query_param_auto_from_type (&h_payto),
      TALER_PQ_query_param_amount (amount_with_fee),
      TALER_PQ_query_param_amount (closing_fee),
      GNUNET_PQ_query_param_uint64 (&close_request_row),
      GNUNET_PQ_query_param_end
    };

    /* Used in #postgres_insert_reserve_closed() */
    PREPARE (pg,
             "reserves_close_insert",
             "INSERT INTO reserves_close "
             "(reserve_pub"
             ",execution_date"
             ",wtid"
             ",wire_target_h_payto"
             ",amount_val"
             ",amount_frac"
             ",closing_fee_val"
             ",closing_fee_frac"
             ",close_request_row"
             ") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9);");

    qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "reserves_close_insert",
                                             params);
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    return qs;

  /* update reserve balance */
  reserve.pub = *reserve_pub;
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      (qs = TEH_PG_reserves_get (cls,
                                 &reserve)))
  {
    /* Existence should have been checked before we got here... */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
      qs = GNUNET_DB_STATUS_HARD_ERROR;
    return qs;
  }
  {
    enum TALER_AmountArithmeticResult ret;

    ret = TALER_amount_subtract (&reserve.balance,
                                 &reserve.balance,
                                 amount_with_fee);
    if (ret < 0)
    {
      /* The reserve history was checked to make sure there is enough of a balance
         left before we tried this; however, concurrent operations may have changed
         the situation by now.  We should re-try the transaction.  */
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Closing of reserve `%s' refused due to balance mismatch. Retrying.\n",
                  TALER_B2S (reserve_pub));
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    GNUNET_break (TALER_AAR_RESULT_ZERO == ret);
  }
  return TEH_PG_reserves_update (cls,
                                 &reserve);
}
