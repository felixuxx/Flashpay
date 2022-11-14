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
 * @file exchangedb/pg_select_refreshes_above_serial_id.c
 * @brief Implementation of the select_refreshes_above_serial_id function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_refreshes_above_serial_id.h"
#include "pg_helper.h"


/**
 * Closure for #refreshs_serial_helper_cb().
 */
struct RefreshsSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_RefreshesCallback cb;

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
 * @param cls closure of type `struct RefreshsSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
refreshs_serial_helper_cb (void *cls,
                           PGresult *result,
                           unsigned int num_results)
{
  struct RefreshsSerialContext *rsc = cls;
  struct PostgresClosure *pg = rsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_DenominationPublicKey denom_pub;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_CoinSpendSignatureP coin_sig;
    struct TALER_AgeCommitmentHash h_age_commitment;
    bool ac_isnull;
    struct TALER_Amount amount_with_fee;
    uint32_t noreveal_index;
    uint64_t rowid;
    struct TALER_RefreshCommitmentP rc;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                              &h_age_commitment),
        &ac_isnull),
      GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                            &coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("old_coin_sig",
                                            &coin_sig),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount_with_fee),
      GNUNET_PQ_result_spec_uint32 ("noreveal_index",
                                    &noreveal_index),
      GNUNET_PQ_result_spec_uint64 ("melt_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("rc",
                                            &rc),
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

    ret = rsc->cb (rsc->cb_cls,
                   rowid,
                   &denom_pub,
                   ac_isnull ? NULL : &h_age_commitment,
                   &coin_pub,
                   &coin_sig,
                   &amount_with_fee,
                   noreveal_index,
                   &rc);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}






enum GNUNET_DB_QueryStatus
TEH_PG_select_refreshes_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_RefreshesCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct RefreshsSerialContext rsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;
    /* Used in #postgres_select_refreshes_above_serial_id() to fetch
       refresh session with id '\geq' the given parameter */
  PREPARE (pg,
           "audit_get_refresh_commitments_incr",
           "SELECT"
           " denom.denom_pub"
           ",kc.coin_pub AS old_coin_pub"
           ",kc.age_commitment_hash"
           ",old_coin_sig"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",noreveal_index"
           ",melt_serial_id"
           ",rc"
           " FROM refresh_commitments"
           "   JOIN known_coins kc"
           "     ON (refresh_commitments.old_coin_pub = kc.coin_pub)"
           "   JOIN denominations denom"
           "     ON (kc.denominations_serial = denom.denominations_serial)"
           " WHERE melt_serial_id>=$1"
           " ORDER BY melt_serial_id ASC;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_refresh_commitments_incr",
                                             params,
                                             &refreshs_serial_helper_cb,
                                             &rsc);
  if (GNUNET_OK != rsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
