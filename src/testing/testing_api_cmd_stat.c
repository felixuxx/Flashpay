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
 * @file testing/testing_api_cmd_stat.c
 * @brief command(s) to get performance statistics on other commands
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"


/**
 * Cleanup the state from a "stat service" CMD.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
stat_cleanup (void *cls,
              const struct TALER_TESTING_Command *cmd)
{
  (void) cls;
  (void) cmd;
  /* nothing to clean.  */
}


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
stat_traits (void *cls,
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
 * Add the time @a cmd took to the respective duration in @a timings.
 *
 * @param timings where to add up times
 * @param cmd command to evaluate
 */
static void
stat_cmd (struct TALER_TESTING_Timer *timings,
          const struct TALER_TESTING_Command *cmd)
{
  struct GNUNET_TIME_Relative duration;
  struct GNUNET_TIME_Relative lat;

  if (cmd->start_time.abs_value_us > cmd->finish_time.abs_value_us)
  {
    GNUNET_break (0);
    return;
  }
  duration = GNUNET_TIME_absolute_get_difference (cmd->start_time,
                                                  cmd->finish_time);
  lat = GNUNET_TIME_absolute_get_difference (cmd->last_req_time,
                                             cmd->finish_time);
  for (unsigned int i = 0;
       NULL != timings[i].prefix;
       i++)
  {
    if (0 == strncmp (timings[i].prefix,
                      cmd->label,
                      strlen (timings[i].prefix)))
    {
      timings[i].total_duration
        = GNUNET_TIME_relative_add (duration,
                                    timings[i].total_duration);
      timings[i].success_latency
        = GNUNET_TIME_relative_add (lat,
                                    timings[i].success_latency);
      timings[i].num_commands++;
      timings[i].num_retries += cmd->num_tries;
      break;
    }
  }
}


/**
 * Obtain statistics for @a timings of @a cmd
 *
 * @param timings what timings to get
 * @param cmd command to process
 */
static void
do_stat (struct TALER_TESTING_Timer *timings,
         const struct TALER_TESTING_Command *cmd)
{
  if (TALER_TESTING_cmd_is_batch (cmd))
  {
#define BATCH_INDEX 1
    struct TALER_TESTING_Command *bcmd;

    if (GNUNET_OK !=
        TALER_TESTING_get_trait_cmd (cmd,
                                     BATCH_INDEX,
                                     &bcmd))
    {
      GNUNET_break (0);
      return;
    }

    for (unsigned int j = 0; NULL != bcmd[j].label; j++)
      do_stat (timings,
               &bcmd[j]);
  }
  else
  {
    stat_cmd (timings,
              cmd);
  }
}


/**
 * Run a "stat" CMD.
 *
 * @param cls closure.
 * @param cmd the command being run.
 * @param is the interpreter state.
 */
static void
stat_run (void *cls,
          const struct TALER_TESTING_Command *cmd,
          struct TALER_TESTING_Interpreter *is)
{
  struct TALER_TESTING_Timer *timings = cls;

  for (unsigned int i = 0; NULL != is->commands[i].label; i++)
  {
    if (cmd == &is->commands[i])
      break; /* skip at our current command */
    do_stat (timings,
             &is->commands[i]);
  }
  TALER_TESTING_interpreter_next (is);
}


/**
 * Obtain performance data from the interpreter.
 *
 * @param timers what commands (by label) to obtain runtimes for
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_stat (struct TALER_TESTING_Timer *timers)
{
  struct TALER_TESTING_Command cmd = {
    .label = "stat",
    .run = stat_run,
    .cleanup = stat_cleanup,
    .traits = stat_traits,
    .cls = (void *) timers
  };

  return cmd;
}


/* end of testing_api_cmd_sleep.c  */
