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
 * @file testing/testing_api_cmd_exec_auditor-offline.c
 * @brief run the taler-exchange-auditor-offline command
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * State for a "auditor-offline" CMD.
 */
struct AuditorOfflineState
{

  /**
   * AuditorOffline process.
   */
  struct GNUNET_OS_Process *auditor_offline_proc;

  /**
   * Configuration file used by the auditor-offline.
   */
  const char *config_filename;

};


/**
 * Run the command.  Use the `taler-exchange-auditor-offline' program.
 *
 * @param cls closure.
 * @param cmd command being run.
 * @param is interpreter state.
 */
static void
auditor_offline_run (void *cls,
                     const struct TALER_TESTING_Command *cmd,
                     struct TALER_TESTING_Interpreter *is)
{
  struct AuditorOfflineState *as = cls;

  (void) cmd;
  as->auditor_offline_proc
    = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                               NULL, NULL, NULL,
                               "taler-auditor-offline",
                               "taler-auditor-offline",
                               "-c", as->config_filename,
                               "-L", "INFO",
                               "download",
                               "sign",
                               "upload",
                               NULL);
  if (NULL == as->auditor_offline_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Free the state of a "auditor-offline" CMD, and possibly kill its
 * process if it did not terminate correctly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
auditor_offline_cleanup (void *cls,
                         const struct TALER_TESTING_Command *cmd)
{
  struct AuditorOfflineState *as = cls;

  (void) cmd;
  if (NULL != as->auditor_offline_proc)
  {
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (as->auditor_offline_proc,
                                          SIGKILL));
    GNUNET_OS_process_wait (as->auditor_offline_proc);
    GNUNET_OS_process_destroy (as->auditor_offline_proc);
    as->auditor_offline_proc = NULL;
  }
  GNUNET_free (as);
}


/**
 * Offer "auditor-offline" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
auditor_offline_traits (void *cls,
                        const void **ret,
                        const char *trait,
                        unsigned int index)
{
  struct AuditorOfflineState *as = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (&as->auditor_offline_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_auditor_offline (const char *label,
                                        const char *config_filename)
{
  struct AuditorOfflineState *as;

  as = GNUNET_new (struct AuditorOfflineState);
  as->config_filename = config_filename;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = as,
      .label = label,
      .run = &auditor_offline_run,
      .cleanup = &auditor_offline_cleanup,
      .traits = &auditor_offline_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_exec_auditor-offline.c */
