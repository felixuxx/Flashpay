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
 * @file lib/testing_api_cmd_serialize_keys.c
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

  /**
   * Exchange URL.  Needed because the exchange gets disconnected
   * from, after keys serialization.  This value is then needed by
   * subsequent commands that have to reconnect to the exchagne.
   */
  char *exchange_url;
};


/**
 * Internal state for a connect-with-state CMD.
 */
struct ConnectWithStateState
{

  /**
   * Reference to a CMD that offers a serialized key-state
   * that will be used in the reconnection.
   */
  const char *state_reference;

  /**
   * If set to GNUNET_YES, then the /keys callback has already
   * been passed the control to the next CMD.  This is necessary
   * because it is not uncommon that the /keys callback gets
   * invoked multiple times, and without this flag, we would keep
   * going "next" CMD upon every invocation (causing impredictable
   * behaviour as for the instruction pointer.)
   */
  unsigned int consumed;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;
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

  sks->exchange_url = GNUNET_strdup
                        (TALER_EXCHANGE_get_base_url (is->exchange));
  TALER_EXCHANGE_disconnect (is->exchange);
  is->exchange = NULL;
  is->working = GNUNET_NO;
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
  {
    json_decref (sks->keys);
  }
  GNUNET_free_non_null (sks->exchange_url);
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
    TALER_TESTING_make_trait_exchange_keys (0, sks->keys),
    TALER_TESTING_make_trait_url (TALER_TESTING_UT_EXCHANGE_BASE_URL,
                                  sks->exchange_url),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
connect_with_state_run (void *cls,
                        const struct TALER_TESTING_Command *cmd,
                        struct TALER_TESTING_Interpreter *is)
{
  struct ConnectWithStateState *cwss = cls;
  const struct TALER_TESTING_Command *state_cmd;
  const json_t *serialized_keys;
  const char *exchange_url;

  /* This command usually gets rescheduled after serialized
   * reconnection.  */
  if (GNUNET_YES == cwss->consumed)
  {
    TALER_TESTING_interpreter_next (is);
    return;
  }

  cwss->is = is;
  state_cmd = TALER_TESTING_interpreter_lookup_command
                (is, cwss->state_reference);

  /* Command providing serialized keys not found.  */
  if (NULL == state_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_exchange_keys (state_cmd,
                                                        0,
                                                        &serialized_keys));
  {
    char *dump;

    dump = json_dumps (serialized_keys,
                       JSON_INDENT (1));
    TALER_LOG_DEBUG ("Serialized key-state: %s\n",
                     dump);
    free (dump);
  }

  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_url (state_cmd,
                                              TALER_TESTING_UT_EXCHANGE_BASE_URL,
                                              &exchange_url));
  is->exchange = TALER_EXCHANGE_connect (is->ctx,
                                         exchange_url,
                                         TALER_TESTING_cert_cb,
                                         cwss,
                                         TALER_EXCHANGE_OPTION_DATA,
                                         serialized_keys,
                                         TALER_EXCHANGE_OPTION_END);
  cwss->consumed = GNUNET_YES;
}


/**
 * Cleanup the state of a "connect with state" CMD.  Just
 * a placeholder to avoid jumping on an invalid address.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
connect_with_state_cleanup (void *cls,
                            const struct TALER_TESTING_Command *cmd)
{
  struct ConnectWithStateState *cwss = cls;

  GNUNET_free (cwss);
}


/**
 * Make a serialize-keys CMD.  It will ask for
 * keys serialization __and__ disconnect from the
 * exchange.
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


/**
 * Make a connect-with-state CMD.  This command
 * will use a serialized key state to reconnect
 * to the exchange.
 *
 * @param label command label
 * @param state_reference label of a CMD offering
 *        a serialized key state.
 * @return the CMD.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_connect_with_state (const char *label,
                                      const char *state_reference)
{
  struct ConnectWithStateState *cwss;

  cwss = GNUNET_new (struct ConnectWithStateState);
  cwss->state_reference = state_reference;
  cwss->consumed = GNUNET_NO;

  struct TALER_TESTING_Command cmd = {
    .cls = cwss,
    .label = label,
    .run = connect_with_state_run,
    .cleanup = connect_with_state_cleanup
  };

  return cmd;
}
