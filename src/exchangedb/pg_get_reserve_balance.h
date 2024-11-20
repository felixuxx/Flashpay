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
 * @file exchangedb/pg_get_reserve_balance.h
 * @brief implementation of the get_reserve_balance function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_RESERVE_BALANCE_H
#define PG_GET_RESERVE_BALANCE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Get the balance of the specified reserve.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param reserve_pub public key of the reserve
 * @param[out] balance set to the reserve balance
 * @param[out] origin_account set to URI of the origin account, NULL
 *     if we have no origin account (reserve created by P2P merge)
* @return transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_reserve_balance (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct TALER_Amount *balance,
  struct TALER_FullPayto *origin_account);

#endif
