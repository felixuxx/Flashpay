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
 * @file testing/testing_api_cmd_signal.c
 * @brief command(s) to send signals to processes.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"


/**
 * State for a "signal" CMD.
 */
struct SignalState
{
  /**
   * The process to send the signal to.
   */
  struct GNUNET_OS_Process *process;

  /**
   * The signal to send to the process.
   */
  int signal;
};

/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
signal_run (void *cls,
            const struct TALER_TESTING_Command *cmd,
            struct TALER_TESTING_Interpreter *is)
{
  struct SignalState *ss = cls;

  GNUNET_break (0 == GNUNET_OS_process_kill
                  (ss->process, ss->signal));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Signaling '%d'..\n",
              ss->signal);
  TALER_TESTING_interpreter_next (is);
}


/**
 * Cleanup the state from a "signal" CMD.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
signal_cleanup (void *cls,
                const struct TALER_TESTING_Command *cmd)
{
  struct SignalState *ss = cls;

  GNUNET_free (ss);
}


/**
 * Create a "signal" CMD.
 *
 * @param label command label.
 * @param process handle to the process to signal.
 * @param signal signal to send.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_signal (const char *label,
                          struct GNUNET_OS_Process *process,
                          int signal)
{
  struct SignalState *ss;

  ss = GNUNET_new (struct SignalState);
  ss->process = process;
  ss->signal = signal;

  {
    struct TALER_TESTING_Command cmd = {
      .cls = ss,
      .label = label,
      .run = &signal_run,
      .cleanup = &signal_cleanup
    };

    return cmd;
  }
}
