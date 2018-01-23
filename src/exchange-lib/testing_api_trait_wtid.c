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
 * @file exchange-lib/testing_api_trait_number.c
 * @brief traits to offer numbers
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"

#define TALER_TESTING_TRAIT_WTID "wtid"

/**
 * Obtain a WTID value from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index which WTID to pick if @a cmd has multiple on
 *        offer
 * @param wtid[out] set to the wanted WTID.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_wtid
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   struct TALER_WireTransferIdentifierRawP **wtid)
{
  return cmd->traits (cmd->cls,
                      (void **) wtid,
                      TALER_TESTING_TRAIT_WTID,
                      index);
}

/**
 * @param index associate the object with this index
 * @param wtid which object should be returned
 *
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_wtid
  (unsigned int index,
   struct TALER_WireTransferIdentifierRawP *wtid)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_WTID,
    .ptr = (const void *) wtid
  };
  return ret;
}

/* end of testing_api_trait_number.c */
