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
 * @file exchangedb/pg_select_recoup_refresh_above_serial_id.c
 * @brief Implementation of the select_recoup_refresh_above_serial_id function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_recoup_refresh_above_serial_id.h"
#include "pg_helper.h"


/**
 * Closure for #recoup_refresh_serial_helper_cb().
 */
struct RecoupRefreshSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_RecoupRefreshCallback cb;

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
 * @param cls closure of type `struct RecoupRefreshSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
recoup_refresh_serial_helper_cb (void *cls,
                                 PGresult *result,
                                 unsigned int num_results)
{
  struct RecoupRefreshSerialContext *psc = cls;
  struct PostgresClosure *pg = psc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t rowid;
    struct TALER_CoinSpendPublicKeyP old_coin_pub;
    struct TALER_CoinPublicInfo coin;
    struct TALER_CoinSpendSignatureP coin_sig;
    union TALER_DenominationBlindingKeyP coin_blind;
    struct TALER_DenominationPublicKey denom_pub;
    struct TALER_DenominationHashP old_denom_pub_hash;
    struct TALER_Amount amount;
    struct TALER_BlindedCoinHashP h_blind_ev;
    struct GNUNET_TIME_Timestamp timestamp;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("recoup_refresh_uuid",
                                    &rowid),
      GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
                                       &timestamp),
      GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                            &old_coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("old_denom_pub_hash",
                                            &old_denom_pub_hash),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin.coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                            &coin_sig),
      GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                            &coin_blind),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
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
    enum GNUNET_GenericReturnValue ret;

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
                   &old_coin_pub,
                   &old_denom_pub_hash,
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
TEH_PG_select_recoup_refresh_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_RecoupRefreshCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct RecoupRefreshSerialContext psc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

      /* Used in #postgres_select_recoup_refresh_above_serial_id() to obtain
       recoup-refresh transactions */
  PREPARE (pg,
           "recoup_refresh_get_incr",
           "SELECT"
           " recoup_refresh_uuid"
           ",recoup_timestamp"
           ",old_coins.coin_pub AS old_coin_pub"
           ",new_coins.age_commitment_hash"
           ",old_denoms.denom_pub_hash AS old_denom_pub_hash"
           ",new_coins.coin_pub As coin_pub"
           ",coin_sig"
           ",coin_blind"
           ",new_denoms.denom_pub AS denom_pub"
           ",rrc.h_coin_ev AS h_blind_ev"
           ",new_denoms.denom_pub_hash"
           ",new_coins.denom_sig AS denom_sig"
           ",amount_val"
           ",amount_frac"
           " FROM recoup_refresh"
           "    INNER JOIN refresh_revealed_coins rrc"
           "      USING (rrc_serial)"
           "    INNER JOIN refresh_commitments rfc"
           "      ON (rrc.melt_serial_id = rfc.melt_serial_id)"
           "    INNER JOIN known_coins old_coins"
           "      ON (rfc.old_coin_pub = old_coins.coin_pub)"
           "    INNER JOIN known_coins new_coins"
           "      ON (new_coins.coin_pub = recoup_refresh.coin_pub)"
           "    INNER JOIN denominations new_denoms"
           "      ON (new_coins.denominations_serial = new_denoms.denominations_serial)"
           "    INNER JOIN denominations old_denoms"
           "      ON (old_coins.denominations_serial = old_denoms.denominations_serial)"
           " WHERE recoup_refresh_uuid>=$1"
           " ORDER BY recoup_refresh_uuid ASC;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "recoup_refresh_get_incr",
                                             params,
                                             &recoup_refresh_serial_helper_cb,
                                             &psc);
  if (GNUNET_OK != psc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
