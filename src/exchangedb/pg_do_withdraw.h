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
 * @file exchangedb/pg_do_withdraw.h
 * @brief implementation of the do_withdraw function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_DO_WITHDRAW_H
#define PG_DO_WITHDRAW_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Perform withdraw operation, checking for sufficient balance
 * and possibly persisting the withdrawal details.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param nonce client-contributed input for CS denominations that must be checked for idempotency, or NULL for non-CS withdrawals
 * @param[in,out] collectable corresponding collectable coin (blind signature) if a coin is found; possibly updated if a (different) signature exists already
 * @param now current time (rounded)
 * @param[out] found set to true if the reserve was found
 * @param[out] balance_ok set to true if the balance was sufficient
 * @param[out] nonce_ok set to false if the nonce was reused
 * @param[out] ruuid set to the reserve's UUID (reserves table row)
 * @return query execution status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_do_withdraw (
  void *cls,
  const struct TALER_CsNonce *nonce,
  const struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable,
  struct GNUNET_TIME_Timestamp now,
  bool *found,
  bool *balance_ok,
  bool *nonce_ok,
  uint64_t *ruuid);

#endif
