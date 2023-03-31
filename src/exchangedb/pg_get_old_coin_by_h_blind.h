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
 * @file exchangedb/pg_get_old_coin_by_h_blind.h
 * @brief implementation of the get_old_coin_by_h_blind function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_OLD_COIN_BY_H_BLIND_H
#define PG_GET_OLD_COIN_BY_H_BLIND_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Obtain information about which old coin a coin was refreshed
 * given the hash of the blinded (fresh) coin.
 *
 * @param cls closure
 * @param h_blind_ev hash of the blinded coin
 * @param[out] old_coin_pub set to information about the old coin (on success only)
 * @param[out] rrc_serial set to serial number of the entry in the database
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_old_coin_by_h_blind (
  void *cls,
  const struct TALER_BlindedCoinHashP *h_blind_ev,
  struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  uint64_t *rrc_serial);

#endif
