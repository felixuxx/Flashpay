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


/**
 * State for a "auditor sign" CMD.
 */
struct AuditorSignState
{

  /**
   * Handle to the process making the signature.
   */
  struct GNUNET_OS_Process *auditor_sign_proc;

  /**
   * Configuration file used by the command.
   */
  const char *config_filename;

  /**
   * File name of signed blob.
   */
  char *signed_keys_out;
};


/**
 * Run the command; calls the `taler-auditor-sign' program.
 *
 * @param cls closure.
 * @param cmd the command.
 * @param is interpreter state.
 */
static void
auditor_sign_run (void *cls,
                  const struct TALER_TESTING_Command *cmd,
                  struct TALER_TESTING_Interpreter *is)
{
  struct AuditorSignState *ass = cls;

  struct GNUNET_CONFIGURATION_Handle *cfg;
  char *test_home_dir;
  char *exchange_master_pub;
  struct GNUNET_TIME_Absolute now;

  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK != GNUNET_CONFIGURATION_load
        (cfg, ass->config_filename))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
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

  now = GNUNET_TIME_absolute_get ();
  GNUNET_asprintf
    (&ass->signed_keys_out,
    "%s/.local/share/taler/auditors/auditor-%llu.out",
    test_home_dir,
    (unsigned long long) now.abs_value_us);
  GNUNET_free (test_home_dir);

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
                             "-o", ass->signed_keys_out,
                             NULL);
  GNUNET_free (exchange_master_pub);
  if (NULL == ass->auditor_sign_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Free the state of a "auditor sign" CMD, and possibly
 * kill its process if it did not terminate correctly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
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
  GNUNET_free_non_null (ass->signed_keys_out);
  GNUNET_free (ass);
}


/**
 * Offer "auditor sign" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param ret[out] result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static int
auditor_sign_traits (void *cls,
                     const void **ret,
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
 * Make a "auditor sign" CMD.
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
  struct AuditorSignState *ass;

  ass = GNUNET_new (struct AuditorSignState);
  ass->config_filename = config_filename;

  {
    struct TALER_TESTING_Command cmd = {
      .cls = ass,
      .label = label,
      .run = &auditor_sign_run,
      .cleanup = &auditor_sign_cleanup,
      .traits = &auditor_sign_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_exec_auditor-sign.c */
