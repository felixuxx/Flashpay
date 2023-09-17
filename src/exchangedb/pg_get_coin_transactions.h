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
 * @file pg_get_coin_transactions.h
 * @brief implementation of the get_coin_transactions function
 * @author Christian Grothoff
 */
#ifndef PG_GET_COIN_TRANSACTIONS_H
#define PG_GET_COIN_TRANSACTIONS_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Compile a list of all (historic) transactions performed with the given coin
 * (/refresh/melt, /deposit, /refund and /recoup operations).
 * Should return 0 if @a etag is already current, otherwise
 * return the full history and update @a etag. @a etag
 * should be set to the last row ID of the given coin
 * in the coin history table.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param coin_pub coin to investigate
 * @param[in,out] etag known etag, updated to current etag * @param[out] tlp set to list of transactions, NULL if coin is fresh
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_coin_transactions (
  void *cls,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  uint64_t *etag,
  struct TALER_EXCHANGEDB_TransactionList **tlp);

#endif
