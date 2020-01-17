/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published
  by the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/

/**
 * @file exchange-lib/testing_api_fresh_coin.c
 * @brief traits to offer fresh conins (after "melt" operations)
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"

#define TALER_TESTING_TRAIT_FRESH_COINS "fresh-coins"

/**
 * Get a array of fresh coins.
 *
 * @param cmd command to extract the fresh coin from.
 * @param index which array to pick if @a cmd has multiple
 *        on offer.
 * @param fresh_coins[out] will point to the offered array.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_fresh_coins
  (const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_TESTING_FreshCoinData **fresh_coins)
{
  return cmd->traits (cmd->cls,
                      (const void **) fresh_coins,
                      TALER_TESTING_TRAIT_FRESH_COINS,
                      index);
}


/**
 * Offer a _array_ of fresh coins.
 *
 * @param index which array of fresh coins to offer,
 *        if there are multiple on offer.  Tipically passed as
 *        zero.
 * @param fresh_coins the array of fresh coins to offer
 *
 * @return the trait,
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_fresh_coins
  (unsigned int index,
  const struct TALER_TESTING_FreshCoinData *fresh_coins)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_FRESH_COINS,
    .ptr = (const void *) fresh_coins
  };
  return ret;
}


/* end of testing_api_trait_fresh_coin.c */
