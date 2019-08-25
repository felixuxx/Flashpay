/*
   This file is part of TALER
   Copyright (C) 2014, 2015 GNUnet e.V.

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
 * @file exchangedb/perf_taler_exchangedb_init.h
 * @brief Heler function for creating dummy inputs for the exchange database
 * @author Nicolas Fournier
 */
#ifndef __PERF_TALER_EXCHANGEDB_INIT_H___
#define __PERF_TALER_EXCHANGEDB_INIT_H___

#include "taler_exchangedb_plugin.h"


#define CURRENCY "EUR"

/**
 * All information about a reserve
 */
struct PERF_TALER_EXCHANGEDB_Reserve
{
  /**
   * Information about a rserve available to the Exchange
   */
  struct TALER_EXCHANGEDB_Reserve reserve;

  /**
   * Private key of a reserve
   */
  struct GNUNET_CRYPTO_EddsaPrivateKey private;
};


/**
 * All informations about a coin
 */
struct PERF_TALER_EXCHANGEDB_Coin
{
  /**
   *  Blinded coin, known by the exchange
   */
  struct TALER_EXCHANGEDB_CollectableBlindcoin blind;

  /**
   *  Public key of the coin and othes informations
   */
  struct TALER_CoinPublicInfo public_info;

  /**
   * Private key of the coin
   */
  struct GNUNET_CRYPTO_EddsaPrivateKey priv;
};


/**
 * Generate a dummy DenominationKeyInformation for testing purposes
 * @return a dummy denomination key
 */
struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *
PERF_TALER_EXCHANGEDB_denomination_init (void);


/**
 * Copies the given denomination
 * @param reserve the deposit copy
 * @return a copy of @a deposit; NULL if error
 */
struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *
PERF_TALER_EXCHANGEDB_denomination_copy (const struct
                                         TALER_EXCHANGEDB_DenominationKeyIssueInformation
                                         *dki);


/**
 * Free memory of a DenominationKeyIssueInformation
 * @param dki pointer to the struct to free
 */
int
PERF_TALER_EXCHANGEDB_denomination_free (struct
                                         TALER_EXCHANGEDB_DenominationKeyIssueInformation
                                         *dki);


/**
 * Generate a dummy reserve for testing
 * @return a reserve with 1000 EUR in it
 */
struct PERF_TALER_EXCHANGEDB_Reserve *
PERF_TALER_EXCHANGEDB_reserve_init (void);


/**
 * Copies the given reserve
 * @param reserve the reserve to copy
 * @return a copy of @a reserve; NULL if error
 */
struct PERF_TALER_EXCHANGEDB_Reserve *
PERF_TALER_EXCHANGEDB_reserve_copy (const struct
                                    PERF_TALER_EXCHANGEDB_Reserve *reserve);


/**
 * Free memory of a reserve
 * @param reserve pointer to the structure to be freed
 */
int
PERF_TALER_EXCHANGEDB_reserve_free (struct
                                    PERF_TALER_EXCHANGEDB_Reserve *reserve);


/**
 * Generate a dummy deposit for testing purposes
 * @param dki the denomination key used to sign the key
 */
struct TALER_EXCHANGEDB_Deposit *
PERF_TALER_EXCHANGEDB_deposit_init (const struct
                                    PERF_TALER_EXCHANGEDB_Coin *coin);


/**
 * Copies the given deposit
 * @param reserve the deposit copy
 * @return a copy of @a deposit; NULL if error
 */
struct TALER_EXCHANGEDB_Deposit *
PERF_TALER_EXCHANGEDB_deposit_copy (const struct
                                    TALER_EXCHANGEDB_Deposit *deposit);


/**
 * Free memory of a deposit
 * @param deposit pointer to the structure to free
 */
int
PERF_TALER_EXCHANGEDB_deposit_free (struct TALER_EXCHANGEDB_Deposit *deposit);


/**
 * Generate a coin for testing purpuses
 * @param dki denomination key used to sign the coin
 * @param reserve reserve providing the money for the coin
 * @return a randomly generated CollectableBlindcoin
 */
struct PERF_TALER_EXCHANGEDB_Coin *
PERF_TALER_EXCHANGEDB_coin_init (const struct
                                 TALER_EXCHANGEDB_DenominationKeyIssueInformation
                                 *dki,
                                 const struct
                                 PERF_TALER_EXCHANGEDB_Reserve *reserve);


/**
 * Copies the given coin
 * @param coin the coin to copy
 * @return a copy of coin; NULL if error
 */
struct PERF_TALER_EXCHANGEDB_Coin *
PERF_TALER_EXCHANGEDB_coin_copy (const struct PERF_TALER_EXCHANGEDB_Coin *coin);


/**
 * Liberate memory of @a coin
 * @param coin pointer to the structure to free
 */
int
PERF_TALER_EXCHANGEDB_coin_free (struct PERF_TALER_EXCHANGEDB_Coin *coin);


/**
 * Create a melt operation
 *
 * @param rc the commitment of the refresh session
 * @param dki the denomination the melted coin uses
 * @return a pointer to a #TALER_EXCHANGEDB_RefreshMelt
 */
struct TALER_EXCHANGEDB_RefreshMelt *
PERF_TALER_EXCHANGEDB_refresh_melt_init (struct TALER_RefreshCommitmentP *rc,
                                         struct PERF_TALER_EXCHANGEDB_Coin *coin);


/**
 * Copies the internals of a #TALER_EXCHANGEDB_RefreshMelt
 *
 * @param melt the refresh melt to copy
 * @return an copy of @ melt
 */
struct TALER_EXCHANGEDB_RefreshMelt *
PERF_TALER_EXCHANGEDB_refresh_melt_copy (const struct
                                         TALER_EXCHANGEDB_RefreshMelt *melt);


/**
 * Free the internal memory of a #TALER_EXCHANGEDB_RefreshMelt
 *
 * @param melt the #TALER_EXCHANGEDB_RefreshMelt to free
 * @return #GNUNET_OK if the operation was successful, #GNUNET_SYSERROR
 */
int
PERF_TALER_EXCHANGEDB_refresh_melt_free (struct
                                         TALER_EXCHANGEDB_RefreshMelt *melt);

#endif
