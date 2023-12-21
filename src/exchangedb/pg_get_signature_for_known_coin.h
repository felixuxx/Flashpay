/*
   This file is part of TALER
   Copyright (C) 2023 Taler Systems SA

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
 * @file exchangedb/pg_get_signature_for_known_coin.h
 * @brief implementation of the get_signature_for_known_coin function for Postgres
 * @author Özgür Kesim
 */
#ifndef PG_GET_SIGNATURE_FOR_KNOWN_COIN_H
#define PG_GET_SIGNATURE_FOR_KNOWN_COIN_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Retrieve the denomination and the corresponding signature for a known coin.
 *
 * @param cls the plugin closure
 * @param coin_pub the public key of the coin to search for
 * @param[out] denom_pub the denomination of the public key, if coin was present
 * @param[out] denom_sig the signature with the denomination key of the coin, if coin was present
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_signature_for_known_coin (
  void *cls,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct TALER_DenominationPublicKey *denom_pub,
  struct TALER_DenominationSignature *denom_sig);

#endif
