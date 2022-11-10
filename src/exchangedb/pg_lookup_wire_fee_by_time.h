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
 * @file exchangedb/pg_lookup_wire_fee_by_time.h
 * @brief implementation of the lookup_wire_fee_by_time function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_LOOKUP_WIRE_FEE_BY_TIME_H
#define PG_LOOKUP_WIRE_FEE_BY_TIME_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


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
  struct TALER_WireFeeSet *fees);

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
  struct TALER_WireFeeSet *fees);
#endif
