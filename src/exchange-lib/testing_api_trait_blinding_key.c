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
 * @file exchange-lib/testing_api_trait_blinding_key.c
 * @brief main interpreter loop for testcases
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"

#define TALER_TESTING_TRAIT_BLINDING_KEY "blinding-key"


/**
 * Obtain a blinding key from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param selector which coin to pick if @a cmd has multiple on offer
 * @param blinding_key[out] set to the blinding key of the coin
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_blinding_key (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  struct TALER_DenominationBlindingKeyP **blinding_key)
{
  return cmd->traits (cmd->cls,
                      (void **) blinding_key,
                      TALER_TESTING_TRAIT_BLINDING_KEY,
                      index);
}


struct TALER_TESTING_Trait
TALER_TESTING_make_trait_blinding_key (
  unsigned int index,
  const struct TALER_DenominationBlindingKeyP *blinding_key)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_BLINDING_KEY,
    .ptr = (const void *) blinding_key
  };

  return ret;
}


/* end of testing_api_trait_blinding_key.c */
