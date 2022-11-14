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
 * @file exchangedb/pg_lookup_wire_tranfer.c
 * @brief Implementation of the lookup_wire_tranfer function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_wire_transfer.h"
#include "pg_helper.h"

/**
 * Closure for #handle_wt_result.
 */
struct WireTransferResultContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_AggregationDataCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to #GNUNET_SYSERR on serious errors.
   */
  int status;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.  Helper function
 * for #postgres_lookup_wire_transfer().
 *
 * @param cls closure of type `struct WireTransferResultContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
handle_wt_result (void *cls,
                  PGresult *result,
                  unsigned int num_results)
{
  struct WireTransferResultContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t rowid;
    struct TALER_PrivateContractHashP h_contract_terms;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_PaytoHashP h_payto;
    struct TALER_MerchantPublicKeyP merchant_pub;
    struct GNUNET_TIME_Timestamp exec_time;
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount deposit_fee;
    struct TALER_DenominationPublicKey denom_pub;
    char *payto_uri;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("aggregation_serial_id", &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                            &h_contract_terms),
      GNUNET_PQ_result_spec_string ("payto_uri",
                                    &payto_uri),
      GNUNET_PQ_result_spec_auto_from_type ("wire_target_h_payto",
                                            &h_payto),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                            &merchant_pub),
      GNUNET_PQ_result_spec_timestamp ("execution_date",
                                       &exec_time),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount_with_fee),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                   &deposit_fee),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->status = GNUNET_SYSERR;
      return;
    }
    ctx->cb (ctx->cb_cls,
             rowid,
             &merchant_pub,
             payto_uri,
             &h_payto,
             exec_time,
             &h_contract_terms,
             &denom_pub,
             &coin_pub,
             &amount_with_fee,
             &deposit_fee);
    GNUNET_PQ_cleanup_result (rs);
  }
}

enum GNUNET_DB_QueryStatus
TEH_PG_lookup_wire_transfer (
  void *cls,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  TALER_EXCHANGEDB_AggregationDataCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_end
  };
  struct WireTransferResultContext ctx;
  enum GNUNET_DB_QueryStatus qs;

  ctx.cb = cb;
  ctx.cb_cls = cb_cls;
  ctx.pg = pg;
  ctx.status = GNUNET_OK;
  /* check if the melt record exists and get it */
    /* Used in #postgres_lookup_wire_transfer */
  PREPARE (pg,
           "lookup_transactions",
           "SELECT"
           " aggregation_serial_id"
           ",deposits.h_contract_terms"
           ",payto_uri"
           ",wire_targets.wire_target_h_payto"
           ",kc.coin_pub"
           ",deposits.merchant_pub"
           ",wire_out.execution_date"
           ",deposits.amount_with_fee_val"
           ",deposits.amount_with_fee_frac"
           ",denom.fee_deposit_val"
           ",denom.fee_deposit_frac"
           ",denom.denom_pub"
           " FROM aggregation_tracking"
           "    JOIN deposits"
           "      USING (deposit_serial_id)"
           "    JOIN wire_targets"
           "      USING (wire_target_h_payto)"
           "    JOIN known_coins kc"
           "      USING (coin_pub)"
           "    JOIN denominations denom"
           "      USING (denominations_serial)"
           "    JOIN wire_out"
           "      USING (wtid_raw)"
           " WHERE wtid_raw=$1;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "lookup_transactions",
                                             params,
                                             &handle_wt_result,
                                             &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
