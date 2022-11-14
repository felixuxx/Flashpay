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
 * @file exchangedb/pg_select_refunds_above_serial_id.c
 * @brief Implementation of the select_refunds_above_serial_id function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_refunds_above_serial_id.h"
#include "pg_helper.h"

/**
 * Closure for #refunds_serial_helper_cb().
 */
struct RefundsSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_RefundCallback cb;

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
 * @param cls closure of type `struct RefundsSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
refunds_serial_helper_cb (void *cls,
                          PGresult *result,
                          unsigned int num_results)
{
  struct RefundsSerialContext *rsc = cls;
  struct PostgresClosure *pg = rsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_Refund refund;
    struct TALER_DenominationPublicKey denom_pub;
    uint64_t rowid;
    bool full_refund;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                            &refund.details.merchant_pub),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_sig",
                                            &refund.details.merchant_sig),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                            &refund.details.h_contract_terms),
      GNUNET_PQ_result_spec_uint64 ("rtransaction_id",
                                    &refund.details.rtransaction_id),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &refund.coin.coin_pub),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &refund.details.refund_amount),
      GNUNET_PQ_result_spec_uint64 ("refund_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_GenericReturnValue ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      rsc->status = GNUNET_SYSERR;
      return;
    }
    {
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_uint64 (&rowid),
        GNUNET_PQ_query_param_end
      };
      struct TALER_Amount amount_with_fee;
      uint64_t s_f;
      uint64_t s_v;
      struct GNUNET_PQ_ResultSpec rs2[] = {
        GNUNET_PQ_result_spec_uint64 ("s_v",
                                      &s_v),
        GNUNET_PQ_result_spec_uint64 ("s_f",
                                      &s_f),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                     &amount_with_fee),
        GNUNET_PQ_result_spec_end
      };
      enum GNUNET_DB_QueryStatus qs;

      qs = GNUNET_PQ_eval_prepared_singleton_select (
        pg->conn,
        "test_refund_full",
        params,
        rs2);
      if (qs <= 0)
      {
        GNUNET_break (0);
        rsc->status = GNUNET_SYSERR;
        return;
      }
      /* normalize */
      s_v += s_f / TALER_AMOUNT_FRAC_BASE;
      s_f %= TALER_AMOUNT_FRAC_BASE;
      full_refund = (s_v >= amount_with_fee.value) &&
                    (s_f >= amount_with_fee.fraction);
    }
    ret = rsc->cb (rsc->cb_cls,
                   rowid,
                   &denom_pub,
                   &refund.coin.coin_pub,
                   &refund.details.merchant_pub,
                   &refund.details.merchant_sig,
                   &refund.details.h_contract_terms,
                   refund.details.rtransaction_id,
                   full_refund,
                   &refund.details.refund_amount);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_refunds_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_RefundCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct RefundsSerialContext rsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

      /* Fetch refunds with rowid '\geq' the given parameter */
  PREPARE (pg,
           "audit_get_refunds_incr",
           "SELECT"
           " dep.merchant_pub"
           ",ref.merchant_sig"
           ",dep.h_contract_terms"
           ",ref.rtransaction_id"
           ",denom.denom_pub"
           ",kc.coin_pub"
           ",ref.amount_with_fee_val"
           ",ref.amount_with_fee_frac"
           ",ref.refund_serial_id"
           " FROM refunds ref"
           "   JOIN deposits dep"
           "     ON (ref.coin_pub=dep.coin_pub AND ref.deposit_serial_id=dep.deposit_serial_id)"
           "   JOIN known_coins kc"
           "     ON (dep.coin_pub=kc.coin_pub)"
           "   JOIN denominations denom"
           "     ON (kc.denominations_serial=denom.denominations_serial)"
           " WHERE ref.refund_serial_id>=$1"
           " ORDER BY ref.refund_serial_id ASC;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_refunds_incr",
                                             params,
                                             &refunds_serial_helper_cb,
                                             &rsc);
  if (GNUNET_OK != rsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
