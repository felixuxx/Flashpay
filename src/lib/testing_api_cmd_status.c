/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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


/**
 * State for a "status" CMD.
 */
struct StatusState
{
  /**
   * Label to the command which created the reserve to check,
   * needed to resort the reserve key.
   */
  const char *reserve_reference;

  /**
   * Handle to the "reserve status" operation.
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
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;
};


/**
 * Check that the reserve balance and HTTP response code are
 * both acceptable.
 *
 * @param cls closure.
 * @param http_status HTTP response code.
 * @param ec taler-specific error code.
 * @param balance current balance in the reserve, NULL on error.
 * @param history_length number of entries in the transaction
 *        history, 0 on error.
 * @param history detailed transaction history, NULL on error.
 */
static void
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
                "Unexpected HTTP response code: %d in %s:%u\n",
                http_status,
                __FILE__,
                __LINE__);
    TALER_TESTING_interpreter_fail (ss->is);
    return;
  }

  GNUNET_assert (GNUNET_OK == TALER_string_to_amount
                   (ss->expected_balance, &eb));

  if (0 != TALER_amount_cmp (&eb, balance))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected amount in reserve: %s\n",
                TALER_amount_to_string (balance));
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
 *
 * IDEA: Maybe realize this via another trait, some kind of
 * "reserve history update trait" which returns information about
 * how the command changes the history (provided only by commands
 * that change reserve balances)?
 */TALER_TESTING_interpreter_next (ss->is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command being executed.
 * @param is the interpreter state.
 */
static void
status_run (void *cls,
            const struct TALER_TESTING_Command *cmd,
            struct TALER_TESTING_Interpreter *is)
{
  struct StatusState *ss = cls;
  const struct TALER_TESTING_Command *create_reserve;
  const struct TALER_ReservePrivateKeyP *reserve_priv;
  struct TALER_ReservePublicKeyP reserve_pub;
  const struct TALER_ReservePublicKeyP *reserve_pubp;

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

  /* NOTE: the following line might generate a ERROR log
   * statements, but it can be ignored.  */
  if (GNUNET_OK ==
      TALER_TESTING_get_trait_reserve_priv (create_reserve,
                                            0,
                                            &reserve_priv))
  {
    GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                        &reserve_pub.eddsa_pub);
    reserve_pubp = &reserve_pub;
  }
  else
  {
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_reserve_pub (create_reserve,
                                             0,
                                             &reserve_pubp))
    {
      GNUNET_break (0);
      TALER_LOG_ERROR ("The reserve has neither a priv nor a pub.\n");
      TALER_TESTING_interpreter_fail (is);
      return;
    }
  }

  ss->rsh = TALER_EXCHANGE_reserve_status (is->exchange,
                                           reserve_pubp,
                                           &reserve_status_cb,
                                           ss);
}


/**
 * Cleanup the state from a "reserve status" CMD, and possibly
 * cancel a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
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
 * Create a "reserve status" command.
 *
 * @param label the command label.
 * @param reserve_reference reference to the reserve to check.
 * @param expected_balance expected balance for the reserve.
 * @param expected_response_code expected HTTP response code.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_status (const char *label,
                          const char *reserve_reference,
                          const char *expected_balance,
                          unsigned int expected_response_code)
{
  struct StatusState *ss;

  ss = GNUNET_new (struct StatusState);
  ss->reserve_reference = reserve_reference;
  ss->expected_balance = expected_balance;
  ss->expected_response_code = expected_response_code;

  struct TALER_TESTING_Command cmd = {
    .cls = ss,
    .label = label,
    .run = &status_run,
    .cleanup = &status_cleanup
  };

  return cmd;
}
