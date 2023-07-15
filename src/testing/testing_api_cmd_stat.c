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
 * Run a "stat" CMD.
 *
 * @param cls closure.
 * @param cmd the command being run.
 * @param is the interpreter state.
 */
static void
stat_run (void *cls,
          const struct TALER_TESTING_Command *cmd,
          struct TALER_TESTING_Interpreter *is);


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

  if (GNUNET_TIME_absolute_cmp (cmd->start_time,
                                >,
                                cmd->finish_time))
  {
    /* This is a problem, except of course for
       this command itself, as we clearly did not yet
       finish... */
    if (cmd->run != &stat_run)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Bad timings for `%s'\n",
                  cmd->label);
      GNUNET_break (0);
    }
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
 * @param[in,out] cls what timings to get
 * @param cmd command to process
 */
static void
do_stat (void *cls,
         const struct TALER_TESTING_Command *cmd)
{
  struct TALER_TESTING_Timer *timings = cls;

  if (TALER_TESTING_cmd_is_batch (cmd))
  {
    struct TALER_TESTING_Command *bcmd;

    if (GNUNET_OK !=
        TALER_TESTING_get_trait_batch_cmds (cmd,
                                            &bcmd))
    {
      GNUNET_break (0);
      return;
    }
    for (unsigned int j = 0;
         NULL != bcmd[j].label;
         j++)
      do_stat (timings,
               &bcmd[j]);
    return;
  }
  stat_cmd (timings,
            cmd);
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

  TALER_TESTING_iterate (is,
                         true,
                         &do_stat,
                         timings);
  TALER_TESTING_interpreter_next (is);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_stat (struct TALER_TESTING_Timer *timers)
{
  struct TALER_TESTING_Command cmd = {
    .label = "stat",
    .run = &stat_run,
    .cls = (void *) timers
  };

  return cmd;
}


/* end of testing_api_cmd_stat.c  */
