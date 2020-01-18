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
 * @file lib/testing_api_cmd_sleep.c
 * @brief command(s) to sleep for a bit
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_testing_lib.h"


/**
 * State for a "sleep" CMD.
 */
struct SleepState
{

  /**
   * How long should we sleep?
   */
  unsigned int duration;
};


/**
 * No traits to offer, just provide a stub to be called when
 * some CMDs iterates through the list of all the commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the trait to return.
 * @return #GNUNET_OK on success.
 */
static int
sleep_traits (void *cls,
              const void **ret,
              const char *trait,
              unsigned int index)
{
  (void) cls;
  (void) ret;
  (void) trait;
  (void) index;
  return GNUNET_NO;
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
sleep_run (void *cls,
           const struct TALER_TESTING_Command *cmd,
           struct TALER_TESTING_Interpreter *is)
{
  struct SleepState *ss = cls;

  sleep (ss->duration);
  TALER_TESTING_interpreter_next (is);
}


/**
 * Cleanup the state from a "sleep" CMD.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
sleep_cleanup (void *cls,
               const struct TALER_TESTING_Command *cmd)
{
  struct SleepState *ss = cls;

  (void) cmd;
  GNUNET_free (ss);
}


/**
 * Sleep for @a duration_s seconds.
 *
 * @param label command label.
 * @param duration_s number of seconds to sleep
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_sleep (const char *label,
                         unsigned int duration_s)
{
  struct SleepState *ss;

  ss = GNUNET_new (struct SleepState);
  ss->duration = duration_s;

  {
    struct TALER_TESTING_Command cmd = {
      .cls = ss,
      .label = label,
      .run = &sleep_run,
      .cleanup = &sleep_cleanup,
      .traits = &sleep_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_sleep.c  */
