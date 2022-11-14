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
 * @file exchangedb/pg_have_deposit2.h
 * @brief implementation of the have_deposit2 function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_HAVE_DEPOSIT2_H
#define PG_HAVE_DEPOSIT2_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Check if we have the specified deposit already in the database.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param h_contract_terms contract to check for
 * @param h_wire wire hash to check for
 * @param coin_pub public key of the coin to check for
 * @param merchant merchant public key to check for
 * @param refund_deadline expected refund deadline
 * @param[out] deposit_fee set to the deposit fee the exchange charged
 * @param[out] exchange_timestamp set to the time when the exchange received the deposit
 * @return 1 if we know this operation,
 *         0 if this exact deposit is unknown to us,
 *         otherwise transaction error status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_have_deposit2 (
  void *cls,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant,
  struct GNUNET_TIME_Timestamp refund_deadline,
  struct TALER_Amount *deposit_fee,
  struct GNUNET_TIME_Timestamp *exchange_timestamp);
#endif
