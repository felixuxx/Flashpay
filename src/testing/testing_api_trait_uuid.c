/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file testing/testing_api_trait_uuid.c
 * @brief offer any trait that is passed over as a uuid.
 * @author Jonathan Buchanan
 */
#include "platform.h"
#include <taler/taler_signatures.h>
#include <taler/taler_exchange_service.h>
#include <taler/taler_testing_lib.h>


#define TALER_TESTING_TRAIT_UUID "uuid"
#define TALER_TESTING_TRAIT_CLAIM_TOKEN "claim_token"


/**
 * Obtain a uuid from @a cmd.
 *
 * @param cmd command to extract the uuid from.
 * @param index which amount to pick if @a cmd has multiple
 *        on offer
 * @param[out] uuid where to write the uuid.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_uuid (const struct TALER_TESTING_Command *cmd,
                              unsigned int index,
                              struct GNUNET_Uuid **uuid)
{
  return cmd->traits (cmd->cls,
                      (const void **) uuid,
                      TALER_TESTING_TRAIT_UUID,
                      index);
}


/**
 * Offer a uuid in a trait.
 *
 * @param index which uuid to offer, in case there are
 *        multiple available.
 * @param uuid the uuid to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_uuid (unsigned int index,
                               const struct GNUNET_Uuid *uuid)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_UUID,
    .ptr = (const void *) uuid
  };
  return ret;
}


/**
 * Obtain a claim token from @a cmd.
 *
 * @param cmd command to extract the token from.
 * @param index which amount to pick if @a cmd has multiple
 *        on offer
 * @param[out] ct where to write the token.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_claim_token (const struct TALER_TESTING_Command *cmd,
                                     unsigned int index,
                                     const struct TALER_ClaimTokenP **ct)
{
  return cmd->traits (cmd->cls,
                      (const void **) ct,
                      TALER_TESTING_TRAIT_CLAIM_TOKEN,
                      index);
}


/**
 * Offer a claim token in a trait.
 *
 * @param index which token to offer, in case there are
 *        multiple available.
 * @param ct the token to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_claim_token (unsigned int index,
                                      const struct TALER_ClaimTokenP *ct)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_CLAIM_TOKEN,
    .ptr = (const void *) ct
  };
  return ret;
}
