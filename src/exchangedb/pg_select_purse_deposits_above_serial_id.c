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
 * @file pg_select_purse_deposits_above_serial_id.c
 * @brief Implementation of the select_purse_deposits_above_serial_id function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_purse_deposits_above_serial_id.h"
#include "pg_helper.h"

/**
 * Closure for #purse_deposit_serial_helper_cb().
 */
struct PurseDepositSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_PurseDepositCallback cb;

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
purse_deposit_serial_helper_cb (void *cls,
                                PGresult *result,
                                unsigned int num_results)
{
  struct PurseDepositSerialContext *dsc = cls;
  struct PostgresClosure *pg = dsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_PurseDeposit deposit = {
      .exchange_base_url = NULL
    };
    struct TALER_DenominationPublicKey denom_pub;
    uint64_t rowid;
    uint32_t flags32;
    struct TALER_ReservePublicKeyP reserve_pub;
    bool not_merged = false;
    struct TALER_Amount purse_balance;
    struct TALER_Amount purse_total;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &deposit.amount),
      TALER_PQ_RESULT_SPEC_AMOUNT ("balance",
                                   &purse_balance),
      TALER_PQ_RESULT_SPEC_AMOUNT ("total",
                                   &purse_total),
      TALER_PQ_RESULT_SPEC_AMOUNT ("deposit_fee",
                                   &deposit.deposit_fee),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("partner_base_url",
                                      &deposit.exchange_base_url),
        NULL),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                              &reserve_pub),
        &not_merged),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                            &deposit.purse_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                            &deposit.coin_sig),
      GNUNET_PQ_result_spec_uint32 ("flags",
                                    &flags32),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &deposit.coin_pub),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                              &deposit.h_age_commitment),
        &deposit.no_age_commitment),
      GNUNET_PQ_result_spec_uint64 ("purse_deposit_serial_id",
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
                   &deposit,
                   not_merged ? NULL : &reserve_pub,
                   (enum TALER_WalletAccountMergeFlags) flags32,
                   &purse_balance,
                   &purse_total,
                   &denom_pub);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_purse_deposits_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_PurseDepositCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct PurseDepositSerialContext dsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "audit_get_purse_deposits_incr",
           "SELECT"
           " pd.amount_with_fee_val"
           ",pd.amount_with_fee_frac"
           ",pr.amount_with_fee_val AS total_val"
           ",pr.amount_with_fee_frac AS total_frac"
           ",pr.balance_val"
           ",pr.balance_frac"
           ",pr.flags"
           ",pd.purse_pub"
           ",pd.coin_sig"
           ",partner_base_url"
           ",denom.denom_pub"
           ",pm.reserve_pub"
           ",kc.coin_pub"
           ",kc.age_commitment_hash"
           ",pd.purse_deposit_serial_id"
           " FROM purse_deposits pd"
           " LEFT JOIN partners USING (partner_serial_id)"
           " LEFT JOIN purse_merges pm USING (purse_pub)"
           " JOIN purse_requests pr USING (purse_pub)"
           " JOIN known_coins kc USING (coin_pub)"
           " JOIN denominations denom USING (denominations_serial)"
           " WHERE ("
           "  (purse_deposit_serial_id>=$1)"
           " )"
           " ORDER BY purse_deposit_serial_id ASC;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_purse_deposits_incr",
                                             params,
                                             &purse_deposit_serial_helper_cb,
                                             &dsc);
  if (GNUNET_OK != dsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
