/*
   This file is part of TALER
   Copyright (C) 2023 Taler Systems SA

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
 * @file exchangedb/pg_do_age_withdraw.h
 * @brief implementation of the do_age_withdraw function for Postgres
 * @author Özgür Kesim
 */
#ifndef PG_DO_AGE_WITHDRAW_H
#define PG_DO_AGE_WITHDRAW_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Perform reserve update as part of an age-withdraw operation, checking for
 * sufficient balance and fulfillment of age requirements. Finally persisting
 * the withdrawal details.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param commitment the commitment with all parameters
 * @param now current time (rounded)
 * @param[out] found set to true if the reserve was found
 * @param[out] balance_ok set to true if the balance was sufficient
 * @param[out] age_ok set to true if no age requirements are present on the reserve
 * @param[out] required_age if @e age_ok is false, set to the maximum allowed age when withdrawing from this reserve
 * @param[out] conflict set to true if there already is an entry in the database for the given pair (h_commitment, reserve_pub)
 * @param[out] ruuid set to the reserve's UUID (reserves table row)
 * @return query execution status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_do_age_withdraw (
  void *cls,
  const struct TALER_EXCHANGEDB_AgeWithdraw *commitment,
  const struct GNUNET_TIME_Timestamp now,
  bool *found,
  bool *balance_ok,
  bool *age_ok,
  uint16_t *required_age,
  bool *conflict,
  uint64_t *ruuid);

#endif
