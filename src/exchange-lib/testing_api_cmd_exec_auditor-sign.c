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
 * @file exchange-lib/testing_api_cmd_exec_auditor-sign.c
 * @brief run the taler-exchange-aggregator command
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"


struct AuditorSignState
{

  /**
   * Process for the "auditor sign" command.
   */
  struct GNUNET_OS_Process *auditor_sign_proc;

  /**
   * Which configuration file should we pass to the process?
   */
  const char *config_filename;

};


/**
 * Runs the command.  Note that upon return, the interpreter
 * will not automatically run the next command, as the command
 * may continue asynchronously in other scheduler tasks.  Thus,
 * the command must ensure to eventually call
 * #TALER_TESTING_interpreter_next() or
 * #TALER_TESTING_interpreter_fail().
 *
 * @param is interpreter state
 */
static void
auditor_sign_run (void *cls,
                  const struct TALER_TESTING_Command *cmd,
                  struct TALER_TESTING_Interpreter *is)
{
  struct AuditorSignState *ass = cls;

  struct GNUNET_CONFIGURATION_Handle *cfg;
  char *test_home_dir;
  char *signed_keys_out;
  char *exchange_master_pub;

  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK != GNUNET_CONFIGURATION_load
    (cfg, ass->config_filename))
  {
    GNUNET_break (0); 
    TALER_TESTING_interpreter_fail (is); 
    return;
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "paths",
                                             "TALER_TEST_HOME",
                                             &test_home_dir))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "paths",
                               "TALER_TEST_HOME");
    GNUNET_CONFIGURATION_destroy (cfg);
    GNUNET_break (0); 
    TALER_TESTING_interpreter_fail (is); 
    return;
  }

  GNUNET_asprintf (&signed_keys_out,
                   "%s/.local/share/taler/auditors/auditor.out",
                   test_home_dir);


  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "MASTER_PUBLIC_KEY",
                                             &exchange_master_pub))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "MASTER_PUBLIC_KEY");
    GNUNET_CONFIGURATION_destroy (cfg);

    GNUNET_break (0); 
    TALER_TESTING_interpreter_fail (is); 
    return;
  }

  GNUNET_CONFIGURATION_destroy (cfg);

  ass->auditor_sign_proc = GNUNET_OS_start_process
    (GNUNET_NO,
     GNUNET_OS_INHERIT_STD_ALL,
     NULL, NULL, NULL,
     "taler-auditor-sign",
     "taler-auditor-sign",
     "-c", ass->config_filename,
     "-u", "http://auditor/",
     "-m", exchange_master_pub,
     "-r", "auditor.in",
     "-o", signed_keys_out,
     NULL);

  if (NULL == ass->auditor_sign_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Clean up after the command.  Run during forced termination
 * (CTRL-C) or test failure or test success.
 *
 * @param cls closure
 */
static void
auditor_sign_cleanup (void *cls,
                    const struct TALER_TESTING_Command *cmd)
{
  struct AuditorSignState *ass = cls;

  if (NULL != ass->auditor_sign_proc)
  {
    GNUNET_break (0 == GNUNET_OS_process_kill
      (ass->auditor_sign_proc, SIGKILL));
    GNUNET_OS_process_wait (ass->auditor_sign_proc);
    GNUNET_OS_process_destroy (ass->auditor_sign_proc);
    ass->auditor_sign_proc = NULL;
  }
  GNUNET_free (ass);
}


/**
 * Extract information from a command that is useful for other
 * commands.
 *
 * @param cls closure
 * @param ret[out] result (could be anything)
 * @param trait name of the trait
 * @param selector more detailed information about which object
 *                 to return in case there were multiple generated
 *                 by the command
 * @return #GNUNET_OK on success
 */
static int
auditor_sign_traits (void *cls,
                     void **ret,
                     const char *trait,
                     unsigned int index)
{
  struct AuditorSignState *ass = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (0, &ass->auditor_sign_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Execute taler-auditor-sign process.
 *
 * @param label command label
 * @param config_filename configuration filename
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_auditor_sign (const char *label,
                                     const char *config_filename)
{
  struct TALER_TESTING_Command cmd;
  struct AuditorSignState *ass;

  ass = GNUNET_new (struct AuditorSignState);
  ass->config_filename = config_filename;
  cmd.cls = ass;
  cmd.label = label;
  cmd.run = &auditor_sign_run;
  cmd.cleanup = &auditor_sign_cleanup;
  cmd.traits = &auditor_sign_traits;
  return cmd;
}

/* end of testing_api_cmd_exec_auditor-sign.c */
