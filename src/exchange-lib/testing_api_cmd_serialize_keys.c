/*
  This file is part of TALER
  (C) 2018 Taler Systems SA

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
 * @file exchange-lib/testing_api_cmd_serialize_keys.c
 * @brief Lets tests use the keys serialization API.
 * @author Marcello Stanisci
 */

#include "platform.h"
#include <jansson.h>
#include "exchange_api_handle.h"
#include "taler_testing_lib.h"


/**
 * Internal state for a serialize-keys CMD.
 */
struct SerializeKeysState
{
  /**
   * Serialized keys.
   */
  json_t *keys;
};


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
serialize_keys_run (void *cls,
                    const struct TALER_TESTING_Command *cmd,
                    struct TALER_TESTING_Interpreter *is)
{
  struct SerializeKeysState *sks = cls;

  sks->keys = TALER_EXCHANGE_serialize_data (is->exchange);

  if (NULL == sks->keys)
    TALER_TESTING_interpreter_fail (is);
}


/**
 * Cleanup the state of a "serialize keys" CMD.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
void
serialize_keys_cleanup (void *cls,
                        const struct TALER_TESTING_Command *cmd)
{
  struct SerializeKeysState *sks = cls;

  if (NULL != sks->keys)
  {
    json_decref (sks->keys);   
  }

  GNUNET_free (sks);
}


/**
 * Offer serialized keys as trait.
 *
 * @param cls closure.
 * @param ret[out] result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 *
 * @return #GNUNET_OK on success.
 */
static int
serialize_keys_traits (void *cls,
                       const void **ret,
                       const char *trait,
                       unsigned int index)
{
  struct SerializeKeysState *sks = cls;

  struct TALER_TESTING_Trait traits[] = {

    TALER_TESTING_make_trait_exchange_keys (0,
                                            sks->keys),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}

/**
 * Make a serialize-keys CMD.
 *
 * @param label CMD label
 * @return the CMD.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_serialize_keys (const char *label)
{
  struct SerializeKeysState *sks;

  sks = GNUNET_new (struct SerializeKeysState);
  struct TALER_TESTING_Command cmd = {
    .cls = sks,
    .label = label,
    .run = serialize_keys_run,
    .cleanup = serialize_keys_cleanup,
    .traits = serialize_keys_traits  
  };

  return cmd;
}
