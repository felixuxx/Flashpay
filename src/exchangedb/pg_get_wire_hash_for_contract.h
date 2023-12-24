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
 * @file exchangedb/pg_get_wire_hash_for_contract.h
 * @brief implementation of the get_wire_hash_for_contract function for Postgres
 * @author Özgür Kesim
 */
#ifndef PG_GET_WIRE_HASH_FOR_CONTRACT_H
#define PG_GET_WIRE_HASH_FOR_CONTRACT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Try to get the salted hash of a merchant's bank account to a deposit
 * contract. This is necessary in the event of a conflict with a given
 * (merchant_pub, h_contract_terms) during deposit.
 *
 * @param cls closure
 * @param merchant_pub merchant public key
 * @param h_contract_terms hash of the proposal data
 * @param[out] h_wire salted hash of a merchant's bank account
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_wire_hash_for_contract (
  void *cls,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  struct TALER_MerchantWireHashP *h_wire);

#endif
