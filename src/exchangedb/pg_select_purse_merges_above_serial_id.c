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
 * @file pg_select_purse_merges_above_serial_id.c
 * @brief Implementation of the select_purse_merges_above_serial_id function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_purse_merges_above_serial_id.h"
#include "pg_helper.h"


/**
 * Closure for #purse_deposit_serial_helper_cb().
 */
struct PurseMergeSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_PurseMergeCallback cb;

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
 * @param cls closure of type `struct PurseMergeSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
purse_merges_serial_helper_cb (void *cls,
                               PGresult *result,
                               unsigned int num_results)
{
  struct PurseMergeSerialContext *dsc = cls;
  struct PostgresClosure *pg = dsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t rowid;
    char *partner_base_url = NULL;
    struct TALER_Amount amount;
    struct TALER_Amount balance;
    uint32_t flags32;
    enum TALER_WalletAccountMergeFlags flags;
    struct TALER_PurseMergePublicKeyP merge_pub;
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_PurseMergeSignatureP merge_sig;
    struct TALER_PurseContractPublicKeyP purse_pub;
    struct GNUNET_TIME_Timestamp merge_timestamp;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount),
      TALER_PQ_RESULT_SPEC_AMOUNT ("balance",
                                   &balance),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("partner_base_url",
                                      &partner_base_url),
        NULL),
      GNUNET_PQ_result_spec_uint32 ("flags",
                                    &flags32),
      GNUNET_PQ_result_spec_timestamp ("merge_timestamp",
                                       &merge_timestamp),
      GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                            &purse_pub),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type ("merge_sig",
                                            &merge_sig),
      GNUNET_PQ_result_spec_auto_from_type ("merge_pub",
                                            &merge_pub),
      GNUNET_PQ_result_spec_uint64 ("purse_merge_request_serial_id",
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
    flags = (enum TALER_WalletAccountMergeFlags) flags32;
    ret = dsc->cb (dsc->cb_cls,
                   rowid,
                   partner_base_url,
                   &amount,
                   &balance,
                   flags,
                   &merge_pub,
                   &reserve_pub,
                   &merge_sig,
                   &purse_pub,
                   merge_timestamp);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_purse_merges_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_PurseMergeCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct PurseMergeSerialContext dsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "audit_get_purse_merge_incr",
           "SELECT"
           " pm.purse_merge_request_serial_id"
           ",partner_base_url"
           ",pr.amount_with_fee"
           ",pr.balance"
           ",pr.flags"
           ",pr.merge_pub"
           ",pm.reserve_pub"
           ",pm.merge_sig"
           ",pm.purse_pub"
           ",pm.merge_timestamp"
           " FROM purse_merges pm"
           " JOIN purse_requests pr USING (purse_pub)"
           " LEFT JOIN partners USING (partner_serial_id)"
           " WHERE ("
           "  (purse_merge_request_serial_id>=$1)"
           " )"
           " ORDER BY purse_merge_request_serial_id ASC;");

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_purse_merge_incr",
                                             params,
                                             &purse_merges_serial_helper_cb,
                                             &dsc);
  if (GNUNET_OK != dsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
