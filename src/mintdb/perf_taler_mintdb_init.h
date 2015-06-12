/*
   This file is part of TALER
   Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

   TALER is free software; you can redistribute it and/or modify it under the
   terms of the GNU General Public License as published by the Free Software
   Foundation; either version 3, or (at your option) any later version.

   TALER is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
   A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

   You should have received a copy of the GNU General Public License along with
   TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
   */
/**
 * @file mintdb/perf_taler_mintdb_init.h
 * @brief Heler function for creating dummy inpus for the mint database
 * @author Nicolas Fournier
 */
#ifndef __PERF_TALER_MINTDB_INIT_H___
#define __PERF_TALER_MINTDB_INIT_H___

#include "taler_mintdb_plugin.h"


#define CURRENCY "EUR"


/**
 * @return a randomly generated CollectableBlindcoin
 */
struct TALER_MINTDB_CollectableBlindcoin *
PERF_TALER_MINTDB_collectable_blindcoin_init (void);


/**
 * Liberate memory of @a coin
 */
int
PERF_TALER_MINTDB_collectable_blindcoin_free (struct TALER_MINTDB_CollectableBlindcoin *NAME);


/**
 * @return a randomly generated reserve
 */
struct TALER_MINTDB_Reserve *
PERF_TALER_MINTDB_reserve_init (void);


/**
 * Free memory of a reserve
 */
int
PERF_TALER_MINTDB_reserve_free (struct TALER_MINTDB_Reserve *reserve);


/**
 * @return a randomly generated refresh session
 */
struct TALER_MINTDB_RefreshSession *
PERF_TALER_MINTDB_refresh_session_init (void);


/**
 * Frees memory of a refresh_session
 */
int
PERF_TALER_MINTDB_refresh_session_free (struct TALER_MINTDB_RefreshSession *refresh_session);


/**
 * Create a randomly generated deposit
 */
struct TALER_MINTDB_Deposit *
PERF_TALER_MINTDB_deposit_init ();


/**
 * Free memory of a deposit
 */
int
PERF_TALER_MINTDB_deposit_free (struct TALER_MINTDB_Deposit *deposit);


/**
 * Generate a randomly generate DenominationKeyInformation
 */
struct TALER_MINTDB_DenominationKeyIssueInformation *
PERF_TALER_MINTDB_denomination_init (void);


/**
 * Free memory for a DenominationKeyIssueInformation
 */
int
PERF_TALER_MINTDB_denomination_free (struct TALER_MINTDB_DenominationKeyIssueInformation *dki);


/**
 * Generate a random CoinPublicInfo
 */
struct TALER_CoinPublicInfo *
PERF_TALER_MINTDB_coin_public_info_init (void);


/**
 * Free a CoinPublicInfo
 */
int PERF_TALER_MINTDB_coin_public_info_free (struct TALER_CoinPublicInfo *cpi);

#endif
