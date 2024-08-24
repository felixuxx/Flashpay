/*
   This file is part of TALER
   Copyright (C) 2022-2024 Taler Systems SA

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
 * @file exchangedb/pg_lookup_transfer_by_deposit.c
 * @brief Implementation of the lookup_transfer_by_deposit function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_transfer_by_deposit.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_lookup_transfer_by_deposit (
  void *cls,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  bool *pending,
  struct TALER_WireTransferIdentifierRawP *wtid,
  struct GNUNET_TIME_Timestamp *exec_time,
  struct TALER_Amount *amount_with_fee,
  struct TALER_Amount *deposit_fee,
  struct TALER_EXCHANGEDB_KycStatus *kyc,
  union TALER_AccountPublicKeyP *account_pub)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_auto_from_type (h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_end
  };
  char *payto_uri;
  struct TALER_WireSaltP wire_salt;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("wtid_raw",
                                          wtid),
    GNUNET_PQ_result_spec_auto_from_type ("wire_salt",
                                          &wire_salt),
    GNUNET_PQ_result_spec_string ("payto_uri",
                                  &payto_uri),
    GNUNET_PQ_result_spec_timestamp ("execution_date",
                                     exec_time),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 amount_with_fee),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                 deposit_fee),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("target_pub",
                                            account_pub),
      NULL),
    GNUNET_PQ_result_spec_end
  };

  memset (kyc,
          0,
          sizeof (*kyc));
  /* check if the aggregation record exists and get it */
  PREPARE (pg,
           "lookup_deposit_wtid",
           "SELECT"
           " atr.wtid_raw"
           ",wire_out.execution_date"
           ",cdep.amount_with_fee"
           ",bdep.wire_salt"
           ",wt.payto_uri"
           ",wt.target_pub"
           ",denom.fee_deposit"
           " FROM coin_deposits cdep"
           "    JOIN batch_deposits bdep"
           "      USING (batch_deposit_serial_id)"
           "    JOIN wire_targets wt"
           "      USING (wire_target_h_payto)"
           "    JOIN aggregation_tracking atr"
           "      ON (cdep.batch_deposit_serial_id = atr.batch_deposit_serial_id)"
           "    JOIN known_coins kc"
           "      ON (kc.coin_pub = cdep.coin_pub)"
           "    JOIN denominations denom"
           "      USING (denominations_serial)"
           "    JOIN wire_out"
           "      USING (wtid_raw)"
           " WHERE cdep.coin_pub=$1"
           "   AND bdep.merchant_pub=$3"
           "   AND bdep.h_contract_terms=$2");
  /* NOTE: above query might be more efficient if we computed the shard
     from the merchant_pub and included that in the query */
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "lookup_deposit_wtid",
                                                 params,
                                                 rs);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    struct TALER_MerchantWireHashP wh;

    TALER_merchant_wire_signature_hash (payto_uri,
                                        &wire_salt,
                                        &wh);
    if (0 ==
        GNUNET_memcmp (&wh,
                       h_wire))
    {
      *pending = false;
      kyc->ok = true;
      GNUNET_PQ_cleanup_result (rs);
      return qs;
    }
    qs = GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
    GNUNET_PQ_cleanup_result (rs);
  }
  if (0 > qs)
    return qs;
  *pending = true;
  memset (wtid,
          0,
          sizeof (*wtid));
  GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "lookup_deposit_wtid returned 0 matching rows\n");
  {
    /* Check if transaction exists in deposits, so that we just
       do not have a WTID yet. In that case, return without wtid
       (by setting 'pending' true). */
    struct GNUNET_PQ_ResultSpec rs2[] = {
      GNUNET_PQ_result_spec_auto_from_type ("wire_salt",
                                            &wire_salt),
      GNUNET_PQ_result_spec_string ("payto_uri",
                                    &payto_uri),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   amount_with_fee),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                   deposit_fee),
      GNUNET_PQ_result_spec_timestamp ("wire_deadline",
                                       exec_time),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_uint64 ("legitimization_requirement_serial_id",
                                      &kyc->requirement_row),
        NULL),
      GNUNET_PQ_result_spec_end
    };

    PREPARE (pg,
             "get_deposit_without_wtid",
             "SELECT"
             " bdep.wire_salt"
             ",wt.payto_uri"
             ",cdep.amount_with_fee"
             ",denom.fee_deposit"
             ",bdep.wire_deadline"
             ",agt.legitimization_requirement_serial_id"
             " FROM coin_deposits cdep"
             " JOIN batch_deposits bdep"
             "   USING (batch_deposit_serial_id)"
             " JOIN wire_targets wt"
             "   USING (wire_target_h_payto)"
             " JOIN known_coins kc"
             "   ON (kc.coin_pub = cdep.coin_pub)"
             " JOIN denominations denom"
             "   USING (denominations_serial)"
             " LEFT JOIN aggregation_transient agt "
             "   ON ( (bdep.wire_target_h_payto = agt.wire_target_h_payto) AND"
             "        (bdep.merchant_pub = agt.merchant_pub) )"
             " WHERE cdep.coin_pub=$1"
             "   AND bdep.merchant_pub=$3"
             "   AND bdep.h_contract_terms=$2"
             " LIMIT 1;");
    /* NOTE: above query might be more efficient if we computed the shard
       from the merchant_pub and included that in the query */
    qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_deposit_without_wtid",
                                                   params,
                                                   rs2);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
    {
      struct TALER_MerchantWireHashP wh;

      TALER_merchant_wire_signature_hash (payto_uri,
                                          &wire_salt,
                                          &wh);
      if (0 !=
          GNUNET_memcmp (&wh,
                         h_wire))
      {
        GNUNET_PQ_cleanup_result (rs2);
        return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
      }
      GNUNET_PQ_cleanup_result (rs2);
      if (0 == kyc->requirement_row)
        kyc->ok = true; /* technically: unknown */
    }
    return qs;
  }
}
