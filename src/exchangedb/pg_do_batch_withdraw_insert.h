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
 * @file exchangedb/pg_do_batch_withdraw_insert.h
 * @brief implementation of the do_batch_withdraw_insert function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_DO_BATCH_WITHDRAW_INSERT_H
#define PG_DO_BATCH_WITHDRAW_INSERT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Perform insert as part of a batch withdraw operation, and persisting the
 * withdrawal details.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param nonce client-contributed input for CS denominations that must be checked for idempotency, or NULL for non-CS withdrawals
 * @param collectable corresponding collectable coin (blind signature)
 * @param now current time (rounded)
 * @param ruuid reserve UUID
 * @param[out] denom_unknown set if the denomination is unknown in the DB
 * @param[out] conflict if the envelope was already in the DB
 * @param[out] nonce_reuse if @a nonce was non-NULL and reused
 * @return query execution status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_do_batch_withdraw_insert (
  void *cls,
  const union GNUNET_CRYPTO_BlindSessionNonce *nonce,
  const struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable,
  struct GNUNET_TIME_Timestamp now,
  uint64_t ruuid,
  bool *denom_unknown,
  bool *conflict,
  bool *nonce_reuse);

#endif
