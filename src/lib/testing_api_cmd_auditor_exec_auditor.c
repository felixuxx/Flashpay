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
 * @file lib/testing_api_cmd_auditor_exec_auditor.c
 * @brief run the taler-auditor command
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "auditor_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * State for a "auditor" CMD.
 */
struct AuditorState
{

  /**
   * Process for the "auditor" command.
   */
  struct GNUNET_OS_Process *auditor_proc;

  /**
   * Configuration file used by the command.
   */
  const char *config_filename;
};


/**
 * Run the command; calls the `taler-auditor' program.
 *
 * @param cls closure.
 * @param cmd the commaind being run.
 * @param is interpreter state.
 */
static void
auditor_run (void *cls,
             const struct TALER_TESTING_Command *cmd,
             struct TALER_TESTING_Interpreter *is)
{
  struct AuditorState *ks = cls;

  ks->auditor_proc
    = GNUNET_OS_start_process (GNUNET_NO,
                               GNUNET_OS_INHERIT_STD_ALL,
                               NULL, NULL, NULL,
                               "taler-auditor",
                               "taler-auditor",
                               "-c", ks->config_filename,
                               NULL);
  if (NULL == ks->auditor_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Free the state of a "auditor" CMD, and possibly kills its
 * process if it did not terminate correctly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
auditor_cleanup (void *cls,
                 const struct TALER_TESTING_Command *cmd)
{
  struct AuditorState *ks = cls;

  if (NULL != ks->auditor_proc)
  {
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (ks->auditor_proc,
                                          SIGKILL));
    GNUNET_OS_process_wait (ks->auditor_proc);
    GNUNET_OS_process_destroy (ks->auditor_proc);
    ks->auditor_proc = NULL;
  }
  GNUNET_free (ks);
}


/**
 * Offer "auditor" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param[out] ret result
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static int
auditor_traits (void *cls,
                const void **ret,
                const char *trait,
                unsigned int index)
{
  struct AuditorState *ks = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (0, &ks->auditor_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Make the "exec-auditor" CMD.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_auditor (const char *label,
                                const char *config_filename)
{
  struct AuditorState *ks;

  ks = GNUNET_new (struct AuditorState);
  ks->config_filename = config_filename;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ks,
      .label = label,
      .run = &auditor_run,
      .cleanup = &auditor_cleanup,
      .traits = &auditor_traits
    };

    return cmd;
  }
}


/* end of testing_auditor_api_cmd_exec_auditor.c */
