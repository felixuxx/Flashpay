/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file exchange-lib/testing_api_cmd_exec_wirewatch.c
 * @brief run the taler-exchange-wirewatch command
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"


struct WirewatchState
{

  /**
   * Process for the wirewatcher.
   */
  struct GNUNET_OS_Process *wirewatch_proc;

  /**
   * Which configuration file should we pass to the process?
   */
  const char *config_filename;

};


/**
 * Runs the command.  Note that upon return, the interpreter
 * will not automatically run the next command, as the command
 * may continue asynchronously in other scheduler tasks.  Thus,
 * the command must ensure to eventually call
 * #TALER_TESTING_interpreter_next() or
 * #TALER_TESTING_interpreter_fail().
 *
 * @param is interpreter state
 */
static void
wirewatch_run (void *cls,
              const struct TALER_TESTING_Command *cmd,
              struct TALER_TESTING_Interpreter *is)
{
  struct WirewatchState *ws = cls;

  ws->wirewatch_proc
    = GNUNET_OS_start_process (GNUNET_NO,
                               GNUNET_OS_INHERIT_STD_ALL,
                               NULL, NULL, NULL,
                               "taler-exchange-wirewatch",
                               "taler-exchange-wirewatch",
                               "-c", ws->config_filename,
                               "-t", "test", /* use Taler's bank/fakebank */
                               "-T", /* exit when done */
                               NULL);
  if (NULL == ws->wirewatch_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Clean up after the command.  Run during forced termination
 * (CTRL-C) or test failure or test success.
 *
 * @param cls closure
 */
static void
wirewatch_cleanup (void *cls,
                   const struct TALER_TESTING_Command *cmd)
{
  struct WirewatchState *ws = cls;

  if (NULL != ws->wirewatch_proc)
  {
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (ws->wirewatch_proc,
                                          SIGKILL));
    GNUNET_OS_process_wait (ws->wirewatch_proc);
    GNUNET_OS_process_destroy (ws->wirewatch_proc);
    ws->wirewatch_proc = NULL;
  }
  GNUNET_free (ws);
}


/**
 * Extract information from a command that is useful for other
 * commands.
 *
 * @param cls closure
 * @param ret[out] result (could be anything)
 * @param trait name of the trait
 * @param selector more detailed information about which object
 *                 to return in case there were multiple generated
 *                 by the command
 * @return #GNUNET_OK on success
 */
static int
wirewatch_traits (void *cls,
                  void **ret,
                  const char *trait,
                  unsigned int index)
{
  struct WirewatchState *ws = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (0,
                                      &ws->wirewatch_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Execute taler-exchange-wirewatch process.
 *
 * @param label command label
 * @param config_filename configuration filename
 *
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_wirewatch (const char *label,
                                  const char *config_filename)
{
  struct TALER_TESTING_Command cmd;
  struct WirewatchState *ws;

  ws = GNUNET_new (struct WirewatchState);
  ws->config_filename = config_filename;
  cmd.cls = ws;
  cmd.label = label;
  cmd.run = &wirewatch_run;
  cmd.cleanup = &wirewatch_cleanup;
  cmd.traits = &wirewatch_traits;
  return cmd;
}

/* end of testing_api_cmd_exec_wirewatch.c */
