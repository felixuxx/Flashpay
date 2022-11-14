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
 * @file exchangedb/pg_get_reserve_by_h_blind.h
 * @brief implementation of the get_reserve_by_h_blind function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_RESERVE_BY_H_BLIND_H
#define PG_GET_RESERVE_BY_H_BLIND_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Obtain information about which reserve a coin was generated
 * from given the hash of the blinded coin.
 *
 * @param cls closure
 * @param bch hash that uniquely identifies the withdraw request
 * @param[out] reserve_pub set to information about the reserve (on success only)
 * @param[out] reserve_out_serial_id set to row of the @a h_blind_ev in reserves_out
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_reserve_by_h_blind (
  void *cls,
  const struct TALER_BlindedCoinHashP *bch,
  struct TALER_ReservePublicKeyP *reserve_pub,
  uint64_t *reserve_out_serial_id);

#endif
