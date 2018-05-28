/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty
  of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/

/**
 * @file exchange-lib/testing_api_trait_process.c
 * @brief trait offering process handles.
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"

#define TALER_TESTING_TRAIT_PROCESS "process"


/**
 * Obtain location where a command stores a pointer to a process.
 *
 * @param cmd command to extract trait from.
 * @param index which process to pick if @a cmd
 *        has multiple on offer.
 * @param coin_priv[out] set to the address of the pointer to the
 *        process.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_process
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   struct GNUNET_OS_Process ***processp)
{
  return cmd->traits (cmd->cls,
                      (void **) processp,
                      TALER_TESTING_TRAIT_PROCESS,
                      index);
}


/**
 * Offer location where a command stores a pointer to a process.
 * 
 * @param index offered location index number, in case there are
 *        multiple on offer.
 * @param processp process location to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_process
  (unsigned int index,
   struct GNUNET_OS_Process **processp)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_PROCESS,
    .ptr = (const void *) processp
  };

  return ret;
}

/* end of testing_api_trait_process.c */
