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
 * @file exchangedb/pg_do_melt.h
 * @brief implementation of the do_melt function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_DO_MELT_H
#define PG_DO_MELT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Perform melt operation, checking for sufficient balance
 * of the coin and possibly persisting the melt details.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param rms client-contributed input for CS denominations that must be checked for idempotency, or NULL for non-CS withdrawals
 * @param[in,out] refresh refresh operation details; the noreveal_index
 *                is set in case the coin was already melted before
 * @param known_coin_id row of the coin in the known_coins table
 * @param[in,out] zombie_required true if the melt must only succeed if the coin is a zombie, set to false if the requirement was satisfied
 * @param[out] balance_ok set to true if the balance was sufficient
 * @return query execution status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_do_melt (
  void *cls,
  const struct TALER_RefreshMasterSecretP *rms,
  struct TALER_EXCHANGEDB_Refresh *refresh,
  uint64_t known_coin_id,
  bool *zombie_required,
  bool *balance_ok);

#endif
