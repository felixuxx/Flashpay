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
 * @brief Heler function for creating dummy inputs for the mint database
 * @author Nicolas Fournier
 */
#ifndef __PERF_TALER_MINTDB_INIT_H___
#define __PERF_TALER_MINTDB_INIT_H___

#include "taler_mintdb_plugin.h"


#define CURRENCY "EUR"

/**
 * All information about a reserve
 */
struct PERF_TALER_MINTDB_Reserve
{
  /**
   * Information about a rserve available to the Mint
   */
  struct TALER_MINTDB_Reserve reserve;

  /**
   * Private key of a reserve
   */
  struct GNUNET_CRYPTO_EddsaPrivateKey private;
};


/**
 * All informations about a coin 
 */
struct PERF_TALER_MINTDB_Coin
{
  /**
   *  Blinded coin, known by the mint
   */
  struct TALER_MINTDB_CollectableBlindcoin blind;

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
struct TALER_MINTDB_DenominationKeyIssueInformation *
PERF_TALER_MINTDB_denomination_init (void);


/**
 * Copies the given denomination
 * @param reserve the deposit copy
 * @return a copy of @a deposit; NULL if error
 */
struct TALER_MINTDB_DenominationKeyIssueInformation *
PERF_TALER_MINTDB_denomination_copy (
  const struct TALER_MINTDB_DenominationKeyIssueInformation *dki);


/**
 * Free memory of a DenominationKeyIssueInformation
 * @param dki pointer to the struct to free
 */
int
PERF_TALER_MINTDB_denomination_free (
  struct TALER_MINTDB_DenominationKeyIssueInformation *dki);


/**
 * Generate a dummy reserve for testing
 * @return a reserve with 1000 EUR in it
 */
struct PERF_TALER_MINTDB_Reserve *
PERF_TALER_MINTDB_reserve_init (void);


/**
 * Copies the given reserve
 * @param reserve the reserve to copy
 * @return a copy of @a reserve; NULL if error
 */
struct PERF_TALER_MINTDB_Reserve *
PERF_TALER_MINTDB_reserve_copy (const struct PERF_TALER_MINTDB_Reserve *reserve);


/**
 * Free memory of a reserve
 * @param reserve pointer to the structure to be freed
 */
int
PERF_TALER_MINTDB_reserve_free (struct PERF_TALER_MINTDB_Reserve *reserve);


/**
 * Generate a dummy deposit for testing purposes
 * @param dki the denomination key used to sign the key
 */
struct TALER_MINTDB_Deposit *
PERF_TALER_MINTDB_deposit_init (
  const struct PERF_TALER_MINTDB_Coin *coin);


/**
 * Copies the given deposit
 * @param reserve the deposit copy
 * @return a copy of @a deposit; NULL if error
 */
struct TALER_MINTDB_Deposit *
PERF_TALER_MINTDB_deposit_copy (const struct TALER_MINTDB_Deposit *deposit);


/**
 * Free memory of a deposit
 * @param deposit pointer to the structure to free
 */
int
PERF_TALER_MINTDB_deposit_free (struct TALER_MINTDB_Deposit *deposit);


/**
 * Generate a coin for testing purpuses
 * @param dki denomination key used to sign the coin
 * @param reserve reserve providing the money for the coin
 * @return a randomly generated CollectableBlindcoin
 */
struct PERF_TALER_MINTDB_Coin *
PERF_TALER_MINTDB_coin_init (
  const struct TALER_MINTDB_DenominationKeyIssueInformation *dki,
  const struct PERF_TALER_MINTDB_Reserve *reserve);


/**
 * Copies the given coin
 * @param coin the coin to copy
 * @return a copy of coin; NULL if error
 */
struct PERF_TALER_MINTDB_Coin *
PERF_TALER_MINTDB_coin_copy (
  const struct PERF_TALER_MINTDB_Coin *coin);


/**
 * Liberate memory of @a coin
 * @param coin pointer to the structure to free
 */
int
PERF_TALER_MINTDB_coin_free (
  struct PERF_TALER_MINTDB_Coin *coin);


/**
 * Create a melt operation
 *
 * @param session the refresh session 
 * @param dki the denomination the melted coin uses
 * @return a pointer to a #TALER_MINTDB_RefreshMelt 
 */
struct TALER_MINTDB_RefreshMelt *
PERF_TALER_MINTDB_refresh_melt_init (struct GNUNET_HashCode *session,
                                     struct PERF_TALER_MINTDB_Coin *coin);


/**
 * Copies the internals of a #TALER_MINTDB_RefreshMelt
 * 
 * @param melt the refresh melt to copy
 * @return an copy of @ melt
 */
struct TALER_MINTDB_RefreshMelt *
PERF_TALER_MINTDB_refresh_melt_copy (const struct TALER_MINTDB_RefreshMelt *melt);


/**
 * Free the internal memory of a #TALER_MINTDB_RefreshMelt
 *
 * @param melt the #TALER_MINTDB_RefreshMelt to free
 * @return #GNUNET_OK if the operation was successful, #GNUNET_SYSERROR
 */
int
PERF_TALER_MINTDB_refresh_melt_free (struct TALER_MINTDB_RefreshMelt *melt);


/**
 * @return a randomly generated refresh session
 */
struct TALER_MINTDB_RefreshSession *
PERF_TALER_MINTDB_refresh_session_init (void);


/**
 * @return #GNUNET_OK if the copy was successful, #GNUNET_SYSERR if it wasn't
 */
int
PERF_TALER_MINTDB_refresh_session_copy (struct TALER_MINTDB_RefreshSession *session, 
                                        struct TALER_MINTDB_RefreshSession *copy);


/**
 * Frees memory of a refresh_session
 */
int
PERF_TALER_MINTDB_refresh_session_free (
  struct TALER_MINTDB_RefreshSession *refresh_session);

#endif
