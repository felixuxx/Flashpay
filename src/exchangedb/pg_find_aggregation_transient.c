/*
   This file is part of TALER
   Copyright (C) 2022, 2024 Taler Systems SA

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
 * @file exchangedb/pg_find_aggregation_transient.c
 * @brief Implementation of the find_aggregation_transient function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_find_aggregation_transient.h"
#include "pg_helper.h"


/**
 * Closure for #get_refunds_cb().
 */
struct FindAggregationTransientContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_TransientAggregationCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to #GNUNET_SYSERR on error.
   */
  enum GNUNET_GenericReturnValue status;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct SelectRefundContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
get_transients_cb (void *cls,
                   PGresult *result,
                   unsigned int num_results)
{
  struct FindAggregationTransientContext *srctx = cls;
  struct PostgresClosure *pg = srctx->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_Amount amount;
    struct TALER_FullPayto payto_uri;
    struct TALER_WireTransferIdentifierRawP wtid;
    struct TALER_MerchantPublicKeyP merchant_pub;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                            &merchant_pub),
      GNUNET_PQ_result_spec_auto_from_type ("wtid_raw",
                                            &wtid),
      GNUNET_PQ_result_spec_string ("payto_uri",
                                    &payto_uri.full_payto),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &amount),
      GNUNET_PQ_result_spec_end
    };
    bool cont;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      srctx->status = GNUNET_SYSERR;
      return;
    }
    cont = srctx->cb (srctx->cb_cls,
                      payto_uri,
                      &wtid,
                      &merchant_pub,
                      &amount);
    GNUNET_free (payto_uri.full_payto);
    if (! cont)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_find_aggregation_transient (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  TALER_EXCHANGEDB_TransientAggregationCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_end
  };
  struct FindAggregationTransientContext srctx = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };

  PREPARE (pg,
           "find_transient_aggregations",
           "SELECT"
           "  atr.amount"
           " ,atr.wtid_raw"
           " ,atr.merchant_pub"
           " ,wt.payto_uri"
           " FROM wire_targets wt"
           " JOIN aggregation_transient atr"
           "   USING (wire_target_h_payto)"
           " WHERE wt.h_normalized_payto=$1;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "find_transient_aggregations",
                                             params,
                                             &get_transients_cb,
                                             &srctx);
  if (GNUNET_SYSERR == srctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
