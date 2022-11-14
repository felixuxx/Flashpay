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
 * @file exchangedb/pg_get_withdraw_info.h
 * @brief implementation of the get_withdraw_info function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_WITHDRAW_INFO_H
#define PG_GET_WITHDRAW_INFO_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Locate the response for a /reserve/withdraw request under the
 * key of the hash of the blinded message.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param bch hash that uniquely identifies the withdraw operation
 * @param collectable corresponding collectable coin (blind signature)
 *                    if a coin is found
 * @return statement execution status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_withdraw_info (
  void *cls,
  const struct TALER_BlindedCoinHashP *bch,
  struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable);

#endif
