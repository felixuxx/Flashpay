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
 * @file exchangedb/pg_iterate_denominations.c
 * @brief Implementation of the iterate_denominations function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_iterate_denominations.h"
#include "pg_helper.h"




/**
 * Closure for #dominations_cb_helper()
 */
struct DenomsIteratorContext
{
  /**
   * Function to call with the results.
   */
  TALER_EXCHANGEDB_DenominationsCallback cb;

  /**
   * Closure to pass to @e cb
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;
};


/**
 * Helper function for #postgres_iterate_denominations().
 * Calls the callback with each denomination key.
 *
 * @param cls a `struct DenomsIteratorContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
dominations_cb_helper (void *cls,
                       PGresult *result,
                       unsigned int num_results)
{
  struct DenomsIteratorContext *dic = cls;
  struct PostgresClosure *pg = dic->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_DenominationKeyMetaData meta = {0};
    struct TALER_DenominationPublicKey denom_pub = {0};
    struct TALER_MasterSignatureP master_sig = {0};
    struct TALER_DenominationHashP h_denom_pub = {0};
    bool revoked;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &master_sig),
      GNUNET_PQ_result_spec_bool ("revoked",
                                  &revoked),
      GNUNET_PQ_result_spec_timestamp ("valid_from",
                                       &meta.start),
      GNUNET_PQ_result_spec_timestamp ("expire_withdraw",
                                       &meta.expire_withdraw),
      GNUNET_PQ_result_spec_timestamp ("expire_deposit",
                                       &meta.expire_deposit),
      GNUNET_PQ_result_spec_timestamp ("expire_legal",
                                       &meta.expire_legal),
      TALER_PQ_RESULT_SPEC_AMOUNT ("coin",
                                   &meta.value),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_withdraw",
                                   &meta.fees.withdraw),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                   &meta.fees.deposit),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refresh",
                                   &meta.fees.refresh),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refund",
                                   &meta.fees.refund),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_uint32 ("age_mask",
                                    &meta.age_mask.bits),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      return;
    }

    /* make sure the mask information is the same */
    denom_pub.age_mask = meta.age_mask;

    TALER_denom_pub_hash (&denom_pub,
                          &h_denom_pub);
    dic->cb (dic->cb_cls,
             &denom_pub,
             &h_denom_pub,
             &meta,
             &master_sig,
             revoked);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_iterate_denominations (void *cls,
                                TALER_EXCHANGEDB_DenominationsCallback cb,
                                void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct DenomsIteratorContext dic = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };

    /* Used in #postgres_iterate_denominations() */
  PREPARE (pg,
           "select_denominations",
           "SELECT"
           " denominations.master_sig"
           ",denom_revocations_serial_id IS NOT NULL AS revoked"
           ",valid_from"
           ",expire_withdraw"
           ",expire_deposit"
           ",expire_legal"
           ",coin_val"                                                /* value of this denom */
           ",coin_frac"                                                /* fractional value of this denom */
           ",fee_withdraw_val"
           ",fee_withdraw_frac"
           ",fee_deposit_val"
           ",fee_deposit_frac"
           ",fee_refresh_val"
           ",fee_refresh_frac"
           ",fee_refund_val"
           ",fee_refund_frac"
           ",denom_type"
           ",age_mask"
           ",denom_pub"
           " FROM denominations"
           " LEFT JOIN "
           "   denomination_revocations USING (denominations_serial);");


  return GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               "select_denominations",
                                               params,
                                               &dominations_cb_helper,
                                               &dic);
}
