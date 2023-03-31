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
 * @file exchangedb/pg_select_refunds_by_coin.h
 * @brief implementation of the select_refunds_by_coin function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_REFUNDS_BY_COIN_H
#define PG_SELECT_REFUNDS_BY_COIN_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Select refunds by @a coin_pub, @a merchant_pub and @a h_contract.
 *
 * @param cls closure of plugin
 * @param coin_pub coin to get refunds for
 * @param merchant_pub merchant to get refunds for
 * @param h_contract contract (hash) to get refunds for
 * @param cb function to call for each refund found
 * @param cb_cls closure for @a cb
 * @return query result status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_select_refunds_by_coin (
  void *cls,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_PrivateContractHashP *h_contract,
  TALER_EXCHANGEDB_RefundCoinCallback cb,
  void *cb_cls);

#endif
