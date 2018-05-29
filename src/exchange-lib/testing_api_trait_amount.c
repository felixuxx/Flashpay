/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/

/**
 * @file exchange-lib/testing_api_trait_amount.c
 * @brief offer amounts as traits.
 * @author Marcello Stanisci
 */

#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"

#define TALER_TESTING_TRAIT_AMOUNT "amount"

/**
 * Obtain an amount from a @a cmd.
 *
 * @param cmd command to extract the amount from.
 * @param index which amount to pick if @a cmd has multiple
 *        on offer
 * @param amount[out] set to the amount.
 *
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_amount_obj
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const struct TALER_Amount **amount)
{
  return cmd->traits (cmd->cls,
                      (void **) amount,
                      TALER_TESTING_TRAIT_AMOUNT,
                      index);
}


/**
 * Offer amount.
 *
 * @param index which amount to offer, in case there are
 *        multiple available.
 * @param amount the amount to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_amount_obj
  (unsigned int index,
   const struct TALER_Amount *amount)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_AMOUNT,
    .ptr = (const void *) amount
  };

  return ret;
}


/* end of testing_api_trait_amount.c */
