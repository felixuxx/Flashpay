/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published
  by the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file exchange-lib/testing_api_trait_denom_pub.c
 * @brief denom pub traits.
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"

#define TALER_TESTING_TRAIT_DENOM_PUB "denomination-public-key"


/**
 * Obtain a denomination public key from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index index number of the denom to obtain.
 * @param denom_pub[out] set to the offered denom pub.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_denom_pub
  (const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_EXCHANGE_DenomPublicKey **denom_pub)
{
  return cmd->traits (cmd->cls,
                      (const void **) denom_pub,
                      TALER_TESTING_TRAIT_DENOM_PUB,
                      index);
}


/**
 * Make a trait for a denomination public key.
 *
 * @param index index number to associate to the offered denom pub.
 * @param denom_pub denom pub to offer with this trait.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_denom_pub
  (unsigned int index,
  const struct TALER_EXCHANGE_DenomPublicKey *denom_pub)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_DENOM_PUB,
    .ptr = (const void *) denom_pub
  };

  return ret;
}

/* end of testing_api_trait_denom_pub.c */
