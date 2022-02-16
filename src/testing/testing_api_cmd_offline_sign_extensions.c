/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

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
 * @file testing/testing_api_cmd_offline_sign_extensions.c
 * @brief run the taler-exchange-offline command to sign extensions (and therefore activate them)
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * State for a "extensionssign" CMD.
 */
struct ExtensionsSignState
{

  /**
   * Process for the "extensionssign" command.
   */
  struct GNUNET_OS_Process *extensionssign_proc;

  /**
   * Configuration file used by the command.
   */
  const char *config_filename;

};


/**
 * Run the command; calls the `taler-exchange-offline' program.
 *
 * @param cls closure.
 * @param cmd the commaind being run.
 * @param is interpreter state.
 */
static void
extensionssign_run (void *cls,
                    const struct TALER_TESTING_Command *cmd,
                    struct TALER_TESTING_Interpreter *is)
{
  struct ExtensionsSignState *ks = cls;

  ks->extensionssign_proc
    = GNUNET_OS_start_process (
        GNUNET_OS_INHERIT_STD_ALL,
        NULL, NULL, NULL,
        "taler-exchange-offline",
        "taler-exchange-offline",
        "-c", ks->config_filename,
        "-L", "INFO",
        "extensions",
        "sign",
        "upload",
        NULL);
  if (NULL == ks->extensionssign_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Free the state of a "extensionssign" CMD, and possibly kills its
 * process if it did not terminate correctly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
extensionssign_cleanup (void *cls,
                        const struct TALER_TESTING_Command *cmd)
{
  struct ExtensionsSignState *ks = cls;

  (void) cmd;
  if (NULL != ks->extensionssign_proc)
  {
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (ks->extensionssign_proc,
                                          SIGKILL));
    GNUNET_OS_process_wait (ks->extensionssign_proc);
    GNUNET_OS_process_destroy (ks->extensionssign_proc);
    ks->extensionssign_proc = NULL;
  }
  GNUNET_free (ks);
}


/**
 * Offer "extensionssign" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param[out] ret result
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
extensionssign_traits (void *cls,
                       const void **ret,
                       const char *trait,
                       unsigned int index)
{
  struct ExtensionsSignState *ks = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (&ks->extensionssign_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_offline_sign_extensions (const char *label,
                                                const char *config_filename)
{
  struct ExtensionsSignState *ks;

  ks = GNUNET_new (struct ExtensionsSignState);
  ks->config_filename = config_filename;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ks,
      .label = label,
      .run = &extensionssign_run,
      .cleanup = &extensionssign_cleanup,
      .traits = &extensionssign_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_exec_offline_sign_extensions.c */
