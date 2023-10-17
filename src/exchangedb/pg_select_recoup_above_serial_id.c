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
 * @file exchangedb/pg_select_recoup_above_serial_id.c
 * @brief Implementation of the select_recoup_above_serial_id function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_recoup_above_serial_id.h"
#include "pg_helper.h"


/**
 * Closure for #recoup_serial_helper_cb().
 */
struct RecoupSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_RecoupCallback cb;

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
 * @param cls closure of type `struct RecoupSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
recoup_serial_helper_cb (void *cls,
                         PGresult *result,
                         unsigned int num_results)
{
  struct RecoupSerialContext *psc = cls;
  struct PostgresClosure *pg = psc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t rowid;
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_CoinPublicInfo coin;
    struct TALER_CoinSpendSignatureP coin_sig;
    union TALER_DenominationBlindingKeyP coin_blind;
    struct TALER_Amount amount;
    struct TALER_DenominationPublicKey denom_pub;
    struct TALER_BlindedCoinHashP h_blind_ev;
    struct GNUNET_TIME_Timestamp timestamp;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("recoup_uuid",
                                    &rowid),
      GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
                                       &timestamp),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin.coin_pub),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                            &coin_sig),
      GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                            &coin_blind),
      GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                            &h_blind_ev),
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &coin.denom_pub_hash),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                              &coin.h_age_commitment),
        &coin.no_age_commitment),
      TALER_PQ_result_spec_denom_sig ("denom_sig",
                                      &coin.denom_sig),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &amount),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      psc->status = GNUNET_SYSERR;
      return;
    }
    ret = psc->cb (psc->cb_cls,
                   rowid,
                   timestamp,
                   &amount,
                   &reserve_pub,
                   &coin,
                   &denom_pub,
                   &coin_sig,
                   &coin_blind);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_recoup_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_RecoupCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct RecoupSerialContext psc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "recoup_get_incr",
           "SELECT"
           " recoup_uuid"
           ",recoup_timestamp"
           ",reserves.reserve_pub"
           ",coins.coin_pub"
           ",coin_sig"
           ",coin_blind"
           ",ro.h_blind_ev"
           ",denoms.denom_pub_hash"
           ",coins.denom_sig"
           ",coins.age_commitment_hash"
           ",denoms.denom_pub"
           ",amount"
           " FROM recoup"
           "    JOIN known_coins coins"
           "      USING (coin_pub)"
           "    JOIN reserves_out ro"
           "      USING (reserve_out_serial_id)"
           "    JOIN reserves"
           "      USING (reserve_uuid)"
           "    JOIN denominations denoms"
           "      ON (coins.denominations_serial = denoms.denominations_serial)"
           " WHERE recoup_uuid>=$1"
           " ORDER BY recoup_uuid ASC;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "recoup_get_incr",
                                             params,
                                             &recoup_serial_helper_cb,
                                             &psc);
  if (GNUNET_OK != psc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
