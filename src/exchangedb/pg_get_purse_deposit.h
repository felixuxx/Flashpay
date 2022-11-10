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
 * @file exchangedb/pg_get_purse_deposit.h
 * @brief implementation of the get_purse_deposit function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_PURSE_DEPOSIT_H
#define PG_GET_PURSE_DEPOSIT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Function called to obtain a coin deposit data from
 * depositing the coin into a purse.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub purse to credit
 * @param coin_pub coin to deposit (debit)
 * @param[out] amount set fraction of the coin's value that was deposited (with fee)
 * @param[out] h_denom_pub set to hash of denomination of the coin
 * @param[out] phac set to hash of age restriction on the coin
 * @param[out] coin_sig set to signature affirming the operation
 * @param[out] partner_url set to the URL of the partner exchange, or NULL for ourselves, must be freed by caller
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_purse_deposit (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct TALER_Amount *amount,
  struct TALER_DenominationHashP *h_denom_pub,
  struct TALER_AgeCommitmentHash *phac,
  struct TALER_CoinSpendSignatureP *coin_sig,
  char **partner_url);

#endif
