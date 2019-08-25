/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 3, or (at your
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
 * @file exchange-lib/testing_api_trait_coin_priv.c
 * @brief coin priv traits.
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"

#define TALER_TESTING_TRAIT_COIN_PRIVATE_KEY "coin-private-key"


/**
 * Obtain a coin private key from a @a cmd.
 *
 * @param cmd command to extract trait from.
 * @param index index of the coin priv to obtain.
 * @param coin_priv[out] set to the private key of the coin.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_coin_priv
  (const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_CoinSpendPrivateKeyP **coin_priv)
{
  return cmd->traits (cmd->cls,
                      (const void **) coin_priv,
                      TALER_TESTING_TRAIT_COIN_PRIVATE_KEY,
                      index);
}


/**
 * Offer coin private key.
 *
 * @param index index number to associate with offered coin priv.
 * @param coin_priv coin private key to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_coin_priv
  (unsigned int index,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_COIN_PRIVATE_KEY,
    .ptr = (const void *) coin_priv
  };

  return ret;
}

/* end of testing_api_trait_coin_priv.c */
