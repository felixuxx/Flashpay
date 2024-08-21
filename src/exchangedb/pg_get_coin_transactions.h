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
 * Compile a list of (historic) transactions performed with the given coin
 * (melt, refund, recoup and deposit operations).  Should return 0 if the @a
 * coin_pub is unknown, otherwise determine @a etag_out and if it is past @a
 * etag_in return the history after @a start_off. @a etag_out should be set
 * to the last row ID of the given @a coin_pub in the coin history table.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param begin_transaction true to run this in its own transaction(s)
 * @param coin_pub coin to investigate
 * @param start_off starting offset from which on to return entries
 * @param etag_in up to this offset the client already has a response, do not
 *                   return anything unless @a etag_out will be larger
 * @param[out] etag_out set to the latest history offset known for this @a coin_pub
 * @param[out] balance set to current balance of the coin
 * @param[out] h_denom_pub set to denomination public key of the coin
 * @param[out] tlp set to list of transactions, set to NULL if coin has no
 *             transaction history past @a start_off or if @a etag_in is equal
 *             to the value written to @a etag_out.
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_coin_transactions (
  void *cls,
  bool begin_transaction,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  uint64_t start_off,
  uint64_t etag_in,
  uint64_t *etag_out,
  struct TALER_Amount *balance,
  struct TALER_DenominationHashP *h_denom_pub,
  struct TALER_EXCHANGEDB_TransactionList **tlp);


#endif
