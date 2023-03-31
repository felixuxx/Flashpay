/*
   This file is part of TALER
   Copyright (C) 2022, 2023 Taler Systems SA

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
 * @file exchangedb/pg_batch_ensure_coin_known.h
 * @brief implementation of the batch_ensure_coin_known function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_BATCH_ENSURE_COIN_KNOWN_H
#define PG_BATCH_ENSURE_COIN_KNOWN_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Make sure the array of given @a coin is known to the database.
 *
 * @param cls database connection plugin state
 * @param coin array of coins that must be made known
 * @param[out] result array where to store information about each coin
 * @param coin_length length of the @a coin and @a result arraysf
 * @param batch_size desired (maximum) batch size
 * @return database transaction status, non-negative on success
 */
enum GNUNET_DB_QueryStatus
TEH_PG_batch_ensure_coin_known (
  void *cls,
  const struct TALER_CoinPublicInfo *coin,
  struct TALER_EXCHANGEDB_CoinInfo *result,
  unsigned int coin_length,
  unsigned int batch_size);

#endif
