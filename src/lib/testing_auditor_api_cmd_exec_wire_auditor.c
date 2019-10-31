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
 * @file auditor-lib/testing_auditor_api_cmd_exec_wire-auditor.c
 * @brief run the taler-wire-auditor command
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
 * State for a "wire-auditor" CMD.
 */
struct WireAuditorState
{

  /**
   * Process for the "wire-auditor" command.
   */
  struct GNUNET_OS_Process *wire_auditor_proc;

  /**
   * Configuration file used by the command.
   */
  const char *config_filename;
};


/**
 * Run the command; calls the `taler-wire-auditor' program.
 *
 * @param cls closure.
 * @param cmd the commaind being run.
 * @param is interpreter state.
 */
static void
wire_auditor_run (void *cls,
                  const struct TALER_TESTING_Command *cmd,
                  struct TALER_TESTING_Interpreter *is)
{
  struct WireAuditorState *ks = cls;

  ks->wire_auditor_proc
    = GNUNET_OS_start_process (GNUNET_NO,
                               GNUNET_OS_INHERIT_STD_ALL,
                               NULL, NULL, NULL,
                               "taler-wire-auditor",
                               "taler-wire-auditor",
                               "-c", ks->config_filename,
                               NULL);
  if (NULL == ks->wire_auditor_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Free the state of a "wire-auditor" CMD, and possibly kills its
 * process if it did not terminate correctly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
wire_auditor_cleanup (void *cls,
                      const struct TALER_TESTING_Command *cmd)
{
  struct WireAuditorState *ks = cls;

  if (NULL != ks->wire_auditor_proc)
  {
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (ks->wire_auditor_proc,
                                          SIGKILL));
    GNUNET_OS_process_wait (ks->wire_auditor_proc);
    GNUNET_OS_process_destroy (ks->wire_auditor_proc);
    ks->wire_auditor_proc = NULL;
  }
  GNUNET_free (ks);
}


/**
 * Offer "wire-auditor" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param ret[out] result
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static int
wire_auditor_traits (void *cls,
                     const void **ret,
                     const char *trait,
                     unsigned int index)
{
  struct WireAuditorState *ks = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (0, &ks->wire_auditor_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Make the "exec wire-auditor" CMD.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_wire_auditor (const char *label,
                                     const char *config_filename)
{
  struct TALER_TESTING_Command cmd;
  struct WireAuditorState *ks;

  ks = GNUNET_new (struct WireAuditorState);
  ks->config_filename = config_filename;
  cmd.cls = ks;
  cmd.label = label;
  cmd.run = &wire_auditor_run;
  cmd.cleanup = &wire_auditor_cleanup;
  cmd.traits = &wire_auditor_traits;
  return cmd;
}


/* end of testing_auditor_api_cmd_exec_wire_auditor.c */
