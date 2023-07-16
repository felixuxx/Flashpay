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
 * @file exchangedb/pg_insert_refund.c
 * @brief Implementation of the insert_refund function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_refund.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_refund (void *cls,
                      const struct TALER_EXCHANGEDB_Refund *refund)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&refund->coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&refund->details.merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (&refund->details.merchant_sig),
    GNUNET_PQ_query_param_auto_from_type (&refund->details.h_contract_terms),
    GNUNET_PQ_query_param_uint64 (&refund->details.rtransaction_id),
    TALER_PQ_query_param_amount (&refund->details.refund_amount),
    GNUNET_PQ_query_param_end
  };

  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (&refund->details.refund_amount,
                                            &refund->details.refund_fee));

  PREPARE (pg,
           "insert_refund",
           "INSERT INTO refunds "
           "(coin_pub"
           ",deposit_serial_id"
           ",merchant_sig"
           ",rtransaction_id"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ") SELECT $1, deposit_serial_id, $3, $5, $6, $7"
           "    FROM deposits"
           "   WHERE coin_pub=$1"
           "     AND h_contract_terms=$4"
           "     AND merchant_pub=$2");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_refund",
                                             params);
}
