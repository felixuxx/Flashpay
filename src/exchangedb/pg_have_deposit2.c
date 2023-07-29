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
 * @file exchangedb/pg_have_deposit2.c
 * @brief Implementation of the have_deposit2 function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_have_deposit2.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_have_deposit2 (
  void *cls,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant,
  struct GNUNET_TIME_Timestamp refund_deadline,
  struct TALER_Amount *deposit_fee,
  struct GNUNET_TIME_Timestamp *exchange_timestamp)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_auto_from_type (h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (merchant),
    GNUNET_PQ_query_param_end
  };
  struct TALER_EXCHANGEDB_Deposit deposit2;
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 &deposit2.amount_with_fee),
    GNUNET_PQ_result_spec_timestamp ("wallet_timestamp",
                                     &deposit2.timestamp),
    GNUNET_PQ_result_spec_timestamp ("exchange_timestamp",
                                     exchange_timestamp),
    GNUNET_PQ_result_spec_timestamp ("refund_deadline",
                                     &deposit2.refund_deadline),
    GNUNET_PQ_result_spec_timestamp ("wire_deadline",
                                     &deposit2.wire_deadline),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                 deposit_fee),
    GNUNET_PQ_result_spec_auto_from_type ("wire_salt",
                                          &deposit2.wire_salt),
    GNUNET_PQ_result_spec_string ("receiver_wire_account",
                                  &deposit2.receiver_wire_account),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_MerchantWireHashP h_wire2;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting deposits for coin %s\n",
              TALER_B2S (coin_pub));
  PREPARE (pg,
           "get_deposit",
           "SELECT"
           " dep.amount_with_fee"
           ",denominations.fee_deposit"
           ",dep.wallet_timestamp"
           ",dep.exchange_timestamp"
           ",dep.refund_deadline"
           ",dep.wire_deadline"
           ",dep.h_contract_terms"
           ",dep.wire_salt"
           ",wt.payto_uri AS receiver_wire_account"
           " FROM deposits dep"
           " JOIN known_coins kc ON (kc.coin_pub = dep.coin_pub)"
           " JOIN denominations USING (denominations_serial)"
           " JOIN wire_targets wt USING (wire_target_h_payto)"
           " WHERE dep.coin_pub=$1"
           "   AND dep.merchant_pub=$3"
           "   AND dep.h_contract_terms=$2;");

  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "get_deposit",
                                                 params,
                                                 rs);
  if (0 >= qs)
    return qs;
  TALER_merchant_wire_signature_hash (deposit2.receiver_wire_account,
                                      &deposit2.wire_salt,
                                      &h_wire2);
  GNUNET_free (deposit2.receiver_wire_account);
  /* Now we check that the other information in @a deposit
     also matches, and if not report inconsistencies. */
  if ( (GNUNET_TIME_timestamp_cmp (refund_deadline,
                                   !=,
                                   deposit2.refund_deadline)) ||
       (0 != GNUNET_memcmp (h_wire,
                            &h_wire2) ) )
  {
    /* Inconsistencies detected! Does not match! */
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}
