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
 * @file exchangedb/pg_insert_denomination_info.c
 * @brief Implementation of the insert_denomination_info function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_denomination_info.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_denomination_info (
  void *cls,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue)
{
  struct PostgresClosure *pg = cls;
  struct TALER_DenominationHashP denom_hash;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&issue->denom_hash),
    TALER_PQ_query_param_denom_pub (denom_pub),
    GNUNET_PQ_query_param_auto_from_type (&issue->signature),
    GNUNET_PQ_query_param_timestamp (&issue->start),
    GNUNET_PQ_query_param_timestamp (&issue->expire_withdraw),
    GNUNET_PQ_query_param_timestamp (&issue->expire_deposit),
    GNUNET_PQ_query_param_timestamp (&issue->expire_legal),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &issue->value),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &issue->fees.withdraw),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &issue->fees.deposit),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &issue->fees.refresh),
    TALER_PQ_query_param_amount_tuple (pg->conn,
                                       &issue->fees.refund),
    GNUNET_PQ_query_param_uint32 (&denom_pub->age_mask.bits),
    GNUNET_PQ_query_param_end
  };

  GNUNET_assert (denom_pub->age_mask.bits ==
                 issue->age_mask.bits);
  TALER_denom_pub_hash (denom_pub,
                        &denom_hash);
  GNUNET_assert (0 ==
                 GNUNET_memcmp (&denom_hash,
                                &issue->denom_hash));
  GNUNET_assert (! GNUNET_TIME_absolute_is_zero (
                   issue->start.abs_time));
  GNUNET_assert (! GNUNET_TIME_absolute_is_zero (
                   issue->expire_withdraw.abs_time));
  GNUNET_assert (! GNUNET_TIME_absolute_is_zero (
                   issue->expire_deposit.abs_time));
  GNUNET_assert (! GNUNET_TIME_absolute_is_zero (
                   issue->expire_legal.abs_time));
  /* check fees match denomination currency */
  GNUNET_assert (GNUNET_YES ==
                 TALER_denom_fee_check_currency (
                   issue->value.currency,
                   &issue->fees));
  PREPARE (pg,
           "denomination_insert",
           "INSERT INTO denominations "
           "(denom_pub_hash"
           ",denom_pub"
           ",master_sig"
           ",valid_from"
           ",expire_withdraw"
           ",expire_deposit"
           ",expire_legal"
           ",coin"  /* value of this denom */
           ",fee_withdraw"
           ",fee_deposit"
           ",fee_refresh"
           ",fee_refund"
           ",age_mask"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,"
           " $11, $12, $13);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "denomination_insert",
                                             params);
}
