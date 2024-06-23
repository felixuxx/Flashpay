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
 * @file pg_insert_historic_denom_revenue.h
 * @brief implementation of the insert_historic_denom_revenue function
 * @author Christian Grothoff
 */
/*
#ifndef PG_INSERT_HISTORIC_DENOM_REVENUE_H
#define PG_INSERT_HISTORIC_DENOM_REVENUE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"

*/
/**
 * Insert information about an exchange's historic
 * revenue about a denomination key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param denom_pub_hash hash of the denomination key
 * @param revenue_timestamp when did this profit get realized
 * @param revenue_balance what was the total profit made from
 *                        deposit fees, melting fees, refresh fees
 *                        and coins that were never returned?
 * @param loss_balance total losses suffered by the exchange at the time
 * @return transaction status code
 */
/*
enum GNUNET_DB_QueryStatus
TAH_PG_insert_historic_denom_revenue (
  void *cls,
  const struct TALER_DenominationHashP *denom_pub_hash,
  struct GNUNET_TIME_Timestamp revenue_timestamp,
  const struct TALER_Amount *revenue_balance,
  const struct TALER_Amount *loss_balance);

#endif
*/