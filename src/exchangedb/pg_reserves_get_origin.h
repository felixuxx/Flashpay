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
 * @file exchangedb/pg_reserves_get_origin.h
 * @brief implementation of the reserves_get_origin function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_RESERVES_GET_ORIGIN_H
#define PG_RESERVES_GET_ORIGIN_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Get the origin of funds of a reserve.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param reserve_pub public key of the reserve
 * @param[out] h_payto set to hash of the wire source payto://-URI
 * @param[out] payto_uri set to the wire source payto://-URI
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_reserves_get_origin (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct TALER_FullPaytoHashP *h_payto,
  struct TALER_FullPayto *payto_uri);

#endif
