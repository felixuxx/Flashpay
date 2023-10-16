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
 * @file testing/testing_api_cmd_reserve_attest.c
 * @brief Implement the /reserve/$RID/attest test command.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"

/**
 * State for a "attest" CMD.
 */
struct AttestState
{
  /**
   * Label to the command which created the reserve to check,
   * needed to resort the reserve key.
   */
  const char *reserve_reference;

  /**
   * Handle to the "reserve attest" operation.
   */
  struct TALER_EXCHANGE_ReservesAttestHandle *rsh;

  /**
   * Private key of the reserve being analyzed.
   */
  const struct TALER_ReservePrivateKeyP *reserve_priv;

  /**
   * Public key of the reserve being analyzed.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Array of attributes to request, of length @e attrs_len.
   */
  const char **attrs;

  /**
   * Length of the @e attrs array.
   */
  unsigned int attrs_len;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /* TODO: expose fields below as traits... */

  /**
   * Attested attributes returned by the exchange.
   */
  json_t *attributes;

  /**
   * Expiration time of the attested attributes.
   */
  struct GNUNET_TIME_Timestamp expiration_time;

  /**
   * Signature by the exchange affirming the attributes.
   */
  struct TALER_ExchangeSignatureP exchange_sig;

  /**
   * Online signing key used by the exchange.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;
};


/**
 * Check that the reserve balance and HTTP response code are
 * both acceptable.
 *
 * @param cls closure.
 * @param rs HTTP response details
 */
static void
reserve_attest_cb (
  void *cls,
  const struct TALER_EXCHANGE_ReservePostAttestResult *rs)
{
  struct AttestState *ss = cls;
  struct TALER_TESTING_Interpreter *is = ss->is;

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
  ss->attributes = json_incref ((json_t*) rs->details.ok.attributes);
  ss->expiration_time = rs->details.ok.expiration_time;
  ss->exchange_pub = rs->details.ok.exchange_pub;
  ss->exchange_sig = rs->details.ok.exchange_sig;
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
attest_run (void *cls,
            const struct TALER_TESTING_Command *cmd,
            struct TALER_TESTING_Interpreter *is)
{
  struct AttestState *ss = cls;
  const struct TALER_TESTING_Command *create_reserve;
  const char *exchange_url;

  ss->is = is;
  exchange_url = TALER_TESTING_get_exchange_url (is);
  if (NULL == exchange_url)
  {
    GNUNET_break (0);
    return;
  }
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
    TALER_LOG_ERROR ("Failed to find reserve_priv for attest query\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_CRYPTO_eddsa_key_get_public (&ss->reserve_priv->eddsa_priv,
                                      &ss->reserve_pub.eddsa_pub);
  ss->rsh = TALER_EXCHANGE_reserves_attest (
    TALER_TESTING_interpreter_get_context (is),
    exchange_url,
    TALER_TESTING_get_keys (is),
    ss->reserve_priv,
    ss->attrs_len,
    ss->attrs,
    &reserve_attest_cb,
    ss);
}


/**
 * Cleanup the state from a "reserve attest" CMD, and possibly
 * cancel a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
attest_cleanup (void *cls,
                const struct TALER_TESTING_Command *cmd)
{
  struct AttestState *ss = cls;

  if (NULL != ss->rsh)
  {
    TALER_TESTING_command_incomplete (ss->is,
                                      cmd->label);
    TALER_EXCHANGE_reserves_attest_cancel (ss->rsh);
    ss->rsh = NULL;
  }
  json_decref (ss->attributes);
  GNUNET_free (ss->attrs);
  GNUNET_free (ss);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_reserve_attest (const char *label,
                                  const char *reserve_reference,
                                  unsigned int expected_response_code,
                                  ...)
{
  struct AttestState *ss;
  unsigned int num_args;
  const char *ea;
  va_list ap;

  num_args = 0;
  va_start (ap, expected_response_code);
  while (NULL != va_arg (ap, const char *))
    num_args++;
  va_end (ap);

  GNUNET_assert (NULL != reserve_reference);
  ss = GNUNET_new (struct AttestState);
  ss->reserve_reference = reserve_reference;
  ss->expected_response_code = expected_response_code;
  ss->attrs_len = num_args;
  ss->attrs = GNUNET_new_array (num_args,
                                const char *);
  num_args = 0;
  va_start (ap, expected_response_code);
  while (NULL != (ea = va_arg (ap, const char *)))
    ss->attrs[num_args++] = ea;
  va_end (ap);

  {
    struct TALER_TESTING_Command cmd = {
      .cls = ss,
      .label = label,
      .run = &attest_run,
      .cleanup = &attest_cleanup
    };

    return cmd;
  }
}
