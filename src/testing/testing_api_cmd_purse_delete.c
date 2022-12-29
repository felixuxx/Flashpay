/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 3, or (at your
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
 * @file testing/testing_api_cmd_purse_delete.c
 * @brief command for testing /management/purse/disable.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"


/**
 * State for a "purse_delete" CMD.
 */
struct PurseDeleteState
{

  /**
   * Purse delete handle while operation is running.
   */
  struct TALER_EXCHANGE_PurseDeleteHandle *pdh;

  /**
   * Our interpreter.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Command that created the purse we now want to
   * delete.
   */
  const char *purse_cmd;
};


/**
 * Callback to analyze the DELETE /purses/$PID response, just used to check if
 * the response code is acceptable.
 *
 * @param cls closure.
 * @param pdr HTTP response details
 */
static void
purse_delete_cb (void *cls,
                 const struct TALER_EXCHANGE_PurseDeleteResponse *pdr)
{
  struct PurseDeleteState *pds = cls;

  pds->pdh = NULL;
  if (pds->expected_response_code != pdr->hr.http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u to command %s in %s:%u\n",
                pdr->hr.http_status,
                pds->is->commands[pds->is->ip].label,
                __FILE__,
                __LINE__);
    json_dumpf (pdr->hr.reply,
                stderr,
                0);
    TALER_TESTING_interpreter_fail (pds->is);
    return;
  }
  TALER_TESTING_interpreter_next (pds->is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
purse_delete_run (void *cls,
                  const struct TALER_TESTING_Command *cmd,
                  struct TALER_TESTING_Interpreter *is)
{
  struct PurseDeleteState *pds = cls;
  const struct TALER_PurseContractPrivateKeyP *purse_priv;
  const struct TALER_TESTING_Command *ref;

  (void) cmd;
  ref = TALER_TESTING_interpreter_lookup_command (is,
                                                  pds->purse_cmd);
  if (NULL == ref)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_purse_priv (ref,
                                          &purse_priv))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  pds->is = is;
  pds->pdh = TALER_EXCHANGE_purse_delete (
    is->exchange,
    purse_priv,
    &purse_delete_cb,
    pds);
  if (NULL == pds->pdh)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "purse_delete" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct PurseDeleteState`.
 * @param cmd the command which is being cleaned up.
 */
static void
purse_delete_cleanup (void *cls,
                      const struct TALER_TESTING_Command *cmd)
{
  struct PurseDeleteState *pds = cls;

  if (NULL != pds->pdh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                pds->is->ip,
                cmd->label);
    TALER_EXCHANGE_purse_delete_cancel (pds->pdh);
    pds->pdh = NULL;
  }
  GNUNET_free (pds);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_purse_delete (const char *label,
                                unsigned int expected_http_status,
                                const char *purse_cmd)
{
  struct PurseDeleteState *ds;

  ds = GNUNET_new (struct PurseDeleteState);
  ds->expected_response_code = expected_http_status;
  ds->purse_cmd = purse_cmd;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ds,
      .label = label,
      .run = &purse_delete_run,
      .cleanup = &purse_delete_cleanup
    };

    return cmd;
  }
}


/* end of testing_api_cmd_purse_delete.c */
