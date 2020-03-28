/*
  This file is part of TALER
  Copyright (C) 2018-2020 Taler Systems SA

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
 * @file testing/testing_api_trait_reserve_history.c
 * @brief implements reserve hostry trait
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"

#define TALER_TESTING_TRAIT_RESERVE_HISTORY \
  "reserve-history-entry"


/**
 * Obtain a reserve history entry from a @a cmd.
 *
 * @param cmd command to extract the reserve history from.
 * @param index reserve history's index number.
 * @param[out] rhp set to the reserve history.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_reserve_history (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_EXCHANGE_ReserveHistory **rhp)
{
  return cmd->traits (cmd->cls,
                      (const void **) rhp,
                      TALER_TESTING_TRAIT_RESERVE_HISTORY,
                      index);
}


/**
 * Offer a reserve history entry.
 *
 * @param index reserve pubs's index number.
 * @param rh reserve history entry to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_reserve_history (
  unsigned int index,
  const struct TALER_EXCHANGE_ReserveHistory *rh)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_RESERVE_HISTORY,
    .ptr = (const void *) rh
  };
  return ret;
}


/* end of testing_api_trait_reserve_history.c */
