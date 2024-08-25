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
 * @file pg_select_historic_denom_revenue.h
 * @brief implementation of the select_historic_denom_revenue function
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_HISTORIC_DENOM_REVENUE_H
#define PG_SELECT_HISTORIC_DENOM_REVENUE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Obtain all of the historic denomination key revenue
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param limit return at most this number of results, negative to descend from @a offset
 * @param offset row from which to return @a limit results
 * @param cb function to call with the results
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_select_historic_denom_revenue (
  void *cls,
  int64_t limit,
  uint64_t offset,
  TALER_AUDITORDB_HistoricDenominationRevenueDataCallback cb,
  void *cb_cls);

#endif
