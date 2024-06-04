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
 * @file exchangedb/pg_lookup_wire_fee_by_time.c
 * @brief Implementation of the lookup_wire_fee_by_time function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_wire_fee_by_time.h"
#include "pg_helper.h"


/**
 * Closure for #wire_fee_by_time_helper()
 */
struct WireFeeLookupContext
{

  /**
   * Set to the wire fees. Set to invalid if fees conflict over
   * the given time period.
   */
  struct TALER_WireFeeSet *fees;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;
};


/**
 * Helper function for #TEH_PG_lookup_wire_fee_by_time().
 * Calls the callback with the wire fee structure.
 *
 * @param cls a `struct WireFeeLookupContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
wire_fee_by_time_helper (void *cls,
                         PGresult *result,
                         unsigned int num_results)
{
  struct WireFeeLookupContext *wlc = cls;
  struct PostgresClosure *pg = wlc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_WireFeeSet fs;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("wire_fee",
                                   &fs.wire),
      TALER_PQ_RESULT_SPEC_AMOUNT ("closing_fee",
                                   &fs.closing),
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
              sizeof (struct TALER_WireFeeSet));
      return;
    }
    if (0 == i)
    {
      *wlc->fees = fs;
      continue;
    }
    if (0 !=
        TALER_wire_fee_set_cmp (&fs,
                                wlc->fees))
    {
      /* invalidate */
      memset (wlc->fees,
              0,
              sizeof (struct TALER_WireFeeSet));
      return;
    }
  }
}


/**
 * Lookup information about known wire fees.  Finds all applicable
 * fees in the given range. If they are identical, returns the
 * respective @a fees. If any of the fees
 * differ between @a start_time and @a end_time, the transaction
 * succeeds BUT returns an invalid amount for both fees.
 *
 * @param cls closure
 * @param wire_method the wire method to lookup fees for
 * @param start_time starting time of fee
 * @param end_time end time of fee
 * @param[out] fees wire fees for that time period; if
 *             different fees exists within this time
 *             period, an 'invalid' amount is returned.
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_lookup_wire_fee_by_time (
  void *cls,
  const char *wire_method,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  struct TALER_WireFeeSet *fees)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (wire_method),
    GNUNET_PQ_query_param_timestamp (&start_time),
    GNUNET_PQ_query_param_timestamp (&end_time),
    GNUNET_PQ_query_param_end
  };
  struct WireFeeLookupContext wlc = {
    .fees = fees,
    .pg = pg
  };

  PREPARE (pg,
           "lookup_wire_fee_by_time",
           "SELECT"
           " wire_fee"
           ",closing_fee"
           " FROM wire_fee"
           " WHERE wire_method=$1"
           " AND end_date > $2"
           " AND start_date < $3;");
  return GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               "lookup_wire_fee_by_time",
                                               params,
                                               &wire_fee_by_time_helper,
                                               &wlc);
}
