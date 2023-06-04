/*
  This file is part of TALER
  Copyright (C) 2020, 2022 Taler Systems SA

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
 * @file testing/testing_api_cmd_set_wire_fee.c
 * @brief command for testing POST to /management/wire-fees
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
struct WireFeeState
{

  /**
   * Wire enable handle while operation is running.
   */
  struct TALER_EXCHANGE_ManagementSetWireFeeHandle *dh;

  /**
   * Our interpreter.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Wire method to configure fee for.
   */
  const char *wire_method;

  /**
   * Wire fee amount to use.
   */
  const char *wire_fee;

  /**
   * Closing fee amount to use.
   */
  const char *closing_fee;

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
 * @param sfr response details
 */
static void
wire_add_cb (void *cls,
             const struct TALER_EXCHANGE_ManagementSetWireFeeResponse *sfr)
{
  struct WireFeeState *ds = cls;
  const struct TALER_EXCHANGE_HttpResponse *hr = &sfr->hr;

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
  struct WireFeeState *ds = cls;
  struct TALER_MasterSignatureP master_sig;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Timestamp start_time;
  struct GNUNET_TIME_Timestamp end_time;
  struct TALER_WireFeeSet fees;

  (void) cmd;
  ds->is = is;
  now = GNUNET_TIME_absolute_get ();
  start_time = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_subtract (now,
                                   GNUNET_TIME_UNIT_HOURS));
  end_time = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (now,
                              GNUNET_TIME_UNIT_HOURS));
  if ( (GNUNET_OK !=
        TALER_string_to_amount (ds->closing_fee,
                                &fees.closing)) ||
       (GNUNET_OK !=
        TALER_string_to_amount (ds->wire_fee,
                                &fees.wire)) )
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  if (ds->bad_sig)
  {
    memset (&master_sig,
            42,
            sizeof (master_sig));
  }
  else
  {
    TALER_exchange_offline_wire_fee_sign (ds->wire_method,
                                          start_time,
                                          end_time,
                                          &fees,
                                          &is->master_priv,
                                          &master_sig);
  }
  ds->dh = TALER_EXCHANGE_management_set_wire_fees (
    is->ctx,
    is->exchange_url,
    ds->wire_method,
    start_time,
    end_time,
    &fees,
    &master_sig,
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
 * @param cls closure, must be a `struct WireFeeState`.
 * @param cmd the command which is being cleaned up.
 */
static void
wire_add_cleanup (void *cls,
                  const struct TALER_TESTING_Command *cmd)
{
  struct WireFeeState *ds = cls;

  if (NULL != ds->dh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ds->is->ip,
                cmd->label);
    TALER_EXCHANGE_management_set_wire_fees_cancel (ds->dh);
    ds->dh = NULL;
  }
  GNUNET_free (ds);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_set_wire_fee (const char *label,
                                const char *wire_method,
                                const char *wire_fee,
                                const char *closing_fee,
                                unsigned int expected_http_status,
                                bool bad_sig)
{
  struct WireFeeState *ds;

  ds = GNUNET_new (struct WireFeeState);
  ds->expected_response_code = expected_http_status;
  ds->bad_sig = bad_sig;
  ds->wire_method = wire_method;
  ds->wire_fee = wire_fee;
  ds->closing_fee = closing_fee;
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


/* end of testing_api_cmd_set_wire_fee.c */
