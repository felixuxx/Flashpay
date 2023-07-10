/*
  This file is part of TALER
  (C) 2018, 2020, 2021 Taler Systems SA

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
 * @file testing/testing_api_cmd_check_keys.c
 * @brief Implementation of "check keys" test command.
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"

// FIXME: duplicated with testing_api_cmd_connect_with_state
// FIXME: this is now duplicated with testing_api_cmd_get_exchange!

/**
 * State for a "check keys" CMD.
 */
struct CheckKeysState
{

  /**
   * Label of a command to use to derive the "last_denom_issue" date to use.
   * FIXME: actually use this!
   */
  const char *last_denom_date_ref;

  /**
   * Our interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Our get keys operation.
   */
  struct TALER_EXCHANGE_GetKeysHandle *gkh;

  /**
   * Last denomination date we received when doing this request.
   */
  struct GNUNET_TIME_Timestamp my_denom_date;
};


/**
 * Function called with information about who is auditing
 * a particular exchange and what keys the exchange is using.
 *
 * @param cls closure
 * @param kr response from /keys
 */
static void
keys_cb (void *cls,
         const struct TALER_EXCHANGE_KeysResponse *kr,
         struct TALER_EXCHANGE_Keys *keys)
{
  struct CheckKeysState *cks = cls;

  cks->gkh = NULL;
  if (MHD_HTTP_OK != kr->hr.http_status)
  {
    TALER_TESTING_unexpected_status (cks->is,
                                     kr->hr.http_status,
                                     MHD_HTTP_OK);
    return;
  }
  cks->my_denom_date = kr->details.ok.keys->last_denom_issue_date;
  /* FIXME: expose keys (and exchange_url) via trait! */
  TALER_EXCHANGE_keys_decref (keys);
  TALER_TESTING_interpreter_next (cks->is);
}


/**
 * Run the "check keys" command.
 *
 * @param cls closure.
 * @param cmd the command currently being executed.
 * @param is the interpreter state.
 */
static void
check_keys_run (void *cls,
                const struct TALER_TESTING_Command *cmd,
                struct TALER_TESTING_Interpreter *is)
{
  struct CheckKeysState *cks = cls;
  const char *exchange_url
    = TALER_TESTING_get_exchange_url (is);

  cks->is = is;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Triggering GET /keys, cmd `%s'\n",
              cmd->label);
  cks->gkh = TALER_EXCHANGE_get_keys (
    TALER_TESTING_interpreter_get_context (is),
    exchange_url,
    NULL, /* FIXME: get form last_denom_date_ref! */
    &keys_cb,
    cks);
}


/**
 * Cleanup the state.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
check_keys_cleanup (void *cls,
                    const struct TALER_TESTING_Command *cmd)
{
  struct CheckKeysState *cks = cls;

  (void) cmd;
  if (NULL != cks->gkh)
  {
    TALER_EXCHANGE_get_keys_cancel (cks->gkh);
    cks->gkh = NULL;
  }
  GNUNET_free (cks);
}


/**
 * Offer internal data to a "check_keys" CMD state to other
 * commands.
 *
 * @param cls closure
 * @param[out] ret result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
check_keys_traits (void *cls,
                   const void **ret,
                   const char *trait,
                   unsigned int index)
{
  struct CheckKeysState *cks = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_timestamp (0,
                                        &cks->my_denom_date),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_check_keys (const char *label)
{
  return TALER_TESTING_cmd_check_keys_with_last_denom (label,
                                                       NULL);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_check_keys_with_last_denom (
  const char *label,
  const char *last_denom_date_ref)
{
  struct CheckKeysState *cks;

  cks = GNUNET_new (struct CheckKeysState);
  cks->last_denom_date_ref = last_denom_date_ref;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = cks,
      .label = label,
      .run = &check_keys_run,
      .cleanup = &check_keys_cleanup,
      .traits = &check_keys_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_check_keys.c */
