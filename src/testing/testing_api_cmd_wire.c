/*
  This file is part of TALER
  Copyright (C) 2018, 2023 Taler Systems SA

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
 * @file testing/testing_api_cmd_wire.c
 * @brief command for testing /wire.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
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
   * Our command.
   */
  const struct TALER_TESTING_Command *cmd;

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
 * @param wr response details
 */
static void
wire_cb (void *cls,
         const struct TALER_EXCHANGE_WireResponse *wr)
{
  struct WireState *ws = cls;
  const struct TALER_EXCHANGE_HttpResponse *hr = &wr->hr;
  struct TALER_Amount expected_fee;

  TALER_LOG_DEBUG ("Checking parsed /wire response\n");
  ws->wh = NULL;
  if (ws->expected_response_code != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Received unexpected status code %u\n",
                hr->http_status);
    TALER_TESTING_interpreter_fail (ws->is);
    return;
  }

  if (MHD_HTTP_OK == hr->http_status)
  {
    unsigned int accounts_len
      = wr->details.ok.accounts_len;
    unsigned int fees_len
      = wr->details.ok.fees_len;
    const struct TALER_EXCHANGE_WireAccount *accounts
      = wr->details.ok.accounts;
    const struct TALER_EXCHANGE_WireFeesByMethod *fees
      = wr->details.ok.fees;

    for (unsigned int i = 0; i<accounts_len; i++)
    {
      char *method;

      method = TALER_payto_get_method (accounts[i].payto_uri);
      if (NULL == method)
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (ws->is);
        return;
      }
      if (0 == strcmp (ws->expected_method,
                       method))
      {
        ws->method_found = GNUNET_OK;
      }
      GNUNET_free (method);
    }
    if (NULL != ws->expected_fee)
    {
      bool fee_found = false;

      GNUNET_assert (GNUNET_OK ==
                     TALER_string_to_amount (ws->expected_fee,
                                             &expected_fee));
      for (unsigned int i = 0; i<fees_len; i++)
      {
        if (0 != strcmp (fees[i].method,
                         ws->expected_method))
          continue;
        for (const struct TALER_EXCHANGE_WireAggregateFees *waf
               = fees[i].fees_head;
             NULL != waf;
             waf = waf->next)
        {
          if (0 != TALER_amount_cmp (&waf->fees.wire,
                                     &expected_fee))
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "Wire fee mismatch to command %s\n",
                        ws->cmd->label);
            TALER_TESTING_interpreter_fail (ws->is);
            return;
          }
          fee_found = true;
        }
      }
      if (! fee_found)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "/wire does not contain expected fee '%s'\n",
                    ws->expected_fee);
        TALER_TESTING_interpreter_fail (ws->is);
        return;
      }
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

  ws->cmd = cmd;
  ws->is = is;
  ws->wh = TALER_EXCHANGE_wire (
    TALER_TESTING_interpreter_get_context (is),
    TALER_TESTING_get_exchange_url (is),
    TALER_TESTING_get_keys (is),
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
    TALER_TESTING_command_incomplete (ws->is,
                                      cmd->label);
    TALER_EXCHANGE_wire_cancel (ws->wh);
    ws->wh = NULL;
  }
  GNUNET_free (ws);
}


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
