/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file testing/testing_api_cmd_exec_wget.c
 * @brief run a wget command
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * State for a "wget" CMD.
 */
struct WgetState
{
  /**
   * Process for the wgeter.
   */
  struct GNUNET_OS_Process *wget_proc;

  /**
   * URL to used by the wget.
   */
  const char *url;
};


/**
 * Run the command; use the `wget' program.
 *
 * @param cls closure.
 * @param cmd command currently being executed.
 * @param is interpreter state.
 */
static void
wget_run (void *cls,
          const struct TALER_TESTING_Command *cmd,
          struct TALER_TESTING_Interpreter *is)
{
  struct WgetState *ws = cls;

  (void) cmd;
  ws->wget_proc
    = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                               NULL, NULL, NULL,
                               "wget",
                               "wget",
                               ws->url,
                               NULL);
  if (NULL == ws->wget_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Free the state of a "wget" CMD, and possibly
 * kills its process if it did not terminate regularly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
wget_cleanup (void *cls,
              const struct TALER_TESTING_Command *cmd)
{
  struct WgetState *ws = cls;

  (void) cmd;
  if (NULL != ws->wget_proc)
  {
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (ws->wget_proc,
                                          SIGKILL));
    GNUNET_OS_process_wait (ws->wget_proc);
    GNUNET_OS_process_destroy (ws->wget_proc);
    ws->wget_proc = NULL;
  }
  GNUNET_free (ws);
}


/**
 * Offer "wget" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
wget_traits (void *cls,
             const void **ret,
             const char *trait,
             unsigned int index)
{
  struct WgetState *ws = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (&ws->wget_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_wget (const char *label,
                             const char *url)
{
  struct WgetState *ws;

  ws = GNUNET_new (struct WgetState);
  ws->url = url;

  {
    struct TALER_TESTING_Command cmd = {
      .cls = ws,
      .label = label,
      .run = &wget_run,
      .cleanup = &wget_cleanup,
      .traits = &wget_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_exec_wget.c */
