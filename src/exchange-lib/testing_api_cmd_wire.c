/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

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
 * @file exchange-lib/testing_api_cmd_wire.c
 * @brief command for testing /wire.
 * @author Marcello Stanisci
 */

#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_testing_lib.h"

struct WireState
{

  /**
   * Handle to the /wire operation.
   */
  struct TALER_EXCHANGE_WireHandle *wh;

  /**
   * Which wire-method we expect are offered by the exchange.
   */
  const char *expected_method;

  /**
   * Flag indicating if the expected method is actually
   * offered.
   */
  unsigned int method_found;

  /**
   * Fee we expect is charged for this wire-transfer method.
   */
  const char *expected_fee;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Connection to the exchange.
   */
  struct TALER_EXCHANGE_Handle *exchange;
};


/**
 * Check all the expected values have been returned by /wire.
 *
 * @param cls closure
 * @param wire_method name of the wire method (i.e. "sepa")
 * @param fees fee structure for this method
 */
static void
check_method_and_fee_cb
  (void *cls,
   const char *wire_method,
   const struct TALER_EXCHANGE_WireAggregateFees *fees);

/**
 * Callbacks called with the result(s) of a wire format inquiry
 * request to the exchange.
 *
 * @param cls closure with the interpreter state
 * @param http_status HTTP response code, #MHD_HTTP_OK (200)
 *                    for successful request; 0 if the exchange's
 *                    reply is bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param obj the received JSON reply, if successful this should
 *            be the wire format details as provided by /wire.
 */
static void
wire_cb (void *cls,
         unsigned int http_status,
	 enum TALER_ErrorCode ec,
         const json_t *obj)
{
  struct WireState *ws = cls;
  struct TALER_TESTING_Command *cmd
    = &ws->is->commands[ws->is->ip];

  /**
   * The handle has been free'd by GNUnet curl-lib. FIXME:
   * shouldn't GNUnet nullify it once it frees it?
   */
  ws->wh = NULL;
  if (ws->expected_response_code != http_status)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (ws->is);
    return;
  }

  if (GNUNET_OK != TALER_EXCHANGE_wire_get_fees
       (&TALER_EXCHANGE_get_keys (ws->exchange)->master_pub,
        obj,
        // will check synchronously.
        &check_method_and_fee_cb,
        ws))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Wire fee extraction in command %s failed\n",
                cmd->label);
    json_dumpf (obj, stderr, 0);
    TALER_TESTING_interpreter_fail (ws->is);
    return;
  }

  if (ws->method_found != GNUNET_OK)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "/wire does not offer method '%s'\n",
                ws->expected_method);
    TALER_TESTING_interpreter_fail (ws->is);
    return;
  }
  TALER_TESTING_interpreter_next (ws->is);
}

/**
 * Check all the expected values have been returned by /wire.
 *
 * @param cls closure
 * @param wire_method name of the wire method (i.e. "sepa")
 * @param fees fee structure for this method
 */
static void
check_method_and_fee_cb
  (void *cls,
   const char *wire_method,
   const struct TALER_EXCHANGE_WireAggregateFees *fees)
{
  struct WireState *ws = cls;
  struct TALER_TESTING_Command *cmd
    = &ws->is->commands[ws->is->ip]; // ugly?
  struct TALER_Amount expected_fee;

  if (0 == strcmp (ws->expected_method, wire_method))
    ws->method_found = GNUNET_OK;

  if ( ws->expected_fee && (ws->method_found == GNUNET_OK) )
  {
    GNUNET_assert (GNUNET_OK == TALER_string_to_amount
                     (ws->expected_fee,
                      &expected_fee));
    while (NULL != fees)
    {
      if (0 != TALER_amount_cmp (&fees->wire_fee,
                                 &expected_fee))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Wire fee missmatch to command %s\n",
                    cmd->label);
        TALER_TESTING_interpreter_fail (ws->is);
        return;
      }
      fees = fees->next;
    }
  }
}

/**
 * Run the command.
 *
 * @param cls closure, typically a #struct WireState.
 * @param cmd the command to execute, a /wire one.
 * @param i the interpreter state.
 */
void
wire_run (void *cls,
          const struct TALER_TESTING_Command *cmd,
          struct TALER_TESTING_Interpreter *i)
{
  struct WireState *ws = cls;
  ws->is = i;
  ws->wh = TALER_EXCHANGE_wire (ws->exchange,
                                &wire_cb,
                                ws);
}


/**
 * Cleanup the state.
 *
 * @param cls closure, typically a #struct WireState.
 * @param cmd the command which is being cleaned up.
 */
void
wire_cleanup (void *cls,
              const struct TALER_TESTING_Command *cmd)
{
  struct WireState *ws = cls;

  if (NULL != ws->wh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ws->is->ip,
                cmd->label);
    TALER_EXCHANGE_wire_cancel (ws->wh);
    ws->wh = NULL;
  }
  GNUNET_free (ws);
}

/**
 * Create a /wire command.
 *
 * @param label the command label.
 * @param exchange the exchange to connect to.
 * @param expected_method which wire-transfer method is expected
 *        to be offered by the exchange.
 * @param expected_fee the fee the exchange should charge.
 * @param expected_response_code the HTTP response the exchange
 *        should return.
 *
 * @return the command to be executed by the interpreter.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_wire (const char *label,
                        struct TALER_EXCHANGE_Handle *exchange,
                        const char *expected_method,
                        const char *expected_fee,
                        unsigned int expected_response_code)
{
  struct TALER_TESTING_Command cmd;
  struct WireState *ws;

  ws = GNUNET_new (struct WireState);
  ws->exchange = exchange;
  ws->expected_method = expected_method;
  ws->expected_fee = expected_fee;
  ws->expected_response_code = expected_response_code;

  cmd.cls = ws;
  cmd.label = label;
  cmd.run = &wire_run;
  cmd.cleanup = &wire_cleanup;

  return cmd;
}
