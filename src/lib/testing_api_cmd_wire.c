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
 * @file lib/testing_api_cmd_wire.c
 * @brief command for testing /wire.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_testing_lib.h"


/**
 * State for a "wire" CMD.
 */
struct WireState
{

  /**
   * Handle to the /wire operation.
   */
  struct TALER_EXCHANGE_WireHandle *wh;

  /**
   * Which wire-method we expect is offered by the exchange.
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
};


/**
 * Check whether the HTTP response code is acceptable, that
 * the expected wire method is offered by the exchange, and
 * that the wire fee is acceptable too.
 *
 * @param cls closure.
 * @param http_status HTTP response code.
 * @param ec taler-specific error code.
 * @param accounts_len length of the @a accounts array.
 * @param accounts list of wire accounts of the exchange,
 *        NULL on error.
 */
static void
wire_cb (void *cls,
         unsigned int http_status,
         enum TALER_ErrorCode ec,
         unsigned int accounts_len,
         const struct TALER_EXCHANGE_WireAccount *accounts)
{
  struct WireState *ws = cls;
  struct TALER_TESTING_Command *cmd = \
    &ws->is->commands[ws->is->ip];
  struct TALER_Amount expected_fee;

  TALER_LOG_DEBUG ("Checking parsed /wire response\n");
  ws->wh = NULL;
  if (ws->expected_response_code != http_status)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (ws->is);
    return;
  }

  if (MHD_HTTP_OK == http_status)
  {
    for (unsigned int i = 0; i<accounts_len; i++)
    {
      char *method;

      method = TALER_payto_get_method (accounts[i].url);
      if (0 == strcmp (ws->expected_method,
                       method))
      {
        ws->method_found = GNUNET_OK;
        if (NULL != ws->expected_fee)
        {
          GNUNET_assert
            (GNUNET_OK ==
            TALER_string_to_amount (ws->expected_fee,
                                    &expected_fee));
          const struct TALER_EXCHANGE_WireAggregateFees *waf;
          for (waf = accounts[i].fees;
               NULL != waf;
               waf = waf->next)
          {
            if (0 != TALER_amount_cmp (&waf->wire_fee,
                                       &expected_fee))
            {
              GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                          "Wire fee missmatch to command %s\n",
                          cmd->label);
              TALER_TESTING_interpreter_fail (ws->is);
              GNUNET_free (method);
              return;
            }
          }
        }
      }
      TALER_LOG_DEBUG ("Freeing method '%s'\n",
                       method);
      GNUNET_free (method);
    }
    if (GNUNET_OK != ws->method_found)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "/wire does not offer method '%s'\n",
                  ws->expected_method);
      TALER_TESTING_interpreter_fail (ws->is);
      return;
    }
  }

  TALER_TESTING_interpreter_next (ws->is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
wire_run (void *cls,
          const struct TALER_TESTING_Command *cmd,
          struct TALER_TESTING_Interpreter *is)
{
  struct WireState *ws = cls;
  ws->is = is;
  ws->wh = TALER_EXCHANGE_wire (is->exchange,
                                &wire_cb,
                                ws);
}


/**
 * Cleanup the state of a "wire" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
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
 * Create a "wire" command.
 *
 * @param label the command label.
 * @param expected_method which wire-transfer method is expected
 *        to be offered by the exchange.
 * @param expected_fee the fee the exchange should charge.
 * @param expected_response_code the HTTP response the exchange
 *        should return.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_wire (const char *label,
                        const char *expected_method,
                        const char *expected_fee,
                        unsigned int expected_response_code)
{
  struct WireState *ws;

  ws = GNUNET_new (struct WireState);
  ws->expected_method = expected_method;
  ws->expected_fee = expected_fee;
  ws->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ws,
      .label = label,
      .run = &wire_run,
      .cleanup = &wire_cleanup
    };

    return cmd;
  }
}
