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


/**
 * State for a "check keys" CMD.
 */
struct CheckKeysState
{

  /**
   * If this value is true, then the "cherry picking" facility is turned off;
   * whole /keys is downloaded.
   */
  bool pull_all_keys;

  /**
   * Label of a command to use to derive the "last_denom_issue" date to use.
   */
  const char *last_denom_date_ref;

  /**
   * Our interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

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
         const struct TALER_EXCHANGE_KeysResponse *kr)
{
  struct CheckKeysState *cks = cls;

  if (MHD_HTTP_OK != kr->hr.http_status)
  {
    TALER_TESTING_unexpected_status (cks->is,
                                     kr->hr.http_status);
    return;
  }
  cks->my_denom_date = kr->details.ok.keys->last_denom_issue_date;
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
  struct TALER_EXCHANGE_Handle *exchange
    = TALER_TESTING_get_exchange (is);
  struct GNUNET_TIME_Timestamp rdate;

  (void) cmd;
  cks->is = is;
  if (NULL == exchange)
    return;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Triggering GET /keys, cmd `%s'\n",
              cmd->label);
  if (NULL != cks->last_denom_date_ref)
  {
    if (0 == strcmp ("zero",
                     cks->last_denom_date_ref))
    {
      TALER_LOG_DEBUG ("Forcing last_denom_date URL argument set to zero\n");
      TALER_EXCHANGE_set_last_denom (exchange,
                                     GNUNET_TIME_UNIT_ZERO_TS);
    }
    else
    {
      const struct GNUNET_TIME_Timestamp *last_denom_date;
      const struct TALER_TESTING_Command *ref;

      ref = TALER_TESTING_interpreter_lookup_command (is,
                                                      cks->last_denom_date_ref);
      if (NULL == ref)
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      if (GNUNET_OK !=
          TALER_TESTING_get_trait_timestamp (ref,
                                             0,
                                             &last_denom_date))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }

      TALER_LOG_DEBUG ("Forcing last_denom_date URL argument\n");
      TALER_EXCHANGE_set_last_denom (exchange,
                                     *last_denom_date);
    }
  }

  rdate = TALER_EXCHANGE_check_keys_current (
    exchange,
    cks->pull_all_keys
      ? TALER_EXCHANGE_CKF_FORCE_ALL_NOW
    : TALER_EXCHANGE_CKF_FORCE_DOWNLOAD,
    &keys_cb,
    cks);
  /* Redownload /keys.  */
  GNUNET_break (GNUNET_TIME_absolute_is_zero (rdate.abs_time));
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
  struct CheckKeysState *cks;

  cks = GNUNET_new (struct CheckKeysState);
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


struct TALER_TESTING_Command
TALER_TESTING_cmd_check_keys_pull_all_keys (const char *label)
{
  struct TALER_TESTING_Command cmd
    = TALER_TESTING_cmd_check_keys (label);
  struct CheckKeysState *cks = cmd.cls;

  cks->pull_all_keys = true;
  return cmd;
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_check_keys_with_last_denom (
  const char *label,
  const char *last_denom_date_ref)
{
  struct TALER_TESTING_Command cmd
    = TALER_TESTING_cmd_check_keys (label);
  struct CheckKeysState *cks = cmd.cls;

  cks->last_denom_date_ref = last_denom_date_ref;
  return cmd;
}


/* end of testing_api_cmd_check_keys.c */
