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
 * @file pg_get_reserve_history.h
 * @brief implementation of the get_reserve_history function
 * @author Christian Grothoff
 */
#ifndef PG_GET_RESERVE_HISTORY_H
#define PG_GET_RESERVE_HISTORY_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Compile a list of (historic) transactions performed with the given reserve
 * (withdraw, incoming wire, open, close operations).  Should return 0 if the @a
 * reserve_pub is unknown, otherwise determine @a etag_out and if it is past @a
 * etag_in return the history after @a start_off. @a etag_out should be set
 * to the last row ID of the given @a reserve_pub in the reserve history table.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param reserve_pub public key of the reserve
 * @param start_off maximum starting offset in history to exclude from returning
 * @param etag_in up to this offset the client already has a response, do not
 *                   return anything unless @a etag_out will be larger
 * @param[out] etag_out set to the latest history offset known for this @a coin_pub
 * @param[out] balance set to the reserve balance
 * @param[out] rhp set to known transaction history (NULL if reserve is unknown)
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_reserve_history (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  uint64_t start_off,
  uint64_t etag_in,
  uint64_t *etag_out,
  struct TALER_Amount *balance,
  struct TALER_EXCHANGEDB_ReserveHistory **rhp);


#endif
