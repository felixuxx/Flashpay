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
 * @file exchangedb/pg_lookup_global_fee_by_time.c
 * @brief Implementation of the lookup_global_fee_by_time function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_global_fee_by_time.h"
#include "pg_helper.h"

/**
 * Closure for #global_fee_by_time_helper()
 */
struct GlobalFeeLookupContext
{

  /**
   * Set to the wire fees. Set to invalid if fees conflict over
   * the given time period.
   */
  struct TALER_GlobalFeeSet *fees;

  /**
   * Set to timeout of unmerged purses
   */
  struct GNUNET_TIME_Relative *purse_timeout;

  /**
   * Set to history expiration for reserves.
   */
  struct GNUNET_TIME_Relative *history_expiration;

  /**
   * Set to number of free purses per account.
   */
  uint32_t *purse_account_limit;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;
};


/**
 * Helper function for #postgres_lookup_global_fee_by_time().
 * Calls the callback with each denomination key.
 *
 * @param cls a `struct GlobalFeeLookupContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
global_fee_by_time_helper (void *cls,
                           PGresult *result,
                           unsigned int num_results)
{
  struct GlobalFeeLookupContext *wlc = cls;
  struct PostgresClosure *pg = wlc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_GlobalFeeSet fs;
    struct GNUNET_TIME_Relative purse_timeout;
    struct GNUNET_TIME_Relative history_expiration;
    uint32_t purse_account_limit;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("history_fee",
                                   &fs.history),
      TALER_PQ_RESULT_SPEC_AMOUNT ("account_fee",
                                   &fs.account),
      TALER_PQ_RESULT_SPEC_AMOUNT ("purse_fee",
                                   &fs.purse),
      GNUNET_PQ_result_spec_relative_time ("purse_timeout",
                                           &purse_timeout),
      GNUNET_PQ_result_spec_relative_time ("history_expiration",
                                           &history_expiration),
      GNUNET_PQ_result_spec_uint32 ("purse_account_limit",
                                    &purse_account_limit),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      /* invalidate */
      memset (wlc->fees,
              0,
              sizeof (struct TALER_GlobalFeeSet));
      return;
    }
    if (0 == i)
    {
      *wlc->fees = fs;
      *wlc->purse_timeout = purse_timeout;
      *wlc->history_expiration = history_expiration;
      *wlc->purse_account_limit = purse_account_limit;
      continue;
    }
    if ( (0 !=
          TALER_global_fee_set_cmp (&fs,
                                    wlc->fees)) ||
         (purse_account_limit != *wlc->purse_account_limit) ||
         (GNUNET_TIME_relative_cmp (purse_timeout,
                                    !=,
                                    *wlc->purse_timeout)) ||
         (GNUNET_TIME_relative_cmp (history_expiration,
                                    !=,
                                    *wlc->history_expiration)) )
    {
      /* invalidate */
      memset (wlc->fees,
              0,
              sizeof (struct TALER_GlobalFeeSet));
      return;
    }
  }
}





enum GNUNET_DB_QueryStatus
TEH_PG_lookup_global_fee_by_time (
  void *cls,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  struct TALER_GlobalFeeSet *fees,
  struct GNUNET_TIME_Relative *purse_timeout,
  struct GNUNET_TIME_Relative *history_expiration,
  uint32_t *purse_account_limit)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&start_time),
    GNUNET_PQ_query_param_timestamp (&end_time),
    GNUNET_PQ_query_param_end
  };
  struct GlobalFeeLookupContext wlc = {
    .fees = fees,
    .purse_timeout = purse_timeout,
    .history_expiration = history_expiration,
    .purse_account_limit = purse_account_limit,
    .pg = pg
  };

  PREPARE (pg,
           "lookup_global_fee_by_time",
           "SELECT"
           " history_fee_val"
           ",history_fee_frac"
           ",account_fee_val"
           ",account_fee_frac"
           ",purse_fee_val"
           ",purse_fee_frac"
           ",purse_timeout"
           ",history_expiration"
           ",purse_account_limit"
           " FROM global_fee"
           " WHERE end_date > $1"
           "   AND start_date < $2;");
  return GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               "lookup_global_fee_by_time",
                                               params,
                                               &global_fee_by_time_helper,
                                               &wlc);
}

