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
 * @file lib/testing_api_cmd_check_keys.c
 * @brief Implementation of "check keys" test command.  XXX-NOTE:
 *        the number of 'expected keys' is NOT the number of the
 *        downloaded keys, but rather the number of keys that the
 *        libtalerutil library keeps locally.  As for the current
 *        design, keys are _never_ discarded by the library,
 *        therefore their (expected) number is monotonically
 *        ascending.
 *
 * @author Marcello Stanisci
 */

#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_testing_lib.h"


/**
 * State for a "check keys" CMD.
 */
struct CheckKeysState
{
  /**
   * This number will instruct the CMD interpreter to
   * make sure that /keys was downloaded `generation` times
   * _before_ running the very CMD logic.
   */
  unsigned int generation;

  /**
   * How many denomination keys the exchange is
   * supposed to have.
   */
  unsigned int num_denom_keys;

  /**
   * If this value is GNUNET_YES, then the "cherry
   * picking" facility is turned off; whole /keys is
   * downloaded.
   */
  unsigned int pull_all_keys;

  /**
   * If GNUNET_YES, then the user must specify the
   * last_denom_issue_date manually.  This way, it is possible
   * to force whatever X value here (including 0): /keys?last_denom_issue=X.
   */
  unsigned int set_last_denom;

  /**
   * Value X to set as the URL parameter:
   * "/keys?last_denom_issue=X" is used only when `set_last_denom'
   * equals GNUNET_YES.
   */
  struct GNUNET_TIME_Absolute last_denom_date;

  /**
   * If GNUNET_YES, then we'll provide the "/keys" request.
   * with the "now" argument.
   */
  int with_now;

