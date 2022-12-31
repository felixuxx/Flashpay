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
 * @file exchangedb/pg_select_deposits_above_serial_id.c
 * @brief Implementation of the select_deposits_above_serial_id function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_deposits_above_serial_id.h"
#include "pg_helper.h"

/**
 * Closure for #deposit_serial_helper_cb().
 */
struct DepositSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_DepositCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  enum GNUNET_GenericReturnValue status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct DepositSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
deposit_serial_helper_cb (void *cls,
                          PGresult *result,
                          unsigned int num_results)
{
  struct DepositSerialContext *dsc = cls;
  struct PostgresClosure *pg = dsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_Deposit deposit;
    struct GNUNET_TIME_Timestamp exchange_timestamp;
    struct TALER_DenominationPublicKey denom_pub;
    bool done;
    uint64_t rowid;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &deposit.amount_with_fee),
      GNUNET_PQ_result_spec_timestamp ("wallet_timestamp",
                                       &deposit.timestamp),
      GNUNET_PQ_result_spec_timestamp ("exchange_timestamp",
                                       &exchange_timestamp),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                            &deposit.merchant_pub),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &deposit.coin.coin_pub),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                              &deposit.coin.h_age_commitment),
        &deposit.coin.no_age_commitment),
      GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                            &deposit.csig),
      GNUNET_PQ_result_spec_timestamp ("refund_deadline",
                                       &deposit.refund_deadline),
      GNUNET_PQ_result_spec_timestamp ("wire_deadline",
                                       &deposit.wire_deadline),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                            &deposit.h_contract_terms),
      GNUNET_PQ_result_spec_auto_from_type ("wire_salt",
                                            &deposit.wire_salt),
      GNUNET_PQ_result_spec_string ("receiver_wire_account",
                                    &deposit.receiver_wire_account),
      GNUNET_PQ_result_spec_bool ("done",
                                  &done),
      GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_GenericReturnValue ret;

    memset (&deposit,
            0,
            sizeof (deposit));
    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      dsc->status = GNUNET_SYSERR;
      return;
    }
    ret = dsc->cb (dsc->cb_cls,
                   rowid,
                   exchange_timestamp,
                   &deposit,
                   &denom_pub,
                   done);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_deposits_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_DepositCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct DepositSerialContext dsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  /* Fetch deposits with rowid '\geq' the given parameter */
  PREPARE (pg,
           "audit_get_deposits_incr",
           "SELECT"
           " amount_with_fee_val"
           ",amount_with_fee_frac"
           ",wallet_timestamp"
           ",exchange_timestamp"
           ",merchant_pub"
           ",denom.denom_pub"
           ",kc.coin_pub"
           ",kc.age_commitment_hash"
           ",coin_sig"
           ",refund_deadline"
           ",wire_deadline"
           ",h_contract_terms"
           ",wire_salt"
           ",payto_uri AS receiver_wire_account"
           ",done"
           ",deposit_serial_id"
           " FROM deposits"
           "    JOIN wire_targets USING (wire_target_h_payto)"
           "    JOIN known_coins kc USING (coin_pub)"
           "    JOIN denominations denom USING (denominations_serial)"
           " WHERE ("
           "  (deposit_serial_id>=$1)"
           " )"
           " ORDER BY deposit_serial_id ASC;");

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_deposits_incr",
                                             params,
                                             &deposit_serial_helper_cb,
                                             &dsc);
  if (GNUNET_OK != dsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
