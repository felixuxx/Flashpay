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
 * @file testing/testing_api_cmd_exec_expire.c
 * @brief run the taler-exchange-expire command
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * State for a "expire" CMD.
 */
struct ExpireState
{

  /**
   * Process for the expireer.
   */
  struct GNUNET_OS_Process *expire_proc;

  /**
   * Configuration file used by the expireer.
   */
  const char *config_filename;
};


/**
 * Run the command; use the `taler-exchange-expire' program.
 *
 * @param cls closure.
 * @param cmd command currently being executed.
 * @param is interpreter state.
 */
static void
expire_run (void *cls,
            const struct TALER_TESTING_Command *cmd,
            struct TALER_TESTING_Interpreter *is)
{
  struct ExpireState *ws = cls;

  (void) cmd;
  ws->expire_proc
    = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                               NULL, NULL, NULL,
                               "taler-exchange-expire",
                               "taler-exchange-expire",
                               "-L", "INFO",
                               "-c", ws->config_filename,
                               "-t", /* exit when done */
                               NULL);
  if (NULL == ws->expire_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Free the state of a "expire" CMD, and possibly
 * kills its process if it did not terminate regularly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
expire_cleanup (void *cls,
                const struct TALER_TESTING_Command *cmd)
{
  struct ExpireState *ws = cls;

  (void) cmd;
  if (NULL != ws->expire_proc)
  {
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (ws->expire_proc,
                                          SIGKILL));
    GNUNET_OS_process_wait (ws->expire_proc);
    GNUNET_OS_process_destroy (ws->expire_proc);
    ws->expire_proc = NULL;
  }
  GNUNET_free (ws);
}


/**
 * Offer "expire" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
expire_traits (void *cls,
               const void **ret,
               const char *trait,
               unsigned int index)
{
  struct ExpireState *ws = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (&ws->expire_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_expire (const char *label,
                               const char *config_filename)
{
  struct ExpireState *ws;

  ws = GNUNET_new (struct ExpireState);
  ws->config_filename = config_filename;

  {
    struct TALER_TESTING_Command cmd = {
      .cls = ws,
      .label = label,
      .run = &expire_run,
      .cleanup = &expire_cleanup,
      .traits = &expire_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_exec_expire.c */
