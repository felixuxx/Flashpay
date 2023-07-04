/*
  This file is part of TALER
  (C) 2018-2023 Taler Systems SA

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
 * @file testing/testing_api_cmd_serialize_keys.c
 * @brief Lets tests use the keys serialization API.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include <jansson.h>
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

  /**
   * Exchange URL.  Needed because the exchange gets disconnected
   * from, after keys serialization.  This value is then needed by
   * subsequent commands that have to reconnect to the exchange.
   */
  char *exchange_url;
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
  struct TALER_EXCHANGE_Keys *keys
    = TALER_TESTING_get_keys (is);

  if (NULL == keys)
    return;
  sks->keys = TALER_EXCHANGE_keys_to_json (keys);
  if (NULL == sks->keys)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
  }
  sks->exchange_url
    = GNUNET_strdup (
        TALER_TESTING_get_exchange_url (is));
  TALER_TESTING_interpreter_next (is);
}


/**
 * Cleanup the state of a "serialize keys" CMD.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
serialize_keys_cleanup (void *cls,
                        const struct TALER_TESTING_Command *cmd)
{
  struct SerializeKeysState *sks = cls;

  if (NULL != sks->keys)
    json_decref (sks->keys);
  GNUNET_free (sks->exchange_url);
  GNUNET_free (sks);
}


/**
 * Offer serialized keys as trait.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
serialize_keys_traits (void *cls,
                       const void **ret,
                       const char *trait,
                       unsigned int index)
{
  struct SerializeKeysState *sks = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_exchange_keys (sks->keys),
    TALER_TESTING_make_trait_exchange_url (sks->exchange_url),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_serialize_keys (const char *label)
{
  struct SerializeKeysState *sks;

  sks = GNUNET_new (struct SerializeKeysState);
  {
    struct TALER_TESTING_Command cmd = {
      .cls = sks,
      .label = label,
      .run = serialize_keys_run,
      .cleanup = serialize_keys_cleanup,
      .traits = serialize_keys_traits
    };

    return cmd;
  }
}
