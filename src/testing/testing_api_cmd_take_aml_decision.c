/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file testing/testing_api_cmd_take_aml_decision.c
 * @brief command for testing /management/XXX
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"


/**
 * State for a "take_aml_decision" CMD.
 */
struct AmlDecisionState
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
   * Reference to command to previous set officer
   * to update, or NULL.
   */
  const char *ref_cmd;

  /**
   * Name to use for the officer.
   */
  const char *name;

  /**
   * Is the officer supposed to be enabled?
   */
  bool is_active;

  /**
   * Is access supposed to be read-only?
   */
  bool read_only;

};


/**
 * Callback to analyze the /management/XXX response, just used to check
 * if the response code is acceptable.
 *
 * @param cls closure.
 * @param hr HTTP response details
 */
static void
take_aml_decision_cb (void *cls,
                      const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct AmlDecisionState *ds = cls;

  ds->dh = NULL;
  if (MHD_HTTP_NO_CONTENT != hr->response_code)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Unexpected response code %u to command %s in %s:%u\n",
                hr->http_status,
                ds->is->commands[ds->is->ip].label,
                __FILE__,
                __LINE__);
    json_dumpf (hr->reply,
                stderr,
                0);
    TALER_TESTING_interpreter_fail (ds->is);
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
take_aml_decision_run (void *cls,
                       const struct TALER_TESTING_Command *cmd,
                       struct TALER_TESTING_Interpreter *is)
{
  struct AmlDecisionState *ds = cls;
  struct GNUNET_TIME_Timestamp now;
  struct TALER_MasterSignatureP master_sig;

  (void) cmd;
  now = GNUNET_TIME_timestamp_get ();
  ds->is = is;
  TALER_exchange_offline_take_aml_decision_sign (&is->auditor_pub,
                                                 is->auditor_url,
                                                 now,
                                                 &is->master_priv,
                                                 &master_sig);
  ds->dh = TALER_EXCHANGE_management_enable_auditor (
    is->ctx,
    is->exchange_url,
    &is->auditor_pub,
    is->auditor_url,
    "test-case auditor", /* human-readable auditor name */
    now,
    &master_sig,
    &take_aml_decision_cb,
    ds);
  if (NULL == ds->dh)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "take_aml_decision" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct AmlDecisionState`.
 * @param cmd the command which is being cleaned up.
 */
static void
take_aml_decision_cleanup (void *cls,
                           const struct TALER_TESTING_Command *cmd)
{
  struct AmlDecisionState *ds = cls;

  if (NULL != ds->dh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ds->is->ip,
                cmd->label);
    TALER_EXCHANGE_management_enable_auditor_cancel (ds->dh);
    ds->dh = NULL;
  }
  GNUNET_free (ds);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_take_aml_decision (
  const char *label,
  const char *ref_officer,
  const char *ref_operation,
  const char *new_threshold,
  bool block)
{
  struct AmlDecisionState *ds;

  ds = GNUNET_new (struct AmlDecisionState);
  ds->ref_cmd = ref_cmd;
  ds->name = name;
  ds->is_active = is_active;
  ds->read_only = read_only;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ds,
      .label = label,
      .run = &take_aml_decision_run,
      .cleanup = &take_aml_decision_cleanup
                 // FIXME: expose trait with officer-priv here!
    };

    return cmd;
  }
}


/* end of testing_api_cmd_take_aml_decision.c */
