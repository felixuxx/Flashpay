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
 * @file exchangedb/pg_get_coin_denomination.h
 * @brief implementation of the get_coin_denomination function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_COIN_DENOMINATION_H
#define PG_GET_COIN_DENOMINATION_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Retrieve the denomination of a known coin.
 *
 * @param cls the plugin closure
 * @param coin_pub the public key of the coin to search for
 * @param[out] known_coin_id set to the ID of the coin in the known_coins table
 * @param[out] denom_hash where to store the hash of the coins denomination
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_coin_denomination (
  void *cls,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  uint64_t *known_coin_id,
  struct TALER_DenominationHashP *denom_hash);

#endif
