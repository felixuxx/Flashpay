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
 * @file exchangedb/pg_iterate_denomination_info.c
 * @brief Implementation of the iterate_denomination_info function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_iterate_denomination_info.h"
#include "pg_helper.h"


/**
 * Closure for #domination_cb_helper()
 */
struct DenomIteratorContext
{
  /**
   * Function to call with the results.
   */
  TALER_EXCHANGEDB_DenominationCallback cb;

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
 * Helper function for #postgres_iterate_denomination_info().
 * Calls the callback with each denomination key.
 *
 * @param cls a `struct DenomIteratorContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
domination_cb_helper (void *cls,
                      PGresult *result,
                      unsigned int num_results)
{
  struct DenomIteratorContext *dic = cls;
  struct PostgresClosure *pg = dic->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_DenominationKeyInformation issue;
    struct TALER_DenominationPublicKey denom_pub;
    struct TALER_DenominationHashP denom_hash;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &issue.signature),
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &denom_hash),
      GNUNET_PQ_result_spec_timestamp ("valid_from",
                                       &issue.start),
      GNUNET_PQ_result_spec_timestamp ("expire_withdraw",
                                       &issue.expire_withdraw),
      GNUNET_PQ_result_spec_timestamp ("expire_deposit",
                                       &issue.expire_deposit),
      GNUNET_PQ_result_spec_timestamp ("expire_legal",
                                       &issue.expire_legal),
      TALER_PQ_RESULT_SPEC_AMOUNT ("coin",
                                   &issue.value),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_withdraw",
                                   &issue.fees.withdraw),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                   &issue.fees.deposit),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refresh",
                                   &issue.fees.refresh),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refund",
                                   &issue.fees.refund),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_uint32 ("age_mask",
                                    &issue.age_mask.bits),
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

    /* Unfortunately we have to carry the age mask in both, the
     * TALER_DenominationPublicKey and
     * TALER_EXCHANGEDB_DenominationKeyInformation at different times.
     * Here we use _both_ so let's make sure the values are the same. */
    denom_pub.age_mask = issue.age_mask;
    TALER_denom_pub_hash (&denom_pub,
                          &issue.denom_hash);
    if (0 !=
        GNUNET_memcmp (&issue.denom_hash,
                       &denom_hash))
    {
      GNUNET_break (0);
    }
    else
    {
      dic->cb (dic->cb_cls,
               &denom_pub,
               &issue);
    }
    TALER_denom_pub_free (&denom_pub);
  }
}










/**
 * Fetch information about all known denomination keys.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param cb function to call on each denomination key
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_iterate_denomination_info (void *cls,
                                    TALER_EXCHANGEDB_DenominationCallback cb,
                                    void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct DenomIteratorContext dic = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };

   /* Used in #postgres_iterate_denomination_info() */
  PREPARE (pg,
           "denomination_iterate",
           "SELECT"
           " master_sig"
           ",denom_pub_hash"
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
           ",denom_pub"
           ",age_mask"
           " FROM denominations;");
  return GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               "denomination_iterate",
                                               params,
                                               &domination_cb_helper,
                                               &dic);
}
