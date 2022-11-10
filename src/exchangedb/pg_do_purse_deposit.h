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
 * @file exchangedb/pg_do_purse_deposit.h
 * @brief implementation of the do_purse_deposit function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_DO_PURSE_DEPOSIT_H
#define PG_DO_PURSE_DEPOSIT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Function called to execute a transaction crediting
 * a purse with @a amount from @a coin_pub. Reduces the
 * value of @a coin_pub and increase the balance of
 * the @a purse_pub purse. If the balance reaches the
 * target amount and the purse has been merged, triggers
 * the updates of the reserve/account balance.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub purse to credit
 * @param coin_pub coin to deposit (debit)
 * @param amount fraction of the coin's value to deposit
 * @param coin_sig signature affirming the operation
 * @param amount_minus_fee amount to add to the purse
 * @param[out] balance_ok set to false if the coin's
 *        remaining balance is below @a amount;
 *             in this case, the return value will be
 *             #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT despite the failure
 * @param[out] conflict set to true if the deposit failed due to a conflict (coin already spent,
 *             or deposited into this purse with a different amount)
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_do_purse_deposit (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_Amount *amount,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  const struct TALER_Amount *amount_minus_fee,
  bool *balance_ok,
  bool *conflict);

#endif
