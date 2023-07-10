/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_cmd_auditor_add.c
 * @brief command for testing auditor_add
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"


/**
 * State for a "auditor_add" CMD.
 */
struct AuditorAddState
{

  /**
   * Auditor enable handle while operation is running.
   */
  struct TALER_EXCHANGE_ManagementAuditorEnableHandle *dh;

  /**
   * Our interpreter.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Should we make the request with a bad master_sig signature?
   */
  bool bad_sig;
};


/**
 * Callback to analyze the /management/auditors response, just used to check
 * if the response code is acceptable.
 *
 * @param cls closure.
 * @param aer response details
 */
static void
auditor_add_cb (
  void *cls,
  const struct TALER_EXCHANGE_ManagementAuditorEnableResponse *aer)
{
  struct AuditorAddState *ds = cls;
  const struct TALER_EXCHANGE_HttpResponse *hr = &aer->hr;

  ds->dh = NULL;
  if (ds->expected_response_code != hr->http_status)
  {
    TALER_TESTING_unexpected_status (ds->is,
                                     hr->http_status,
                                     ds->expected_response_code);
    return;
  }
  TALER_TESTING_interpreter_next (ds->is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
auditor_add_run (void *cls,
                 const struct TALER_TESTING_Command *cmd,
                 struct TALER_TESTING_Interpreter *is)
{
  struct AuditorAddState *ds = cls;
  struct GNUNET_TIME_Timestamp now;
  struct TALER_MasterSignatureP master_sig;
  const struct TALER_AuditorPublicKeyP *auditor_pub;
  const struct TALER_TESTING_Command *auditor_cmd;
  const struct TALER_TESTING_Command *exchange_cmd;
  const char *exchange_url;
  const char *auditor_url;

  (void) cmd;
  now = GNUNET_TIME_timestamp_get ();
  ds->is = is;

  auditor_cmd = TALER_TESTING_interpreter_get_command (is,
                                                       "auditor");
  if (NULL == auditor_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_auditor_pub (auditor_cmd,
                                                      &auditor_pub));
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_auditor_url (auditor_cmd,
                                                      &auditor_url));
  exchange_cmd = TALER_TESTING_interpreter_get_command (is,
                                                        "exchange");
  if (NULL == exchange_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_exchange_url (exchange_cmd,
                                                       &exchange_url));


  if (ds->bad_sig)
  {
    memset (&master_sig,
            42,
            sizeof (master_sig));
  }
  else
  {
    const struct TALER_MasterPrivateKeyP *master_priv;

    GNUNET_assert (GNUNET_OK ==
                   TALER_TESTING_get_trait_master_priv (exchange_cmd,
                                                        &master_priv));
    TALER_exchange_offline_auditor_add_sign (auditor_pub,
                                             auditor_url,
                                             now,
                                             master_priv,
                                             &master_sig);
  }
  ds->dh = TALER_EXCHANGE_management_enable_auditor (
    TALER_TESTING_interpreter_get_context (is),
    exchange_url,
    auditor_pub,
    auditor_url,
    "test-case auditor", /* human-readable auditor name */
    now,
    &master_sig,
    &auditor_add_cb,
    ds);
  if (NULL == ds->dh)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "auditor_add" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct AuditorAddState`.
 * @param cmd the command which is being cleaned up.
 */
static void
auditor_add_cleanup (void *cls,
                     const struct TALER_TESTING_Command *cmd)
{
  struct AuditorAddState *ds = cls;

  if (NULL != ds->dh)
  {
    TALER_TESTING_command_incomplete (ds->is,
                                      cmd->label);
    TALER_EXCHANGE_management_enable_auditor_cancel (ds->dh);
    ds->dh = NULL;
  }
  GNUNET_free (ds);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_auditor_add (const char *label,
                               unsigned int expected_http_status,
                               bool bad_sig)
{
  struct AuditorAddState *ds;

  ds = GNUNET_new (struct AuditorAddState);
  ds->expected_response_code = expected_http_status;
  ds->bad_sig = bad_sig;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ds,
      .label = label,
      .run = &auditor_add_run,
      .cleanup = &auditor_add_cleanup
    };

    return cmd;
  }
}


/* end of testing_api_cmd_auditor_add.c */
