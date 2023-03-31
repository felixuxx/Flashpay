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
 * @file exchangedb/pg_ensure_coin_known.h
 * @brief implementation of the ensure_coin_known function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_ENSURE_COIN_KNOWN_H
#define PG_ENSURE_COIN_KNOWN_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Make sure the given @a coin is known to the database.
 *
 * @param cls database connection plugin state
 * @param coin the coin that must be made known
 * @param[out] known_coin_id set to the unique row of the coin
 * @param[out] denom_hash set to the denomination hash of the existing
 *             coin (for conflict error reporting)
 * @param[out] h_age_commitment  set to the conflicting age commitment hash on conflict
 * @return database transaction status, non-negative on success
 */
enum TALER_EXCHANGEDB_CoinKnownStatus
TEH_PG_ensure_coin_known (void *cls,
                          const struct TALER_CoinPublicInfo *coin,
                          uint64_t *known_coin_id,
                          struct TALER_DenominationHashP *denom_hash,
                          struct TALER_AgeCommitmentHash *h_age_commitment);

#endif
