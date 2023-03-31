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
 * @file exchangedb/pg_lookup_global_fee_by_time.h
 * @brief implementation of the lookup_global_fee_by_time function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_LOOKUP_GLOBAL_FEE_BY_TIME_H
#define PG_LOOKUP_GLOBAL_FEE_BY_TIME_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Lookup information about known global fees.
 *
 * @param cls closure
 * @param start_time starting time of fee
 * @param end_time end time of fee
 * @param[out] fees set to wire fees for that time period; if
 *             different global fee exists within this time
 *             period, an 'invalid' amount is returned.
 * @param[out] purse_timeout set to when unmerged purses expire
 * @param[out] history_expiration set to when we expire reserve histories
 * @param[out] purse_account_limit set to number of free purses
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_lookup_global_fee_by_time (
  void *cls,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  struct TALER_GlobalFeeSet *fees,
  struct GNUNET_TIME_Relative *purse_timeout,
  struct GNUNET_TIME_Relative *history_expiration,
  uint32_t *purse_account_limit);

#endif