  /**
   * Fake now as passed by the user.
   */
  struct GNUNET_TIME_Absolute now;

};


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

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "cmd `%s' (ip: %u), key generation: %d\n",
              cmd->label,
              is->ip,
              is->key_generation);

  if (is->key_generation < cks->generation)
  {
    is->working = GNUNET_NO;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Triggering GET /keys, cmd `%s'\n",
                cmd->label);

    if (GNUNET_YES == cks->set_last_denom)
    {
      TALER_LOG_DEBUG ("Forcing last_denom_date URL argument\n");
      TALER_EXCHANGE_set_last_denom (is->exchange,
                                     cks->last_denom_date);
    }

    if (GNUNET_YES == cks->with_now)
      TALER_EXCHANGE_set_now (is->exchange,
                              cks->now);
    /* Redownload /keys.  */
    GNUNET_break
      (0 == TALER_EXCHANGE_check_keys_current
        (is->exchange,
        GNUNET_YES,
        cks->pull_all_keys).abs_value_us);
    return;
  }

#if 0
  /**
   * Not sure this check makes sense: GET /keys is performed on
   * a "maybe" basis, so it can get quite hard to track /keys
   * request.  Rather, this CMD should just check if /keys was
   * requested AT LEAST n times before going ahead with checks.
   */if (is->key_generation > cks->generation)
  {
    /* We got /keys too often, strange. Fatal. May theoretically
       happen if somehow we were really unlucky and /keys expired
       "naturally", but obviously with a sane configuration this
       should also not be. */
    GNUNET_break (0);
    TALER_LOG_ERROR ("Acutal- vs expected key"
                     " generation: %u vs %u\n",
                     is->key_generation,
                     cks->generation);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
#endif
  /* "/keys" was updated, let's check they were OK! */
  if (cks->num_denom_keys != is->keys->num_denom_keys)
  {
    /* Did not get the expected number of denomination keys! */
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Got %u keys in step %s, expected %u\n",
                is->keys->num_denom_keys,
                cmd->label,
                cks->num_denom_keys);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  /* Let's unset the fake now before moving on.  */
  TALER_EXCHANGE_unset_now (is->exchange);
  TALER_TESTING_interpreter_next (is);
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

  GNUNET_free (cks);
}


/**
 * Make a "check keys" command.  This type of command
 * checks whether the number of denomination keys from
 * @a exchange matches @a num_denom_keys.  Additionally,
 * it lets the user set a last denom issue date to be
 * used in the request for /keys.
 *
 * @param label command label
 * @param generation when this command is run, exactly @a
 *        generation /keys downloads took place.  If the number
 *        of downloads is less than @a generation, the logic will
 *        first make sure that @a generation downloads are done,
 *        and _then_ execute the rest of the command.
 * @param num_denom_keys expected number of denomination keys.
 * @param exchange connection handle to the exchange to test.
 * @param last_denom_date date to be set in the "last_denom_issue"
 *        URL parameter of /keys.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_keys_with_last_denom
  (const char *label,
  unsigned int generation,
  unsigned int num_denom_keys,
  struct GNUNET_TIME_Absolute last_denom_date)
{
  struct CheckKeysState *cks;

  cks = GNUNET_new (struct CheckKeysState);
  cks->generation = generation;
  cks->num_denom_keys = num_denom_keys;
  cks->set_last_denom = GNUNET_YES;
  cks->last_denom_date = last_denom_date;

  struct TALER_TESTING_Command cmd = {
    .cls = cks,
    .label = label,
    .run = &check_keys_run,
    .cleanup = &check_keys_cleanup
  };

  return cmd;
}


/**
 * Make a "check keys" command.  This type of command
 * checks whether the number of denomination keys from
 * @a exchange matches @a num_denom_keys.
 *
 * @param label command label
 * @param generation when this command is run, exactly @a
 *        generation /keys downloads took place.  If the number
 *        of downloads is less than @a generation, the logic will
 *        first make sure that @a generation downloads are done,
 *        and _then_ execute the rest of the command.
 * @param num_denom_keys expected number of denomination keys.
 * @param exchange connection handle to the exchange to test.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_keys
  (const char *label,
  unsigned int generation,
  unsigned int num_denom_keys)
{
  struct CheckKeysState *cks;

  cks = GNUNET_new (struct CheckKeysState);
  cks->generation = generation;
  cks->num_denom_keys = num_denom_keys;

  struct TALER_TESTING_Command cmd = {
    .cls = cks,
    .label = label,
    .run = &check_keys_run,
    .cleanup = &check_keys_cleanup
  };

  return cmd;
}


/**
 * Make a "check keys" command.  This type of command
 * checks whether the number of denomination keys from
 * @a exchange matches @a num_denom_keys.
 *
 * @param label command label
 * @param generation when this command is run, exactly @a
 *        generation /keys downloads took place.  If the number
 *        of downloads is less than @a generation, the logic will
 *        first make sure that @a generation downloads are done,
 *        and _then_ execute the rest of the command.
 * @param num_denom_keys expected number of denomination keys.
 * @param exchange connection handle to the exchange to test.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_keys_with_now
  (const char *label,
  unsigned int generation,
  unsigned int num_denom_keys,
  struct GNUNET_TIME_Absolute now)
{
  struct CheckKeysState *cks;

  cks = GNUNET_new (struct CheckKeysState);
  cks->generation = generation;
  cks->num_denom_keys = num_denom_keys;
  cks->now = now;
  cks->with_now = GNUNET_YES;

  /* Force to NOT cherry pick, otherwise they conflict.  */
  cks->pull_all_keys = GNUNET_YES;

  struct TALER_TESTING_Command cmd = {
    .cls = cks,
    .label = label,
    .run = &check_keys_run,
    .cleanup = &check_keys_cleanup
  };

  return cmd;
}


/**
 * Make a "check keys" command that forcedly does NOT cherry pick;
 * just redownload the whole /keys.  Then checks whether the number
 * of denomination keys from @a exchange matches @a num_denom_keys.
 *
 * @param label command label
 * @param generation when this command is run, exactly @a
 *        generation /keys downloads took place.  If the number
 *        of downloads is less than @a generation, the logic will
 *        first make sure that @a generation downloads are done,
 *        and _then_ execute the rest of the command.
 * @param num_denom_keys expected number of denomination keys.
 * @param exchange connection handle to the exchange to test.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_keys_pull_all_keys
  (const char *label,
  unsigned int generation,
  unsigned int num_denom_keys)
{
  struct CheckKeysState *cks;

  cks = GNUNET_new (struct CheckKeysState);
  cks->generation = generation;
  cks->num_denom_keys = num_denom_keys;
  cks->pull_all_keys = GNUNET_YES;

  struct TALER_TESTING_Command cmd = {
    .cls = cks,
    .label = label,
    .run = &check_keys_run,
    .cleanup = &check_keys_cleanup
  };

  return cmd;
}


/* end of testing_api_cmd_check_keys.c */
