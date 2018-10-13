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
 * @file exchange-lib/testing_api_trait_cmd.c
 * @brief offers CMDs as traits.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"

#define TALER_TESTING_TRAIT_CMD "cmd"

/**
 * Obtain a command from @a cmd.
 *
 * @param cmd command to extract the command from.
 * @param index always zero.  Commands offering this
 *        kind of traits do not need this index.  For
 *        example, a "batch" CMD returns always the
 *        CMD currently being executed.
 * @param cmd_[out] where to write the wire details.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_cmd
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   struct TALER_TESTING_Command **_cmd)
{
  return cmd->traits (cmd->cls,
                      (void **) _cmd,
                      TALER_TESTING_TRAIT_CMD,
                      index);
}

/**
 * Offer a command in a trait.
 *
 * @param index always zero.  Commands offering this
 *        kind of traits do not need this index.  For
 *        example, a "meta" CMD returns always the
 *        CMD currently being executed.
 * @param cmd wire details to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_cmd
  (unsigned int index,
   const struct TALER_TESTING_Command *cmd)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_CMD,
    .ptr = (const struct TALER_TESTING_Command *) cmd
  };
  return ret;
}

/* end of testing_api_trait_cmd.c */
