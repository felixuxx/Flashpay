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
 * @file exchangedb/pg_do_reserve_purse.c
 * @brief Implementation of the do_reserve_purse function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_do_reserve_purse.h"
#include "pg_helper.h"
/**
 * Function called insert request to merge a purse into a reserve by the
 * respective purse merge key. The purse must not have been merged into a
 * different reserve.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub purse to merge
 * @param merge_sig signature affirming the merge
 * @param merge_timestamp time of the merge
 * @param reserve_sig signature of the reserve affirming the merge
 * @param purse_fee amount to charge the reserve for the purse creation, NULL to use the quota
 * @param reserve_pub public key of the reserve to credit
 * @param[out] in_conflict set to true if @a purse_pub was merged into a different reserve already
 * @param[out] no_reserve set to true if @a reserve_pub is not a known reserve
 * @param[out] insufficient_funds set to true if @a reserve_pub has insufficient capacity to create another purse
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_do_reserve_purse (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergeSignatureP *merge_sig,
  const struct GNUNET_TIME_Timestamp merge_timestamp,
  const struct TALER_ReserveSignatureP *reserve_sig,
  const struct TALER_Amount *purse_fee,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  bool *in_conflict,
  bool *no_reserve,
  bool *insufficient_funds)
{
  struct PostgresClosure *pg = cls;
  struct TALER_Amount zero_fee;
  struct TALER_PaytoHashP h_payto;
  struct GNUNET_TIME_Timestamp reserve_expiration
    = GNUNET_TIME_absolute_to_timestamp (
        GNUNET_TIME_absolute_add (GNUNET_TIME_absolute_get (),
                                  pg->idle_reserve_expiration_time));
  struct GNUNET_TIME_Timestamp reserve_gc
    = GNUNET_TIME_absolute_to_timestamp (
        GNUNET_TIME_absolute_add (GNUNET_TIME_absolute_get (),
                                  pg->legal_reserve_expiration_time));

  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_auto_from_type (merge_sig),
    GNUNET_PQ_query_param_timestamp (&merge_timestamp),
    GNUNET_PQ_query_param_timestamp (&reserve_expiration),
    GNUNET_PQ_query_param_timestamp (&reserve_gc),
    GNUNET_PQ_query_param_auto_from_type (reserve_sig),
    GNUNET_PQ_query_param_bool (NULL == purse_fee),
    TALER_PQ_query_param_amount (NULL == purse_fee
                                 ? &zero_fee
                                 : purse_fee),
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (&h_payto),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("insufficient_funds",
                                insufficient_funds),
    GNUNET_PQ_result_spec_bool ("conflict",
                                in_conflict),
    GNUNET_PQ_result_spec_bool ("no_reserve",
                                no_reserve),
    GNUNET_PQ_result_spec_end
  };

  {
    char *payto_uri;

    payto_uri = TALER_reserve_make_payto (pg->exchange_url,
                                          reserve_pub);
    TALER_payto_hash (payto_uri,
                      &h_payto);
    GNUNET_free (payto_uri);
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &zero_fee));
  /* Used in #postgres_do_reserve_purse() */
  PREPARE (pg,
           "call_reserve_purse",
           "SELECT"
           " out_no_funds AS insufficient_funds"
           ",out_no_reserve AS no_reserve"
           ",out_conflict AS conflict"
           " FROM exchange_do_reserve_purse"
           "  ($1, $2, $3, $4, $5, $6, $7, $8, $9);");

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_reserve_purse",
                                                   params,
                                                   rs);
}
