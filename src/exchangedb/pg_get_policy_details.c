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
 * @file exchangedb/pg_get_policy_details.c
 * @brief Implementation of the get_policy_details function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_policy_details.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_get_policy_details (
  void *cls,
  const struct GNUNET_HashCode *hc,
  struct TALER_PolicyDetails *details)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (hc),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("deadline",
                                     &details->deadline),
    TALER_PQ_RESULT_SPEC_AMOUNT ("commitment",
                                 &details->commitment),
    TALER_PQ_RESULT_SPEC_AMOUNT ("accumulated_total",
                                 &details->accumulated_total),
    TALER_PQ_RESULT_SPEC_AMOUNT ("policy_fee",
                                 &details->policy_fee),
    TALER_PQ_RESULT_SPEC_AMOUNT ("transferable_amount",
                                 &details->transferable_amount),
    GNUNET_PQ_result_spec_auto_from_type ("state",
                                          &details->fulfillment_state),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_uint64 ("policy_fulfillment_id",
                                    &details->policy_fulfillment_id),
      &details->no_policy_fulfillment_id),
    GNUNET_PQ_result_spec_end
  };


  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_policy_details",
                                                   params,
                                                   rs);
}
