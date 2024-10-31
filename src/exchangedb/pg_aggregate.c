/*
   This file is part of TALER
   Copyright (C) 2022, 2023 Taler Systems SA

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
 * @file exchangedb/pg_aggregate.c
 * @brief Implementation of the aggregate function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_compute_shard.h"
#include "pg_event_notify.h"
#include "pg_aggregate.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_aggregate (
  void *cls,
  const struct TALER_FullPaytoHashP *h_payto,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  struct TALER_Amount *total)
{
  struct PostgresClosure *pg = cls;
  uint64_t deposit_shard = TEH_PG_compute_shard (merchant_pub);
  struct GNUNET_TIME_Absolute now = {0};
  uint64_t sum_deposit_value;
  uint64_t sum_deposit_frac;
  uint64_t sum_refund_value;
  uint64_t sum_refund_frac;
  uint64_t sum_fee_value;
  uint64_t sum_fee_frac;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_Amount sum_deposit;
  struct TALER_Amount sum_refund;
  struct TALER_Amount sum_fee;
  struct TALER_Amount delta;

  now = GNUNET_TIME_absolute_round_down (GNUNET_TIME_absolute_get (),
                                         pg->aggregator_shift);
  PREPARE (pg,
           "aggregate",
           "WITH bdep AS (" /* restrict to our merchant and account and mark as done */
           "  UPDATE batch_deposits"
           "     SET done=TRUE"
           "   WHERE NOT (done OR policy_blocked)" /* only actually executable deposits */
           "     AND refund_deadline<$1"
           "     AND shard=$5" /* only for efficiency, merchant_pub is what we really filter by */
           "     AND merchant_pub=$2" /* filter by target merchant */
           "     AND wire_target_h_payto=$3" /* merchant could have a 2nd bank account */
           "   RETURNING"
           "     batch_deposit_serial_id)"
           " ,cdep AS ("
           "   SELECT"
           "     coin_deposit_serial_id"
           "    ,batch_deposit_serial_id"
           "    ,coin_pub"
           "    ,amount_with_fee AS amount"
           "   FROM coin_deposits"
           "   WHERE batch_deposit_serial_id IN (SELECT batch_deposit_serial_id FROM bdep))"
           " ,ref AS (" /* find applicable refunds -- NOTE: may do a full join on the master, maybe find a left-join way to integrate with query above to push it to the shards? */
           "  SELECT"
           "    amount_with_fee AS refund"
           "   ,coin_pub"
           "   ,batch_deposit_serial_id" /* theoretically, coin could be in multiple refunded transactions */
           "    FROM refunds"
           "   WHERE coin_pub IN (SELECT coin_pub FROM cdep)"
           "     AND batch_deposit_serial_id IN (SELECT batch_deposit_serial_id FROM bdep))"
           " ,ref_by_coin AS (" /* total up refunds by coin */
           "  SELECT"
           "    SUM((ref.refund).val) AS sum_refund_val"
           "   ,SUM((ref.refund).frac) AS sum_refund_frac"
           "   ,coin_pub"
           "   ,batch_deposit_serial_id" /* theoretically, coin could be in multiple refunded transactions */
           "    FROM ref"
           "   GROUP BY coin_pub, batch_deposit_serial_id)"
           " ,norm_ref_by_coin AS (" /* normalize */
           "  SELECT"
           "    sum_refund_val + sum_refund_frac / 100000000 AS norm_refund_val"
           "   ,sum_refund_frac % 100000000 AS norm_refund_frac"
           "   ,coin_pub"
           "   ,batch_deposit_serial_id" /* theoretically, coin could be in multiple refunded transactions */
           "    FROM ref_by_coin)"
           " ,fully_refunded_coins AS (" /* find applicable refunds -- NOTE: may do a full join on the master, maybe find a left-join way to integrate with query above to push it to the shards? */
           "  SELECT"
           "    cdep.coin_pub"
           "    FROM norm_ref_by_coin norm"
           "    JOIN cdep"
           "      ON (norm.coin_pub = cdep.coin_pub"
           "      AND norm.batch_deposit_serial_id = cdep.batch_deposit_serial_id"
           "      AND norm.norm_refund_val = (cdep.amount).val"
           "      AND norm.norm_refund_frac = (cdep.amount).frac))"
           " ,fees AS (" /* find deposit fees for not fully refunded deposits */
           "  SELECT"
           "    denom.fee_deposit AS fee"
           "   ,cs.batch_deposit_serial_id" /* ensures we get the fee for each coin, not once per denomination */
           "    FROM cdep cs"
           "    JOIN known_coins kc" /* NOTE: may do a full join on the master, maybe find a left-join way to integrate with query above to push it to the shards? */
           "      USING (coin_pub)"
           "    JOIN denominations denom"
           "      USING (denominations_serial)"
           "    WHERE coin_pub NOT IN (SELECT coin_pub FROM fully_refunded_coins))"
           " ,dummy AS (" /* add deposits to aggregation_tracking */
           "    INSERT INTO aggregation_tracking"
           "    (batch_deposit_serial_id"
           "    ,wtid_raw)"
           "    SELECT batch_deposit_serial_id,$4"
           "      FROM bdep)"
           "SELECT" /* calculate totals (deposits, refunds and fees) */
           "  CAST(COALESCE(SUM((cdep.amount).val),0) AS INT8) AS sum_deposit_value"
           /* cast needed, otherwise we get NUMBER */
           " ,COALESCE(SUM((cdep.amount).frac),0) AS sum_deposit_fraction" /* SUM over INT returns INT8 */
           " ,CAST(COALESCE(SUM((ref.refund).val),0) AS INT8) AS sum_refund_value"
           " ,COALESCE(SUM((ref.refund).frac),0) AS sum_refund_fraction"
           " ,CAST(COALESCE(SUM((fees.fee).val),0) AS INT8) AS sum_fee_value"
           " ,COALESCE(SUM((fees.fee).frac),0) AS sum_fee_fraction"
           " FROM cdep "
           "   FULL OUTER JOIN ref ON (FALSE)"    /* We just want all sums */
           "   FULL OUTER JOIN fees ON (FALSE);");

  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_absolute_time (&now),
      GNUNET_PQ_query_param_auto_from_type (merchant_pub),
      GNUNET_PQ_query_param_auto_from_type (h_payto),
      GNUNET_PQ_query_param_auto_from_type (wtid),
      GNUNET_PQ_query_param_uint64 (&deposit_shard),
      GNUNET_PQ_query_param_end
    };
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("sum_deposit_value",
                                    &sum_deposit_value),
      GNUNET_PQ_result_spec_uint64 ("sum_deposit_fraction",
                                    &sum_deposit_frac),
      GNUNET_PQ_result_spec_uint64 ("sum_refund_value",
                                    &sum_refund_value),
      GNUNET_PQ_result_spec_uint64 ("sum_refund_fraction",
                                    &sum_refund_frac),
      GNUNET_PQ_result_spec_uint64 ("sum_fee_value",
                                    &sum_fee_value),
      GNUNET_PQ_result_spec_uint64 ("sum_fee_fraction",
                                    &sum_fee_frac),
      GNUNET_PQ_result_spec_end
    };

    qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "aggregate",
                                                   params,
                                                   rs);
  }
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (pg->currency,
                                          total));
    return qs;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &sum_deposit));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &sum_refund));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &sum_fee));
  sum_deposit.value    = sum_deposit_frac / TALER_AMOUNT_FRAC_BASE
                         + sum_deposit_value;
  sum_deposit.fraction = sum_deposit_frac % TALER_AMOUNT_FRAC_BASE;
  sum_refund.value     = sum_refund_frac  / TALER_AMOUNT_FRAC_BASE
                         + sum_refund_value;
  sum_refund.fraction  = sum_refund_frac  % TALER_AMOUNT_FRAC_BASE;
  sum_fee.value        = sum_fee_frac     / TALER_AMOUNT_FRAC_BASE
                         + sum_fee_value;
  sum_fee.fraction     = sum_fee_frac     % TALER_AMOUNT_FRAC_BASE; \
  GNUNET_assert (0 <=
                 TALER_amount_subtract (&delta,
                                        &sum_deposit,
                                        &sum_refund));
  GNUNET_assert (0 <=
                 TALER_amount_subtract (total,
                                        &delta,
                                        &sum_fee));
  return qs;
}
