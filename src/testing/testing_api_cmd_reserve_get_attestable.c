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
  struct TALER_EXCHANGE_ReservesGetAttestHandle *rgah;

  /**
   * Expected attestable attributes.
   */
  const char **expected_attestables;

  /**
   * Length of the @e expected_attestables array.
   */
  unsigned int expected_attestables_length;

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
reserve_get_attestable_cb (
  void *cls,
  const struct TALER_EXCHANGE_ReserveGetAttestResult *rs)
{
  struct GetAttestableState *ss = cls;
  struct TALER_TESTING_Interpreter *is = ss->is;

  ss->rgah = NULL;
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
  // FIXME: check returned list matches expectations!
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
  const struct TALER_TESTING_Command *ref_reserve;
  const struct TALER_ReservePrivateKeyP *reserve_priv;
  const struct TALER_ReservePublicKeyP *reserve_pub;
  struct TALER_EXCHANGE_Handle *exchange
    = TALER_TESTING_get_exchange (is);

  if (NULL == exchange)
    return;
  ss->is = is;
  ref_reserve
    = TALER_TESTING_interpreter_lookup_command (is,
                                                ss->reserve_reference);

  if (NULL == ref_reserve)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (GNUNET_OK ==
      TALER_TESTING_get_trait_reserve_priv (ref_reserve,
                                            &reserve_priv))
  {
    GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                        &ss->reserve_pub.eddsa_pub);
  }
  else
  {
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_reserve_pub (ref_reserve,
                                             &reserve_pub))
    {
      GNUNET_break (0);
      TALER_LOG_ERROR (
        "Failed to find reserve_priv for get_attestable query\n");
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    ss->reserve_pub = *reserve_pub;
  }
  ss->rgah = TALER_EXCHANGE_reserves_get_attestable (exchange,
                                                     &ss->reserve_pub,
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

  if (NULL != ss->rgah)
  {
    TALER_TESTING_command_incomplete (ss->is,
                                      cmd->label);
    TALER_EXCHANGE_reserves_get_attestable_cancel (ss->rgah);
    ss->rgah = NULL;
  }
  GNUNET_free (ss->expected_attestables);
  GNUNET_free (ss);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_reserve_get_attestable (const char *label,
                                          const char *reserve_reference,
                                          unsigned int expected_response_code,
                                          ...)
{
  struct GetAttestableState *ss;
  va_list ap;
  unsigned int num_expected;
  const char *ea;

  num_expected = 0;
  va_start (ap, expected_response_code);
  while (NULL != va_arg (ap, const char *))
    num_expected++;
  va_end (ap);

  GNUNET_assert (NULL != reserve_reference);
  ss = GNUNET_new (struct GetAttestableState);
  ss->reserve_reference = reserve_reference;
  ss->expected_response_code = expected_response_code;
  ss->expected_attestables_length = num_expected;
  ss->expected_attestables = GNUNET_new_array (num_expected,
                                               const char *);
  num_expected = 0;
  va_start (ap, expected_response_code);
  while (NULL != (ea = va_arg (ap, const char *)))
    ss->expected_attestables[num_expected++] = ea;
  va_end (ap);

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
