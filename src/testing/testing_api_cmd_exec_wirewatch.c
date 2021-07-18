/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_cmd_exec_wirewatch.c
 * @brief run the taler-exchange-wirewatch command
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * State for a "wirewatch" CMD.
 */
struct WirewatchState
{

  /**
   * Process for the wirewatcher.
   */
  struct GNUNET_OS_Process *wirewatch_proc;

  /**
   * Configuration file used by the wirewatcher.
   */
  const char *config_filename;
};

/**
 * Run the command; use the `taler-exchange-wirewatch' program.
 *
 * @param cls closure.
 * @param cmd command currently being executed.
 * @param is interpreter state.
 */
static void
wirewatch_run (void *cls,
               const struct TALER_TESTING_Command *cmd,
               struct TALER_TESTING_Interpreter *is)
{
  struct WirewatchState *ws = cls;

  ws->wirewatch_proc
    = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                               NULL, NULL, NULL,
                               "taler-exchange-wirewatch",
                               "taler-exchange-wirewatch",
                               "-c", ws->config_filename,
                               "-S", "1",
                               "-w", "0",
                               "-t", /* exit when done */
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
 * Free the state of a "wirewatch" CMD, and possibly
 * kills its process if it did not terminate regularly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
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
 * Offer "wirewatch" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static int
wirewatch_traits (void *cls,
                  const void **ret,
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
 * Make a "wirewatch" CMD.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_wirewatch (const char *label,
                                  const char *config_filename)
{
  struct WirewatchState *ws;

  ws = GNUNET_new (struct WirewatchState);
  ws->config_filename = config_filename;

  {
    struct TALER_TESTING_Command cmd = {
      .cls = ws,
      .label = label,
      .run = &wirewatch_run,
      .cleanup = &wirewatch_cleanup,
      .traits = &wirewatch_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_exec_wirewatch.c */
