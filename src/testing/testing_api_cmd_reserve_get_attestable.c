/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file testing/testing_api_cmd_reserve_get_attestable.c
 * @brief Implement the /reserve/$RID/get_attestable test command.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"


/**
 * State for a "get_attestable" CMD.
 */
struct GetAttestableState
{
  /**
   * Label to the command which created the reserve to check,
   * needed to resort the reserve key.
   */
  const char *reserve_reference;

  /**
   * Handle to the "reserve get_attestable" operation.
   */
  struct TALER_EXCHANGE_ReservesGetAttestableHandle *rsh;

  /**
   * Expected reserve balance.
   */
  const char *expected_balance;

  /**
   * Private key of the reserve being analyzed.
   */
  const struct TALER_ReservePrivateKeyP *reserve_priv;

  /**
   * Public key of the reserve being analyzed.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

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
 * @param rs HTTP response details
 */
static void
reserve_get_attestable_cb (void *cls,
                           const struct TALER_EXCHANGE_ReserveGetAttestable *rs)
{
  struct GetAttestableState *ss = cls;
  struct TALER_TESTING_Interpreter *is = ss->is;
  struct TALER_Amount eb;

  ss->rsh = NULL;
  if (ss->expected_response_code != rs->hr.http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected HTTP response code: %d in %s:%u\n",
                rs->hr.http_status,
                __FILE__,
                __LINE__);
    json_dumpf (rs->hr.reply,
                stderr,
                JSON_INDENT (2));
    TALER_TESTING_interpreter_fail (ss->is);
    return;
  }
  if (MHD_HTTP_OK != rs->hr.http_status)
  {
    TALER_TESTING_interpreter_next (is);
    return;
  }
  TALER_TESTING_interpreter_next (is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command being executed.
 * @param is the interpreter state.
 */
static void
get_attestable_run (void *cls,
                    const struct TALER_TESTING_Command *cmd,
                    struct TALER_TESTING_Interpreter *is)
{
  struct GetAttestableState *ss = cls;
  const struct TALER_TESTING_Command *create_reserve;

  ss->is = is;
  create_reserve
    = TALER_TESTING_interpreter_lookup_command (is,
                                                ss->reserve_reference);

  if (NULL == create_reserve)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_reserve_priv (create_reserve,
                                            &ss->reserve_priv))
  {
    GNUNET_break (0);
    TALER_LOG_ERROR ("Failed to find reserve_priv for get_attestable query\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_CRYPTO_eddsa_key_get_public (&ss->reserve_priv->eddsa_priv,
                                      &ss->reserve_pub.eddsa_pub);
  ss->rsh = TALER_EXCHANGE_reserves_get_attestable (is->exchange,
                                                    ss->reserve_priv,
                                                    &reserve_get_attestable_cb,
                                                    ss);
}


/**
 * Cleanup the state from a "reserve get_attestable" CMD, and possibly
 * cancel a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
get_attestable_cleanup (void *cls,
                        const struct TALER_TESTING_Command *cmd)
{
  struct GetAttestableState *ss = cls;

  if (NULL != ss->rsh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ss->is->ip,
                cmd->label);
    TALER_EXCHANGE_reserves_get_attestable_cancel (ss->rsh);
    ss->rsh = NULL;
  }
  GNUNET_free (ss);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_reserve_get_attestable (const char *label,
                                          const char *reserve_reference,
                                          unsigned int expected_response_code,
                                          ...)
{
  struct GetAttestableState *ss;

  GNUNET_assert (NULL != reserve_reference);
  ss = GNUNET_new (struct GetAttestableState);
  ss->reserve_reference = reserve_reference;
  ss->expected_balance = expected_balance;
  ss->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ss,
      .label = label,
      .run = &get_attestable_run,
      .cleanup = &get_attestable_cleanup
    };

    return cmd;
  }
}
