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
 * @file testing/testing_api_cmd_connect_with_state.c
 * @brief Lets tests use the keys deserialization API.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include <jansson.h>
#include "taler_testing_lib.h"


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
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * New exchange handle.
   */
  struct TALER_EXCHANGE_Handle *exchange;
};


static void
cert_cb (void *cls,
         const struct TALER_EXCHANGE_KeysResponse *kr)
{
  struct ConnectWithStateState *cwss = cls;
  struct TALER_TESTING_Interpreter *is = cwss->is;
  const struct TALER_EXCHANGE_HttpResponse *hr = &kr->hr;

  switch (hr->http_status)
  {
  case MHD_HTTP_OK:
    /* dealt with below */
    break;
  default:
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Got failure response %u/%d for /keys!\n",
                hr->http_status,
                (int) hr->ec);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Got %d DK from /keys\n",
              kr->details.ok.keys->num_denom_keys);
  TALER_TESTING_interpreter_next (is);
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

  cwss->is = is;
  state_cmd = TALER_TESTING_interpreter_lookup_command (is,
                                                        cwss->state_reference);
  if (NULL == state_cmd)
  {
    /* Command providing serialized keys not found.  */
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_exchange_keys (state_cmd,
                                                        &serialized_keys));
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_exchange_url (state_cmd,
                                                       &exchange_url));
  cwss->exchange
    = TALER_EXCHANGE_connect (
        TALER_TESTING_interpreter_get_context (is),
        exchange_url,
        &cert_cb,
        cwss,
        TALER_EXCHANGE_OPTION_DATA,
        serialized_keys,
        TALER_EXCHANGE_OPTION_END);
}


/**
 * Offer exchange connection as trait.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
connect_with_state_traits (void *cls,
                           const void **ret,
                           const char *trait,
                           unsigned int index)
{
  struct ConnectWithStateState *cwss = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_exchange (cwss->exchange),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
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


struct TALER_TESTING_Command
TALER_TESTING_cmd_connect_with_state (const char *label,
                                      const char *state_reference)
{
  struct ConnectWithStateState *cwss;

  cwss = GNUNET_new (struct ConnectWithStateState);
  cwss->state_reference = state_reference;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = cwss,
      .label = label,
      .run = connect_with_state_run,
      .cleanup = connect_with_state_cleanup,
      .traits = connect_with_state_traits
    };

    return cmd;
  }
}
