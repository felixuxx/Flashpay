/*
  This file is part of TALER
  Copyright (C) 2014-2018 Taler Systems SA

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
 * @file testing/test_auditor_api_version.c
 * @brief testcase to test auditor's HTTP API interface to fetch /version
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_exchange_service.h"
#include "taler_auditor_service.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler_bank_service.h"
#include "taler_fakebank_lib.h"
#include "taler_testing_lib.h"


/**
 * Configuration file we use.  One (big) configuration is used
 * for the various components for this test.
 */
#define CONFIG_FILE "test_auditor_api.conf"

static struct TALER_AUDITOR_Handle *ah;

static struct GNUNET_CURL_Context *ctx;

static struct GNUNET_CURL_RescheduleContext *rc;

static int global_ret;

static struct GNUNET_SCHEDULER_Task *tt;

static void
do_shutdown (void *cls)
{
  (void) cls;

  if (NULL != tt)
  {
    GNUNET_SCHEDULER_cancel (tt);
    tt = NULL;
  }
  TALER_AUDITOR_disconnect (ah);
  GNUNET_CURL_fini (ctx);
  GNUNET_CURL_gnunet_rc_destroy (rc);
}


static void
do_timeout (void *cls)
{
  (void) cls;
  tt = NULL;
  global_ret = 3;
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Function called with information about the auditor.
 *
 * @param cls closure
 * @param vi basic information about the auditor
 * @param compat protocol compatibility information
 */
static void
version_cb (void *cls,
            const struct TALER_AUDITOR_VersionInformation *vi,
            enum TALER_AUDITOR_VersionCompatibility compat)
{
  if ( (NULL != vi) &&
       (TALER_AUDITOR_VC_MATCH == compat) )
    global_ret = 0;
  else
    global_ret = 2;
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Main function that will tell the interpreter what commands to
 * run.
 *
 * @param cls closure
 */
static void
run (void *cls)
{
  const char *auditor_url = "http://localhost:8083/";

  (void) cls;
  ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &rc);
  rc = GNUNET_CURL_gnunet_rc_create (ctx);
  ah = TALER_AUDITOR_connect (ctx,
                              auditor_url,
                              &version_cb,
                              NULL);
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  tt = GNUNET_SCHEDULER_add_delayed (GNUNET_TIME_UNIT_SECONDS,
                                     &do_timeout,
                                     NULL);
}


int
main (int argc,
      char *const *argv)
{
  struct GNUNET_OS_Process *proc;

  /* These environment variables get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-auditor-api-version",
                    "INFO",
                    NULL);
  proc = GNUNET_OS_start_process (GNUNET_NO,
                                  GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-auditor-httpd",
                                  "taler-auditor-httpd",
                                  "-c", CONFIG_FILE,
                                  NULL);
  if (NULL == proc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to run `taler-auditor-httpd`,"
                " is your PATH correct?\n");
    return 77;
  }
  GNUNET_SCHEDULER_run (&run,
                        NULL);
  GNUNET_OS_process_kill (proc, SIGTERM);
  GNUNET_OS_process_wait (proc);
  GNUNET_OS_process_destroy (proc);
  return global_ret;
}


/* end of test_auditor_api_version.c */
