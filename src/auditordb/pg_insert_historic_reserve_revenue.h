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
 * @file pg_insert_historic_reserve_revenue.h
 * @brief implementation of the insert_historic_reserve_revenue function
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_HISTORIC_RESERVE_REVENUE_H
#define PG_INSERT_HISTORIC_RESERVE_REVENUE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Insert information about an exchange's historic revenue from reserves.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param start_time beginning of aggregated time interval
 * @param end_time end of aggregated time interval
 * @param reserve_profits total profits made
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_insert_historic_reserve_revenue (
  void *cls,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  const struct TALER_Amount *reserve_profits);

#endif
