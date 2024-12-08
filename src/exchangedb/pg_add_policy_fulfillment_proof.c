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
 * @file exchangedb/pg_add_policy_fulfillment_proof.c
 * @brief Implementation of the add_policy_fulfillment_proof function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_add_policy_fulfillment_proof.h"
#include "pg_helper.h"


/**
 * Compares two indices into an array of hash codes according to
 * GNUNET_CRYPTO_hash_cmp of the content at those index positions.
 *
 * Used in a call qsort_t in order to generate sorted policy_hash_codes.
 */
static int
hash_code_cmp (
  const void *hc1,
  const void *hc2,
  void *arg)
{
  size_t i1 = *(size_t *) hc1;
  size_t i2 = *(size_t *) hc2;
  const struct TALER_PolicyDetails *d = arg;

  return GNUNET_CRYPTO_hash_cmp (&d[i1].hash_code,
                                 &d[i2].hash_code);
}


enum GNUNET_DB_QueryStatus
TEH_PG_add_policy_fulfillment_proof (
  void *cls,
  struct TALER_PolicyFulfillmentTransactionData *fulfillment)
{
  enum GNUNET_DB_QueryStatus qs;
  struct PostgresClosure *pg = cls;
  size_t count = fulfillment->details_count;
  /* FIXME[Oec]: this seems to be prone to VLA attacks */
  struct GNUNET_HashCode hcs[GNUNET_NZL (count)];

  /* Create the sorted policy_hash_codes */
  {
    size_t idx[GNUNET_NZL (count)];
    for (size_t i = 0; i < count; i++)
      idx[i] = i;

    /* Sort the indices according to the hash codes of the corresponding
     * details. */
    qsort_r (idx,
             count,
             sizeof(size_t),
             hash_code_cmp,
             fulfillment->details);

    /* Finally, concatenate all hash_codes in sorted order */
    for (size_t i = 0; i < count; i++)
      hcs[i] = fulfillment->details[idx[i]].hash_code;
  }


  /* Now, add the proof to the policy_fulfillments table, retrieve the
   * record_id */
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_timestamp (&fulfillment->timestamp),
      TALER_PQ_query_param_json (fulfillment->proof),
      GNUNET_PQ_query_param_auto_from_type (&fulfillment->h_proof),
      TALER_PQ_query_param_array_hash_code (count, hcs, pg->conn),
      GNUNET_PQ_query_param_end
    };
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("fulfillment_id",
                                    &fulfillment->fulfillment_id),
      GNUNET_PQ_result_spec_end
    };

    PREPARE (pg,
             "insert_proof_into_policy_fulfillments",
             "INSERT INTO policy_fulfillments"
             "(fulfillment_timestamp"
             ",fulfillment_proof"
             ",h_fulfillment_proof"
             ",policy_hash_codes"
             ") VALUES ($1, $2, $3, $4)"
             " ON CONFLICT DO NOTHING;");
    qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "insert_proof_into_policy_fulfillments",
                                                   params,
                                                   rs);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
      return qs;
  }

  /* Now, set the states of each entry corresponding to the hash_codes in
   * policy_details accordingly */
  for (size_t i = 0; i < count; i++)
  {
    struct TALER_PolicyDetails *pos = &fulfillment->details[i];
    {
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_auto_from_type (&pos->hash_code),
        GNUNET_PQ_query_param_timestamp (&pos->deadline),
        TALER_PQ_query_param_amount (pg->conn,
                                     &pos->commitment),
        TALER_PQ_query_param_amount (pg->conn,
                                     &pos->accumulated_total),
        TALER_PQ_query_param_amount (pg->conn,
                                     &pos->policy_fee),
        TALER_PQ_query_param_amount (pg->conn,
                                     &pos->transferable_amount),
        GNUNET_PQ_query_param_auto_from_type (&pos->fulfillment_state),
        GNUNET_PQ_query_param_end
      };

      PREPARE (pg,
               "update_policy_details",
               "UPDATE policy_details SET"
               " deadline=$2"
               ",commitment=$3"
               ",accumulated_total=$4"
               ",fee=$5"
               ",transferable=$6"
               ",fulfillment_state=$7"
               " WHERE policy_hash_code=$1;");
      qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                               "update_policy_details",
                                               params);
      if (qs < 0)
        return qs;
    }
  }

  /*
   * FIXME[oec]-#7999: When all policies of a deposit are fulfilled,
   * unblock it and trigger a wire-transfer.
   */

  return qs;
}
