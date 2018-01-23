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
 * @file exchange-lib/testing_api_trait_key_peer.c
 * @brief traits to offer peer's (private) keys
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"

/**
 * NOTE: calling it "peer" key to make clear it is _not a coin_
 *       key.
 */

#define TALER_TESTING_TRAIT_KEY_PEER "key-peer"

/**
 * Obtain a private key from a "peer".  Used e.g. to obtain
 * a merchant's priv to sign a /track request.
 *
 * @param index (tipically zero) which key to return if they
 *        exist in an array.
 * @param selector which coin to pick if @a cmd has multiple on
 * offer
 * @param priv[out] set to the key coming from @a cmd.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_peer_key
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const struct GNUNET_CRYPTO_EddsaPrivateKey **priv)
{
  return cmd->traits (cmd->cls,
                      (void **) priv,
                      TALER_TESTING_TRAIT_KEY_PEER,
                      index);
}

/**
 * @param index (tipically zero) which key to return if they
 *        exist in an array.
 * @param priv which object should be returned
 *
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_peer_key
  (unsigned int index,
   struct GNUNET_CRYPTO_EddsaPrivateKey *priv)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_KEY_PEER,
    .ptr = (const void *) priv
  };
  return ret;
}

/* end of testing_api_trait_key_peer.c */
