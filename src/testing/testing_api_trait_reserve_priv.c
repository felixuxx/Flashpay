/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3, or
  (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_trait_reserve_priv.c
 * @brief implements reserve private key trait
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"

#define TALER_TESTING_TRAIT_RESERVE_PRIVATE_KEY \
  "reserve-private-key"

/**
 * Obtain a reserve private key from a @a cmd.
 *
 * @param cmd command to extract the reserve priv from.
 * @param index reserve priv's index number.
 * @param[out] reserve_priv set to the reserve priv.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_reserve_priv
  (const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_ReservePrivateKeyP **reserve_priv)
{
  return cmd->traits (cmd->cls,
                      (const void **) reserve_priv,
                      TALER_TESTING_TRAIT_RESERVE_PRIVATE_KEY,
                      index);
}


/**
 * Offer a reserve private key.
 *
 * @param index reserve priv's index number.
 * @param reserve_priv reserve private key to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_reserve_priv
  (unsigned int index,
  const struct TALER_ReservePrivateKeyP *reserve_priv)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_RESERVE_PRIVATE_KEY,
    .ptr = (const void *) reserve_priv
  };
  return ret;
}


/* end of testing_api_trait_reserve_priv.c */
