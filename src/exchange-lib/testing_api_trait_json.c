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
 * @file exchange-lib/testing_api_trait_json.c
 * @brief offers JSON traits.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"

#define TALER_TESTING_TRAIT_WIRE_DETAILS "wire-details"

/**
 * Obtain wire details from @a cmd.
 *
 * @param cmd command to extract the wire details from.
 * @param index index number associate with the wire details
 *        on offer; usually zero, as one command sticks to
 *        one bank account.
 * @param wire_details[out] where to write the wire details.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_wire_details
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const json_t **wire_details)
{
  return cmd->traits (cmd->cls,
                      (void **) wire_details,
                      TALER_TESTING_TRAIT_WIRE_DETAILS,
                      index);
}

/**
 * Offer wire details in a trait.
 *
 * @param index index number associate with the wire details
 *        on offer; usually zero, as one command sticks to
 *        one bank account.
 * @param wire_details wire details to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_wire_details
  (unsigned int index,
   const json_t *wire_details)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_WIRE_DETAILS,
    .ptr = (const json_t *) wire_details
  };
  return ret;
}

/* end of testing_api_trait_json.c */
