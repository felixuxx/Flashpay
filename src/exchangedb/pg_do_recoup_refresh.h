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
 * @file exchangedb/pg_do_recoup_refresh.h
 * @brief implementation of the do_recoup_refresh function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_DO_RECOUP_REFRESH_H
#define PG_DO_RECOUP_REFRESH_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Perform recoup-refresh operation, checking for sufficient deposits of the
 * coin and possibly persisting the recoup-refresh details.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param old_coin_pub public key of the old coin to credit
 * @param rrc_serial row in the refresh_revealed_coins table justifying the recoup-refresh
 * @param coin_bks coin blinding key secret to persist
 * @param coin_pub public key of the coin being recouped
 * @param known_coin_id row of the @a coin_pub in the known_coins table
 * @param coin_sig signature of the coin requesting the recoup
 * @param[in,out] recoup_timestamp recoup timestamp, set if recoup existed
 * @param[out] recoup_ok  set if the recoup-refresh succeeded (balance ok)
 * @param[out] internal_failure set on internal failures
 * @return query execution status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_do_recoup_refresh (
  void *cls,
  const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  uint64_t rrc_serial,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  uint64_t known_coin_id,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  struct GNUNET_TIME_Timestamp *recoup_timestamp,
  bool *recoup_ok,
  bool *internal_failure);

#endif
