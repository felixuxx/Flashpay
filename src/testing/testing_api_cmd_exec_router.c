/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

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
 * @file testing/testing_api_cmd_exec_router.c
 * @brief run the taler-exchange-router command
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * State for a "router" CMD.
 */
struct RouterState
{

  /**
   * Process for the routerer.
   */
  struct GNUNET_OS_Process *router_proc;

  /**
   * Configuration file used by the routerer.
   */
  const char *config_filename;
};


/**
 * Run the command; use the `taler-exchange-router' program.
 *
 * @param cls closure.
 * @param cmd command currently being executed.
 * @param is interpreter state.
 */
static void
router_run (void *cls,
            const struct TALER_TESTING_Command *cmd,
            struct TALER_TESTING_Interpreter *is)
{
  struct RouterState *ws = cls;

  (void) cmd;
  ws->router_proc
    = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                               NULL, NULL, NULL,
                               "taler-exchange-router",
                               "taler-exchange-router",
                               "-c", ws->config_filename,
                               "-t", /* exit when done */
                               NULL);
  if (NULL == ws->router_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Free the state of a "router" CMD, and possibly
 * kills its process if it did not terminate regularly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
router_cleanup (void *cls,
                const struct TALER_TESTING_Command *cmd)
{
  struct RouterState *ws = cls;

  (void) cmd;
  if (NULL != ws->router_proc)
  {
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (ws->router_proc,
                                          SIGKILL));
    GNUNET_OS_process_wait (ws->router_proc);
    GNUNET_OS_process_destroy (ws->router_proc);
    ws->router_proc = NULL;
  }
  GNUNET_free (ws);
}


/**
 * Offer "router" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
router_traits (void *cls,
               const void **ret,
               const char *trait,
               unsigned int index)
{
  struct RouterState *ws = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (&ws->router_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_router (const char *label,
                               const char *config_filename)
{
  struct RouterState *ws;

  ws = GNUNET_new (struct RouterState);
  ws->config_filename = config_filename;

  {
    struct TALER_TESTING_Command cmd = {
      .cls = ws,
      .label = label,
      .run = &router_run,
      .cleanup = &router_cleanup,
      .traits = &router_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_exec_router.c */
