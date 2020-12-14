/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file testing/testing_api_cmd_offline_sign_fees.c
 * @brief run the taler-exchange-offline command to download, sign and upload wire fees
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * State for a "offlinesign" CMD.
 */
struct OfflineSignState
{

  /**
   * Process for the "offlinesign" command.
   */
  struct GNUNET_OS_Process *offlinesign_proc;

  /**
   * Configuration file used by the command.
   */
  const char *config_filename;

  /**
   * The wire fee to sign.
   */
  const char *wire_fee_s;

  /**
   * The closing fee to sign.
   */
  const char *closing_fee_s;

};


/**
 * Run the command; calls the `taler-exchange-offline' program.
 *
 * @param cls closure.
 * @param cmd the commaind being run.
 * @param is interpreter state.
 */
static void
offlinesign_run (void *cls,
                 const struct TALER_TESTING_Command *cmd,
                 struct TALER_TESTING_Interpreter *is)
{
  struct OfflineSignState *ks = cls;

  ks->offlinesign_proc
    = GNUNET_OS_start_process (
        GNUNET_OS_INHERIT_STD_ALL,
        NULL, NULL, NULL,
        "taler-exchange-offline",
        "taler-exchange-offline",
        "-c", ks->config_filename,
        "-L", "INFO",
        "wire-fee",
        "now",
        "x-taler-bank",
        ks->wire_fee_s,
        ks->closing_fee_s,
        "upload",
        NULL);
  if (NULL == ks->offlinesign_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Free the state of a "offlinesign" CMD, and possibly kills its
 * process if it did not terminate correctly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
offlinesign_cleanup (void *cls,
                     const struct TALER_TESTING_Command *cmd)
{
  struct OfflineSignState *ks = cls;

  (void) cmd;
  if (NULL != ks->offlinesign_proc)
  {
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (ks->offlinesign_proc,
                                          SIGKILL));
    GNUNET_OS_process_wait (ks->offlinesign_proc);
    GNUNET_OS_process_destroy (ks->offlinesign_proc);
    ks->offlinesign_proc = NULL;
  }
  GNUNET_free (ks);
}


/**
 * Offer "offlinesign" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param[out] ret result
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static int
offlinesign_traits (void *cls,
                    const void **ret,
                    const char *trait,
                    unsigned int index)
{
  struct OfflineSignState *ks = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (0,
                                      &ks->offlinesign_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Sign a wire fee.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @param wire_fee the wire fee to affirm (for the current year)
 * @param closing_fee the closing fee to affirm (for the current year)
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_offline_sign_fees (const char *label,
                                          const char *config_filename,
                                          const char *wire_fee,
                                          const char *closing_fee)
{
  struct OfflineSignState *ks;

  ks = GNUNET_new (struct OfflineSignState);
  ks->config_filename = config_filename;
  ks->wire_fee_s = wire_fee;
  ks->closing_fee_s = closing_fee;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ks,
      .label = label,
      .run = &offlinesign_run,
      .cleanup = &offlinesign_cleanup,
      .traits = &offlinesign_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_exec_offline_sign_fees.c */
