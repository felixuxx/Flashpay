/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published
  by the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_cmd_exec_closer.c
 * @brief run the taler-exchange-closer command
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * State for a "closer" CMD.
 */
struct CloserState
{

  /**
   * Closer process.
   */
  struct GNUNET_OS_Process *closer_proc;

  /**
   * Configuration file used by the closer.
   */
  const char *config_filename;
};


/**
 * Run the command.  Use the `taler-exchange-closer' program.
 *
 * @param cls closure.
 * @param cmd command being run.
 * @param is interpreter state.
 */
static void
closer_run (void *cls,
            const struct TALER_TESTING_Command *cmd,
            struct TALER_TESTING_Interpreter *is)
{
  struct CloserState *as = cls;

  as->closer_proc
    = GNUNET_OS_start_process (GNUNET_NO,
                               GNUNET_OS_INHERIT_STD_ALL,
                               NULL, NULL, NULL,
                               "taler-exchange-closer",
                               "taler-exchange-closer",
                               "-c", as->config_filename,
                               "-t", /* exit when done */
                               NULL);
  if (NULL == as->closer_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Free the state of a "closer" CMD, and possibly kill its
 * process if it did not terminate correctly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
closer_cleanup (void *cls,
                const struct TALER_TESTING_Command *cmd)
{
  struct CloserState *as = cls;

  if (NULL != as->closer_proc)
  {
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (as->closer_proc,
                                          SIGKILL));
    GNUNET_OS_process_wait (as->closer_proc);
    GNUNET_OS_process_destroy (as->closer_proc);
    as->closer_proc = NULL;
  }
  GNUNET_free (as);
}


/**
 * Offer "closer" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static int
closer_traits (void *cls,
               const void **ret,
               const char *trait,
               unsigned int index)
{
  struct CloserState *as = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (0, &as->closer_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Make a "closer" CMD.
 *
 * @param label command label.
 * @param config_filename configuration file for the
 *                        closer to use.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_closer (const char *label,
                               const char *config_filename)
{
  struct CloserState *as;

  as = GNUNET_new (struct CloserState);
  as->config_filename = config_filename;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = as,
      .label = label,
      .run = &closer_run,
      .cleanup = &closer_cleanup,
      .traits = &closer_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_exec_closer.c */
