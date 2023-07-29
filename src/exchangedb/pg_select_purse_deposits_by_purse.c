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
 * @file exchangedb/pg_select_purse_deposits_by_purse.c
 * @brief Implementation of the select_purse_deposits_by_purse function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_purse_deposits_by_purse.h"
#include "pg_helper.h"

/**
 * Closure for #purse_refund_coin_helper_cb().
 */
struct PurseRefundCoinContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_PurseRefundCoinCallback cb;

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
 * @param cls closure of type `struct PurseRefundCoinContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
purse_refund_coin_helper_cb (void *cls,
                             PGresult *result,
                             unsigned int num_results)
{
  struct PurseRefundCoinContext *dsc = cls;
  struct PostgresClosure *pg = dsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_Amount amount_with_fee;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_DenominationPublicKey denom_pub;
    uint64_t rowid;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount_with_fee),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin_pub),
      GNUNET_PQ_result_spec_uint64 ("purse_deposit_serial_id",
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
      dsc->status = GNUNET_SYSERR;
      return;
    }
    ret = dsc->cb (dsc->cb_cls,
                   rowid,
                   &amount_with_fee,
                   &coin_pub,
                   &denom_pub);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_purse_deposits_by_purse (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  TALER_EXCHANGEDB_PurseRefundCoinCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_end
  };
  struct PurseRefundCoinContext dsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "audit_get_purse_deposits_by_purse",
           "SELECT"
           " pd.purse_deposit_serial_id"
           ",pd.amount_with_fee"
           ",pd.coin_pub"
           ",denom.denom_pub"
           " FROM purse_deposits pd"
           " JOIN known_coins kc USING (coin_pub)"
           " JOIN denominations denom USING (denominations_serial)"
           " WHERE purse_pub=$1;");

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_purse_deposits_by_purse",
                                             params,
                                             &purse_refund_coin_helper_cb,
                                             &dsc);
  if (GNUNET_OK != dsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
