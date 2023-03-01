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
 * @file exchangedb/pg_get_age_withdraw_info.h
 * @brief implementation of the get_age_withdraw_info function for Postgres
 * @author Özgür KESIM
 */
#ifndef PG_GET_AGE_WITHDRAW_INFO_H
#define PG_GET_AGE_WITHDRAW_INFO_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
   * Locate the response for a age-withdraw request under a hash that uniquely
   * identifies the age-withdraw operation.  Used to ensure idempotency of the
   * request.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param reserve_pub public key of the reserve for which the age-withdraw request is made
   * @param ach hash that uniquely identifies the age-withdraw operation
   * @param[out] awc corresponding details of the previous age-withdraw request if an entry was found
   * @return statement execution status
   */
enum GNUNET_DB_QueryStatus
TEH_PG_get_age_withdraw_info (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_AgeWithdrawCommitmentHashP *ach,
  struct TALER_EXCHANGEDB_AgeWithdrawCommitment *awc);
#endif
