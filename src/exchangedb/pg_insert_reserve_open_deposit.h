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
 * @file pg_insert_reserve_open_deposit.h
 * @brief implementation of the insert_reserve_open_deposit function
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_RESERVE_OPEN_DEPOSIT_H
#define PG_INSERT_RESERVE_OPEN_DEPOSIT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Insert reserve open coin deposit data into database.
 * Subtracts the @a coin_total from the coin's balance.
 *
 * @param cls closure
 * @param cpi public information about the coin
 * @param coin_sig signature with @e coin_pub of type #TALER_SIGNATURE_WALLET_RESERVE_OPEN_DEPOSIT
 * @param known_coin_id ID of the coin in the known_coins table
 * @param coin_total amount to be spent of the coin (including deposit fee)
 * @param reserve_sig signature by the reserve affirming the open operation
 * @param reserve_pub public key of the reserve being opened
 * @param[out] insufficient_funds set to true if the coin's balance is insufficient, otherwise to false
 * @return transaction status code, 0 if operation is already in the DB
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_reserve_open_deposit (
  void *cls,
  const struct TALER_CoinPublicInfo *cpi,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  uint64_t known_coin_id,
  const struct TALER_Amount *coin_total,
  const struct TALER_ReserveSignatureP *reserve_sig,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  bool *insufficient_funds);

#endif
