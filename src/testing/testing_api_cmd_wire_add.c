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
 * @file testing/testing_api_cmd_wire_add.c
 * @brief command for testing POST to /management/wire
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"


/**
 * State for a "wire_add" CMD.
 */
struct WireAddState
{

  /**
   * Wire enable handle while operation is running.
   */
  struct TALER_EXCHANGE_ManagementWireEnableHandle *dh;

  /**
   * Our interpreter.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Account to add.
   */
  const char *payto_uri;

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
 * Callback to analyze the /management/wire response, just used to check
 * if the response code is acceptable.
 *
 * @param cls closure.
 * @param hr HTTP response details
 */
static void
wire_add_cb (void *cls,
             const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct WireAddState *ds = cls;

  ds->dh = NULL;
  if (ds->expected_response_code != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
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
wire_add_run (void *cls,
              const struct TALER_TESTING_Command *cmd,
              struct TALER_TESTING_Interpreter *is)
{
  struct WireAddState *ds = cls;
  struct TALER_MasterSignatureP master_sig1;
  struct TALER_MasterSignatureP master_sig2;
  struct GNUNET_TIME_Timestamp now;

  (void) cmd;
  now = GNUNET_TIME_timestamp_get ();
  ds->is = is;
  if (ds->bad_sig)
  {
    memset (&master_sig1,
            42,
            sizeof (master_sig1));
    memset (&master_sig2,
            42,
            sizeof (master_sig2));
  }
  else
  {
    TALER_exchange_offline_wire_add_sign (ds->payto_uri,
                                          now,
                                          &is->master_priv,
                                          &master_sig1);
    TALER_exchange_wire_signature_make (ds->payto_uri,
                                        &is->master_priv,
                                        &master_sig2);
  }
  ds->dh = TALER_EXCHANGE_management_enable_wire (
    is->ctx,
    is->exchange_url,
    ds->payto_uri,
    now,
    &master_sig1,
    &master_sig2,
    &wire_add_cb,
    ds);
  if (NULL == ds->dh)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "wire_add" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct WireAddState`.
 * @param cmd the command which is being cleaned up.
 */
static void
wire_add_cleanup (void *cls,
                  const struct TALER_TESTING_Command *cmd)
{
  struct WireAddState *ds = cls;

  if (NULL != ds->dh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ds->is->ip,
                cmd->label);
    TALER_EXCHANGE_management_enable_wire_cancel (ds->dh);
    ds->dh = NULL;
  }
  GNUNET_free (ds);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_wire_add (const char *label,
                            const char *payto_uri,
                            unsigned int expected_http_status,
                            bool bad_sig)
{
  struct WireAddState *ds;

  ds = GNUNET_new (struct WireAddState);
  ds->expected_response_code = expected_http_status;
  ds->bad_sig = bad_sig;
  ds->payto_uri = payto_uri;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ds,
      .label = label,
      .run = &wire_add_run,
      .cleanup = &wire_add_cleanup
    };

    return cmd;
  }
}


/* end of testing_api_cmd_wire_add.c */
