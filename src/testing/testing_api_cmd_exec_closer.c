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

  /**
   * Reserve history entry that corresponds to this operation.  Set if @e
   * expect_close is true.  Will be of type
   * #TALER_EXCHANGE_RTT_RESERVE_CLOSED.
   */
  struct TALER_EXCHANGE_ReserveHistory reserve_history;

  /**
   * If the closer filled a reserve (@e expect_close is set), this is set to
   * the reserve's public key.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Reference to a command to get the @e reserve_pub.
   */
  const char *reserve_ref;

  /**
   * Do we expect the command to actually close a reserve?
   */
  int expect_close;
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

  (void) cmd;
  if (NULL != as->reserve_ref)
  {
    const struct TALER_TESTING_Command *rcmd;
    const struct TALER_ReservePublicKeyP *reserve_pubp;

    rcmd = TALER_TESTING_interpreter_lookup_command (is,
                                                     as->reserve_ref);
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_reserve_pub (rcmd,
                                             0,
                                             &reserve_pubp))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    as->reserve_pub = *reserve_pubp;
  }
  as->closer_proc
    = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
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

  (void) cmd;
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
  struct TALER_TESTING_Trait xtraits[] = {
    TALER_TESTING_make_trait_process (0, &as->closer_proc),
    TALER_TESTING_make_trait_reserve_pub (0,
                                          &as->reserve_pub),
    TALER_TESTING_make_trait_reserve_history (0,
                                              &as->reserve_history),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait ((as->expect_close)
                                  ? xtraits
                                  : traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Make a "closer" CMD.  Note that it is right now not supported to run the
 * closer to close multiple reserves in combination with a subsequent reserve
 * status call, as we cannot generate the traits necessary for multiple closed
 * reserves.  You can work around this by using multiple closer commands, one
 * per reserve that is being closed.
 *
 * @param label command label.
 * @param config_filename configuration file for the
 *                        closer to use.
 * @param expected_amount amount we expect to see wired from a @a expected_reserve_ref
 * @param expected_fee closing fee we expect to see
 * @param expected_reserve_ref reference to a reserve we expect the closer to drain;
 *          NULL if we do not expect the closer to do anything
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_closer (const char *label,
                               const char *config_filename,
                               const char *expected_amount,
                               const char *expected_fee,
                               const char *expected_reserve_ref)
{
  struct CloserState *as;

  as = GNUNET_new (struct CloserState);
  as->config_filename = config_filename;
  if (NULL != expected_reserve_ref)
  {
    as->expect_close = GNUNET_YES;
    as->reserve_ref = expected_reserve_ref;
    if (GNUNET_OK !=
        TALER_string_to_amount (expected_amount,
                                &as->reserve_history.amount))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to parse amount `%s' at %s\n",
                  expected_amount,
                  label);
      GNUNET_assert (0);
    }
    if (GNUNET_OK !=
        TALER_string_to_amount (expected_fee,
                                &as->reserve_history.details.close_details.fee))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to parse amount `%s' at %s\n",
                  expected_fee,
                  label);
      GNUNET_assert (0);
    }
    /* expected amount includes fee, while our argument
       gives the amount _without_ the fee. So add the fee. */
    GNUNET_assert (0 <=
                   TALER_amount_add (&as->reserve_history.amount,
                                     &as->reserve_history.amount,
                                     &as->reserve_history.details.close_details.
                                     fee));
    as->reserve_history.type = TALER_EXCHANGE_RTT_CLOSE;
  }
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
