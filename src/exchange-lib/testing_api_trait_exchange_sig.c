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
 * @file exchange-lib/testing_api_trait_exchange_sig.c
 * @brief exchange pub traits.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"

#define TALER_TESTING_TRAIT_EXCHANGE_SIG "exchange-online-signature"


/**
 * Obtain a exchange signature (online sig) from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index index number of the exchange to obtain.
 * @param exchange_sig[out] set to the offered exchange signature.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_exchange_sig
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const struct TALER_ExchangeSignatureP **exchange_sig)
{
  return cmd->traits (cmd->cls,
                      (void **) exchange_sig,
                      TALER_TESTING_TRAIT_EXCHANGE_SIG,
                      index);
}


/**
 * Make a trait for a exchange signature.
 *
 * @param index index number to associate to the offered exchange pub.
 * @param exchange_sig exchange signature to offer with this trait.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_exchange_sig
  (unsigned int index,
   const struct TALER_ExchangeSignatureP *exchange_sig)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_EXCHANGE_SIG,
    .ptr = (const void *) exchange_sig
  };

  return ret;
}

/* end of testing_api_trait_exchange_sig.c */
