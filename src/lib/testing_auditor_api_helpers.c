/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3, or
  (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/

/**
 * @file auditor-lib/testing_auditor_api_helpers.c
 * @brief helper functions
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_testing_auditor_lib.h"
#include "taler_auditor_service.h"


/**
 * Closure for #cleanup_auditor.
 */
struct CleanupContext
{
  /**
   * Where we find the state to clean up.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Next cleanup routine to call, NULL for none.
   */
  GNUNET_SCHEDULER_TaskCallback fcb;

  /**
   * Closure for @e fcb
   */
  void *fcb_cls;
};


/**
 * Function to clean up the auditor connection.
 *
 * @param cls a `struct CleanupContext`
 */
static void
cleanup_auditor (void *cls)
{
  struct CleanupContext *cc = cls;
  struct TALER_TESTING_Interpreter *is = cc->is;

  TALER_AUDITOR_disconnect (is->auditor);
  is->auditor = NULL;
  if (NULL != cc->fcb)
    cc->fcb (cc->fcb_cls);
  GNUNET_free (cc);
}

/**
 * Closure for #auditor_main_wrapper()
 */
struct MainWrapperContext
{
  /**
   * Main function to launch.
   */
  TALER_TESTING_Main main_cb;

  /**
   * Closure for @e main_cb.
   */
  void *main_cb_cls;

  /**
   * Configuration we use.
   */
  const struct GNUNET_CONFIGURATION_Handle *cfg;

  /**
   * Name of the configuration file.
   */
  const char *config_filename;

};


/**
 * Function called with information about the auditor.
 *
 * @param cls closure
 * @param vi basic information about the auditor
 * @param compat protocol compatibility information
 */
static void
auditor_version_cb
  (void *cls,
  const struct TALER_AUDITOR_VersionInformation *vi,
  enum TALER_AUDITOR_VersionCompatibility compat)
{
  struct TALER_TESTING_Interpreter *is = cls;

  if (TALER_AUDITOR_VC_MATCH != compat)
  {
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  is->auditor_working = GNUNET_YES;
}

/**
 * Setup the @a is 'auditor' member before running the main test loop.
 *
 * @param cls must be a `struct MainWrapperContext *`
 * @param is[in,out] interpreter state to setup
 */
static void
auditor_main_wrapper (void *cls,
                      struct TALER_TESTING_Interpreter *is)
{
  struct MainWrapperContext *mwc = cls;
  struct CleanupContext *cc;
  char *auditor_base_url;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (mwc->cfg,
                                             "auditor",
                                             "BASE_URL",
                                             &auditor_base_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "auditor",
                               "BASE_URL");
    return;
  }

  is->auditor = TALER_AUDITOR_connect (is->ctx,
                                       auditor_base_url,
                                       &auditor_version_cb,
                                       is);
  GNUNET_free (auditor_base_url);

  if (NULL == is->auditor)
  {
    GNUNET_break (0);
    return;
  }

  cc = GNUNET_new (struct CleanupContext);
  cc->is = is;
  cc->fcb = is->final_cleanup_cb;
  cc->fcb_cls = is->final_cleanup_cb;
  is->final_cleanup_cb = cleanup_auditor;
  is->final_cleanup_cb_cls = cc;
  mwc->main_cb (mwc->main_cb_cls,
                is);
}


/**
 * Install signal handlers plus schedules the main wrapper
 * around the "run" method.
 *
 * @param cls our `struct MainWrapperContext`
 * @param cfg configuration we use
 * @return #GNUNET_OK if all is okay, != #GNUNET_OK otherwise.
 *         non-GNUNET_OK codes are #GNUNET_SYSERR most of the
 *         times.
 */
static int
setup_with_cfg (void *cls,
                const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  struct MainWrapperContext *mwc = cls;
  struct TALER_TESTING_SetupContext setup_ctx = {
    .config_filename = mwc->config_filename,
    .main_cb = &auditor_main_wrapper,
    .main_cb_cls = mwc
  };

  mwc->cfg = cfg;
  return TALER_TESTING_setup_with_auditor_and_exchange_cfg (&setup_ctx,
                                                            cfg);
}


/**
 * Install signal handlers plus schedules the main wrapper
 * around the "run" method.
 *
 * @param main_cb the "run" method which contains all the
 *        commands.
 * @param main_cb_cls a closure for "run", typically NULL.
 * @param config_filename configuration filename.
 * @return #GNUNET_OK if all is okay, != #GNUNET_OK otherwise.
 *         non-GNUNET_OK codes are #GNUNET_SYSERR most of the
 *         times.
 */
int
TALER_TESTING_AUDITOR_setup (TALER_TESTING_Main main_cb,
                             void *main_cb_cls,
                             const char *config_filename)
{
  struct MainWrapperContext mwc = {
    .main_cb = main_cb,
    .main_cb_cls = main_cb_cls,
    .config_filename = config_filename
  };

  return GNUNET_CONFIGURATION_parse_and_run (config_filename,
                                             &setup_with_cfg,
                                             &mwc);
}



/* end of testing_auditor_api_helpers.c */
