/*
  This file is part of TALER
  Copyright (C) 2018, 2021 Taler Systems SA

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
 * @file testing/testing_api_traits.c
 * @brief loop for trait resolution
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"


TALER_TESTING_SIMPLE_TRAITS (TALER_TESTING_MAKE_IMPL_SIMPLE_TRAIT)

TALER_TESTING_INDEXED_TRAITS (TALER_TESTING_MAKE_IMPL_INDEXED_TRAIT)


/**
 * End a trait array.  Usually, commands offer several traits,
 * and put them in arrays.
 */
struct TALER_TESTING_Trait
TALER_TESTING_trait_end ()
{
  struct TALER_TESTING_Trait end = {
    .index = 0,
    .trait_name = NULL,
    .ptr = NULL
  };

  return end;
}


enum GNUNET_GenericReturnValue
TALER_TESTING_get_trait (const struct TALER_TESTING_Trait *traits,
                         const void **ret,
                         const char *trait,
                         unsigned int index)
{
  for (unsigned int i = 0; NULL != traits[i].trait_name; i++)
  {
    if ( (0 == strcmp (trait,
                       traits[i].trait_name)) &&
         (index == traits[i].index) )
    {
      *ret = (void *) traits[i].ptr;
      return GNUNET_OK;
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Trait %s/%u not found.\n",
              trait,
              index);
  return GNUNET_SYSERR;
}


const char *
TALER_TESTING_get_exchange_url (struct TALER_TESTING_Interpreter *is)
{
  const char *exchange_url;
  const struct TALER_TESTING_Command *exchange_cmd;

  exchange_cmd
    = TALER_TESTING_interpreter_get_command (is,
                                             "exchange");
  if (NULL == exchange_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return NULL;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_exchange_url (exchange_cmd,
                                            &exchange_url))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return NULL;
  }
  return exchange_url;
}


struct TALER_EXCHANGE_Keys *
TALER_TESTING_get_keys (
  struct TALER_TESTING_Interpreter *is)
{
  struct TALER_EXCHANGE_Keys *keys;
  const struct TALER_TESTING_Command *exchange_cmd;

  exchange_cmd
    = TALER_TESTING_interpreter_get_command (is,
                                             "exchange");
  if (NULL == exchange_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return NULL;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_keys (exchange_cmd,
                                    &keys))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return NULL;
  }
  return keys;
}


/* end of testing_api_traits.c */
