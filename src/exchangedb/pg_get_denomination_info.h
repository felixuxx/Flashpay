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
 * @file exchangedb/pg_get_denomination_info.h
 * @brief implementation of the get_denomination_info function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_DENOMINATION_INFO_H
#define PG_GET_DENOMINATION_INFO_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Fetch information about a denomination key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param denom_pub_hash hash of the public key used for signing coins of this denomination
 * @param[out] issue set to issue information with value, fees and other info about the coin
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_denomination_info (
  void *cls,
  const struct TALER_DenominationHashP *denom_pub_hash,
  struct TALER_EXCHANGEDB_DenominationKeyInformation *issue);

#endif
