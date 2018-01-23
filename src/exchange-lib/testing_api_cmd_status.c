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
 * @file exchange/testing_api_cmd_status.c
 * @brief Implement the /reserve/status test command.
 * @author Marcello Stanisci
 */

#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_testing_lib.h"

struct StatusState
{
  /**
   * Label to the command which created the reserve to check,
   * needed to resort the reserve key.
   */
   const char *reserve_reference;

  /**
   * Handle to a /reserve/status operation.
   */
  struct TALER_EXCHANGE_ReserveStatusHandle *rsh;

  /**
   * Expected reserve balance.
   */
  const char *expected_balance;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Handle to the exchange.
   */
  struct TALER_EXCHANGE_Handle *exchange;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;
};

/**
 * Check exchange returned expected values.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for
 *        successful status request 0 if the exchange's reply is
 *        bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param[in] json original response in JSON format (useful only
 *            for diagnostics)
 * @param balance current balance in the reserve, NULL on error
 * @param history_length number of entries in the transaction
 *        history, 0 on error
 * @param history detailed transaction history, NULL on error
 */
void
reserve_status_cb
  (void *cls,
   unsigned int http_status,
   enum TALER_ErrorCode ec,
   const json_t *json,
   const struct TALER_Amount *balance,
   unsigned int history_length,
   const struct TALER_EXCHANGE_ReserveHistory *history)
{
  struct StatusState *ss = cls;
  struct TALER_Amount eb;
  
  ss->rsh = NULL;
  if (ss->expected_response_code != http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected HTTP response code: %d\n",
                http_status);
    TALER_TESTING_interpreter_fail (ss->is);
    return;
  }

  GNUNET_assert (GNUNET_OK == TALER_string_to_amount
    (ss->expected_balance, &eb));

  if (0 != TALER_amount_cmp (&eb, balance))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected amount in reserve\n");
    TALER_TESTING_interpreter_fail (ss->is);
    return;
  }

/**
 * Fixme: need a way to check if reserve history is consistent.
 * Every command which relates to reserve 'x' should be added in
 * a linked list of all commands that relate to the same reserve
 * 'x'.
 *
 * API-wise, any command that relates to a reserve should offer a
 * method called e.g. "compare_with_history" that takes an element
 * of the array returned by "/reserve/status" and checks if that
 * element correspond to itself (= the command exposing the check-
 * method).
 */

  TALER_TESTING_interpreter_next (ss->is);
}

/**
 * Run the command.
 *
 * @param cls closure, typically a #struct WireState.
 * @param cmd the command to execute, a /wire one.
 * @param i the interpreter state.
 */
void
status_run (void *cls,
            const struct TALER_TESTING_Command *cmd,
            struct TALER_TESTING_Interpreter *is)
{

  struct StatusState *ss = cls;
  const struct TALER_TESTING_Command *create_reserve;
  struct TALER_ReservePrivateKeyP *reserve_priv;
  struct TALER_ReservePublicKeyP reserve_pub;

  ss->is = is;
  GNUNET_assert (NULL != ss->reserve_reference);

  create_reserve
    = TALER_TESTING_interpreter_lookup_command
      (is, ss->reserve_reference);

  if (NULL == create_reserve)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  if (GNUNET_OK !=
      TALER_TESTING_get_trait_reserve_priv (create_reserve,
                                            0,
                                            &reserve_priv))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv, 
                                      &reserve_pub.eddsa_pub);
  ss->rsh
    = TALER_EXCHANGE_reserve_status (ss->exchange,
                                     &reserve_pub,
                                     &reserve_status_cb,
                                     ss);
}

/**
 * Cleanup the state.
 *
 * @param cls closure, typically a #struct WireState.
 * @param cmd the command which is being cleaned up.
 */
void
status_cleanup (void *cls,
                const struct TALER_TESTING_Command *cmd)
{
  struct StatusState *ss = cls;

  if (NULL != ss->rsh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ss->is->ip,
                cmd->label);
    TALER_EXCHANGE_reserve_status_cancel (ss->rsh);
    ss->rsh = NULL;
  }
  GNUNET_free (ss);
}


/**
 * Create a /reserve/status command.
 *
 * @param label the command label.
 * @param exchange the exchange to connect to.
 * @param reserve_reference reference to the reserve to check.
 * @param expected_balance balance expected to be at the referenced reserve.
 * @param expected_response_code expected HTTP response code.
 *
 * @return the command to be executed by the interpreter.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_status (const char *label,
                          struct TALER_EXCHANGE_Handle *exchange,
                          const char *reserve_reference,
                          const char *expected_balance,
                          unsigned int expected_response_code)
{
  struct TALER_TESTING_Command cmd;
  struct StatusState *ss;

  ss = GNUNET_new (struct StatusState);
  ss->exchange = exchange;
  ss->reserve_reference = reserve_reference;
  ss->expected_balance = expected_balance;
  ss->expected_response_code = expected_response_code;

  cmd.cls = ss;
  cmd.label = label;
  cmd.run = &status_run;
  cmd.cleanup = &status_cleanup;

  return cmd;
}
