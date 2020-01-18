/*
  This file is part of TALER
  Copyright (C) 2018-2020 Taler Systems SA

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
 * @file lib/testing_api_trait_contract.c
 * @brief offers contract term trait.
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"


/**
 * Contains a contract terms object as a json_t.
 */
#define TALER_TESTING_TRAIT_CONTRACT_TERMS "contract-terms"


/**
 * Obtain contract terms from @a cmd.
 *
 * @param cmd command to extract the contract terms from.
 * @param index contract terms index number.
 * @param[out] contract_terms where to write the contract terms.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_contract_terms (const struct TALER_TESTING_Command *cmd,
                                        unsigned int index,
                                        const json_t **contract_terms)
{
  return cmd->traits (cmd->cls,
                      (const void **) contract_terms,
                      TALER_TESTING_TRAIT_CONTRACT_TERMS,
                      index);
}


/**
 * Offer contract terms.
 *
 * @param index contract terms index number.
 * @param contract_terms contract terms to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_contract_terms (unsigned int index,
                                         const json_t *contract_terms)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_CONTRACT_TERMS,
    .ptr = (const void *) contract_terms
  };
  return ret;
}
