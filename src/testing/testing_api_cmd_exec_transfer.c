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
 * @file testing/testing_api_cmd_exec_transfer.c
 * @brief run the taler-exchange-transfer command
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * State for a "transfer" CMD.
 */
struct TransferState
{

  /**
   * Transfer process.
   */
  struct GNUNET_OS_Process *transfer_proc;

  /**
   * Configuration file used by the transfer.
   */
  const char *config_filename;
};


/**
 * Run the command.  Use the `taler-exchange-transfer' program.
 *
 * @param cls closure.
 * @param cmd command being run.
 * @param is interpreter state.
 */
static void
transfer_run (void *cls,
              const struct TALER_TESTING_Command *cmd,
              struct TALER_TESTING_Interpreter *is)
{
  struct TransferState *as = cls;

  as->transfer_proc
    = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                               NULL, NULL, NULL,
                               "taler-exchange-transfer",
                               "taler-exchange-transfer",
                               "-c", as->config_filename,
                               "-t", /* exit when done */
                               NULL);
  if (NULL == as->transfer_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Free the state of a "transfer" CMD, and possibly kill its
 * process if it did not terminate correctly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
transfer_cleanup (void *cls,
                  const struct TALER_TESTING_Command *cmd)
{
  struct TransferState *as = cls;

  if (NULL != as->transfer_proc)
  {
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (as->transfer_proc,
                                          SIGKILL));
    GNUNET_OS_process_wait (as->transfer_proc);
    GNUNET_OS_process_destroy (as->transfer_proc);
    as->transfer_proc = NULL;
  }
  GNUNET_free (as);
}


/**
 * Offer "transfer" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static int
transfer_traits (void *cls,
                 const void **ret,
                 const char *trait,
                 unsigned int index)
{
  struct TransferState *as = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (0, &as->transfer_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Make a "transfer" CMD.
 *
 * @param label command label.
 * @param config_filename configuration file for the
 *                        transfer to use.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_transfer (const char *label,
                                 const char *config_filename)
{
  struct TransferState *as;

  as = GNUNET_new (struct TransferState);
  as->config_filename = config_filename;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = as,
      .label = label,
      .run = &transfer_run,
      .cleanup = &transfer_cleanup,
      .traits = &transfer_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_exec_transfer.c */
