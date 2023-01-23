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
 * @file exchangedb/pg_select_refunds_by_coin.c
 * @brief Implementation of the select_refunds_by_coin function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_refunds_by_coin.h"
#include "pg_helper.h"


/**
 * Closure for #get_refunds_cb().
 */
struct SelectRefundContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_RefundCoinCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to #GNUNET_SYSERR on error.
   */
  int status;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct SelectRefundContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
get_refunds_cb (void *cls,
                PGresult *result,
                unsigned int num_results)
{
  struct SelectRefundContext *srctx = cls;
  struct PostgresClosure *pg = srctx->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_Amount amount_with_fee;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount_with_fee),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      srctx->status = GNUNET_SYSERR;
      return;
    }
    if (GNUNET_OK !=
        srctx->cb (srctx->cb_cls,
                   &amount_with_fee))
      return;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_refunds_by_coin (
  void *cls,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_PrivateContractHashP *h_contract,
  TALER_EXCHANGEDB_RefundCoinCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (h_contract),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_QueryParam params5[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };

  struct SelectRefundContext srctx = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  static int percent_refund = -2;
  const char *query;
  struct GNUNET_PQ_QueryParam *xparams = params;

  if (-2 == percent_refund)
  {
    const char *mode = getenv ("NEW_LOGIC");
    char dummy;

    if ( (NULL==mode) ||
         (1 != sscanf (mode,
                       "%d%c",
                       &percent_refund,
                       &dummy)) )
      {
        if (NULL != mode)
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "Bad mode `%s' specified\n",
                      mode);
      }
      if (NULL==mode)
        percent_refund=0;
  }

  switch (percent_refund)
  {
  case 0:
    query = "get_refunds_by_coin_and_contract-v0";
    PREPARE (pg,
             query,
             "SELECT"
             " ref.amount_with_fee_val"
             ",ref.amount_with_fee_frac"
             " FROM refunds ref"
             " JOIN deposits dep"
             "   USING (coin_pub,deposit_serial_id)"
             " WHERE ref.coin_pub=$1"
             "   AND dep.merchant_pub=$2"
             "   AND dep.h_contract_terms=$3;");
    break;
  case 1:
    query = "get_refunds_by_coin_and_contract-v1";
    PREPARE (pg,
             query,
             "SELECT"
             " ref.amount_with_fee_val"
             ",ref.amount_with_fee_frac"
             " FROM refunds ref"
             " LEFT JOIN deposits dep"
             "   ON dep.coin_pub = ref.coin_pub"
             "   AND ref.deposit_serial_id = dep.deposit_serial_id"
             " WHERE ref.coin_pub=$1"
             "   AND dep.merchant_pub=$2"
             "   AND dep.h_contract_terms=$3;");
    break;
  case 2:
    query = "get_refunds_by_coin_and_contract-v2";
    PREPARE (pg,
             query,
             "WITH rc AS MATERIALIZED("
             "SELECT"
             " amount_with_fee_val"
             ",amount_with_fee_frac"
             ",coin_pub"
             ",deposit_serial_id"
             " FROM refunds ref"
             " WHERE ref.coin_pub=$1)"
             "SELECT"
             "   rc.amount_with_fee_val"
             "  ,rc.amount_with_fee_frac"
             "  FROM deposits dep"
             " JOIN rc"
             " ON rc.deposit_serial_id = dep.deposit_serial_id"
             "  WHERE"
             "      dep.coin_pub = $1"
             "  AND dep.merchant_pub = $2"
             "  AND dep.h_contract_terms = $3");
    break;
  case 3:
    query = "get_refunds_by_coin_and_contract-v3";
    PREPARE (pg,
             query,
             "WITH rc AS MATERIALIZED("
             "SELECT"
             " amount_with_fee_val"
             ",amount_with_fee_frac"
             ",deposit_serial_id"
             " FROM refunds"
             " WHERE coin_pub=$1)"
             "SELECT"
             "   rc.amount_with_fee_val"
             "  ,rc.amount_with_fee_frac"
             "  FROM ("
             "SELECT"
             " amount_with_fee_val"
             ",amount_with_fee_frac"
             " FROM deposits depos"
             "  WHERE"
             "  depos.coin_pub = $1"
             "  AND depos.merchant_pub = $2"
             "  AND depos.h_contract_terms = $3) dep, rc;");
    break;
  case 4:
    query = "get_refunds_by_coin_and_contract-v4";
    PREPARE (pg,
             query,
             "WITH rc AS MATERIALIZED("
             "SELECT"
             " amount_with_fee_val"
             ",amount_with_fee_frac"
             ",coin_pub"
             ",deposit_serial_id"
             " FROM refunds ref"
             " WHERE ref.coin_pub=$1)"
             "SELECT"
             "   rc.amount_with_fee_val"
             "  ,rc.amount_with_fee_frac"
             "  ,deposit_serial_id"
             "  FROM ("
             "SELECT"
             " amount_with_fee_val"
             ",amount_with_fee_frac"
             " FROM deposits depos"
             "  WHERE"
             "  depos.merchant_pub = $2"
             "  AND depos.h_contract_terms = $3) dep JOIN rc "
             "USING(deposit_serial_id, coin_pub);");
    break;
  case 5:
    query = "get_refunds_by_coin_and_contract-v-broken";
    xparams = params5;
    PREPARE (pg,
             query,
             "SELECT"
             " amount_with_fee_val"
             ",amount_with_fee_frac"
             ",coin_pub"
             ",deposit_serial_id"
             " FROM refunds"
             " WHERE coin_pub=$1;");
    break;
  case 8:
    query = "get_refunds_by_coin_and_contract-v8";
    PREPARE (pg,
             query,
             "WITH"
             " rc AS MATERIALIZED("
             "  SELECT"
             "   amount_with_fee_val"
             "  ,amount_with_fee_frac"
             "  ,coin_pub"
             "  ,deposit_serial_id"
             "  FROM refunds"
             "  WHERE coin_pub=$1),"
             " dep AS MATERIALIZED("
             "  SELECT"
             "   deposit_serial_id"
             "  FROM deposits"
             "  WHERE coin_pub = $1"
             "    AND merchant_pub = $2"
             "    AND h_contract_terms = $3"
             ")"
             "SELECT"
             "   rc.amount_with_fee_val"
             "  ,rc.amount_with_fee_frac"
             "  FROM "
             "  rc JOIN dep USING (deposit_serial_id);");
    break;
  case 9:
    query = "get_refunds_by_coin_and_contract-v9-broken";
    PREPARE (pg,
             query,
             "SELECT"
             "   ref.amount_with_fee_val"
             "  ,ref.amount_with_fee_frac"
             " FROM deposits dep"
             " JOIN refunds ref USING(deposit_serial_id)"
             " WHERE dep.coin_pub IN ("
             "   SELECT coin_pub"
             "     FROM refunds"
             "    WHERE coin_pub=$1)"
             "  AND merchant_pub = $2"
             "  AND h_contract_terms = $3;");
    break;
  case 10:
    query = "get_refunds_by_coin_and_contract-v10-broken";
    PREPARE (pg,
             query,
             "SELECT"
             " *"
             " FROM"
             " exchange_do_refund_by_coin"
             " ($1, $2, $3) "
             " AS (amount_with_fee_val INT8, amount_with_fee_frac INT4);");
    break;
  default:
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             query,
                                             xparams,
                                             &get_refunds_cb,
                                             &srctx);
  if (GNUNET_SYSERR == srctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
