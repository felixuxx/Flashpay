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
 * @file testing/testing_api_cmd_exec_aggregator.c
 * @brief run the taler-exchange-aggregator command
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * State for a "aggregator" CMD.
 */
struct AggregatorState
{

  /**
   * Aggregator process.
   */
  struct GNUNET_OS_Process *aggregator_proc;

  /**
   * Configuration file used by the aggregator.
   */
  const char *config_filename;

  /**
   * Run with KYC restrictions on.
   */
  bool kyc_on;
};


/**
 * Run the command.  Use the `taler-exchange-aggregator' program.
 *
 * @param cls closure.
 * @param cmd command being run.
 * @param is interpreter state.
 */
static void
aggregator_run (void *cls,
                const struct TALER_TESTING_Command *cmd,
                struct TALER_TESTING_Interpreter *is)
{
  struct AggregatorState *as = cls;

  (void) cmd;
  as->aggregator_proc
    = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                               NULL, NULL, NULL,
                               "taler-exchange-aggregator",
                               "taler-exchange-aggregator",
                               "-c", as->config_filename,
                               "-L", "INFO",
                               "-t", /* exit when done */
                               (as->kyc_on)
                               ? NULL
                               : "-y", /* skip KYC */
                               NULL);
  if (NULL == as->aggregator_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Free the state of a "aggregator" CMD, and possibly kill its
 * process if it did not terminate correctly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
aggregator_cleanup (void *cls,
                    const struct TALER_TESTING_Command *cmd)
{
  struct AggregatorState *as = cls;

  (void) cmd;
  if (NULL != as->aggregator_proc)
  {
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (as->aggregator_proc,
                                          SIGKILL));
    GNUNET_OS_process_wait (as->aggregator_proc);
    GNUNET_OS_process_destroy (as->aggregator_proc);
    as->aggregator_proc = NULL;
  }
  GNUNET_free (as);
}


/**
 * Offer "aggregator" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
aggregator_traits (void *cls,
                   const void **ret,
                   const char *trait,
                   unsigned int index)
{
  struct AggregatorState *as = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (&as->aggregator_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_aggregator (const char *label,
                                   const char *config_filename)
{
  struct AggregatorState *as;

  as = GNUNET_new (struct AggregatorState);
  as->config_filename = config_filename;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = as,
      .label = label,
      .run = &aggregator_run,
      .cleanup = &aggregator_cleanup,
      .traits = &aggregator_traits
    };

    return cmd;
  }
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_aggregator_with_kyc (const char *label,
                                            const char *config_filename)
{
  struct AggregatorState *as;

  as = GNUNET_new (struct AggregatorState);
  as->config_filename = config_filename;
  as->kyc_on = true;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = as,
      .label = label,
      .run = &aggregator_run,
      .cleanup = &aggregator_cleanup,
      .traits = &aggregator_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_exec_aggregator.c */
