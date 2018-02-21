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
 * @file exchange/testing_api_cmd_payback.c
 * @brief Implement the /revoke and /payback test commands.
 * @author Marcello Stanisci
 */

#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_testing_lib.h"

struct RevokeState
{
  /** 
   * Expected HTTP status code.
   */
  unsigned int expected_response_code;

  /**
   * Command that offers a denomination to revoke.
   */
  const char *coin_reference;

  /**
   * The interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * The revoke process handle.
   */
  struct GNUNET_OS_Process *revoke_proc;

  /**
   * Configuration filename.
   */
  const char *config_filename;

  /**
   * Encoding of the denomination (to revoke) public key hash.
   */
  char *dhks;

};

struct PaybackState
{
  /** 
   * Expected HTTP status code.
   */
  unsigned int expected_response_code;

  /**
   * Command that offers a reserve private key plus a
   * coin to be paid back.
   */
  const char *coin_reference;

  /**
   * The interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Amount expected to be paid back.
   */
  const char *amount;

  /**
   * Connection to the exchange.
   */
  struct TALER_EXCHANGE_Handle *exchange;

  /**
   * Handle to the ongoing operation.
   */
  struct TALER_EXCHANGE_PaybackHandle *ph;

};

/**
 * Check the result of the payback request.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for
 *        successful status request; 0 if the exchange's reply is
 *        bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param amount amount the exchange will wire back for this coin
 * @param timestamp what time did the exchange receive the
 *        /payback request
 * @param reserve_pub public key of the reserve receiving the
 *        payback
 * @param full_response full response from the exchange (for
 *        logging, in case of errors)
 */
static void
payback_cb (void *cls,
            unsigned int http_status,
            enum TALER_ErrorCode ec,
            const struct TALER_Amount *amount,
            struct GNUNET_TIME_Absolute timestamp,
            const struct TALER_ReservePublicKeyP *reserve_pub,
            const json_t *full_response)
{

  struct PaybackState *ps = cls;
  struct TALER_TESTING_Interpreter *is = ps->is;
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];
  const struct TALER_TESTING_Command *reserve_cmd;
  struct TALER_ReservePrivateKeyP *reserve_priv;
  struct TALER_ReservePublicKeyP rp;
  struct TALER_Amount expected_amount;

  ps->ph = NULL;
  if (ps->expected_response_code != http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u to command %s\n",
                http_status,
                cmd->label);
    json_dumpf (full_response, stderr, 0);
    fprintf (stderr, "\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  reserve_cmd = TALER_TESTING_interpreter_lookup_command
    (is, ps->coin_reference);

  if (NULL == reserve_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  
  if (GNUNET_OK != TALER_TESTING_get_trait_reserve_priv
    (reserve_cmd, 0, &reserve_priv))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                      &rp.eddsa_pub);

  switch (http_status)
  {
  case MHD_HTTP_OK:
    if (GNUNET_OK != TALER_string_to_amount
      (ps->amount, &expected_amount))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if (0 != TALER_amount_cmp (amount, &expected_amount))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Total amount missmatch to command %s\n",
                  cmd->label);
      json_dumpf (full_response, stderr, 0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if (0 != memcmp (reserve_pub, &rp,
                     sizeof (struct TALER_ReservePublicKeyP)))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    break;
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Unmanaged HTTP status code.\n");
    break;
  }
  TALER_TESTING_interpreter_next (is);
}

/**
 * Run the command.
 *
 * @param cls closure, typically a #struct WireState.
 * @param cmd the command to execute, a /wire one.
 * @param is the interpreter state.
 */
void
payback_run (void *cls,
             const struct TALER_TESTING_Command *cmd,
             struct TALER_TESTING_Interpreter *is)
{
  struct PaybackState *ps = cls;
  const struct TALER_TESTING_Command *coin_cmd;
  struct TALER_CoinSpendPrivateKeyP *coin_priv;
  struct TALER_DenominationBlindingKeyP *blinding_key;
  const struct TALER_EXCHANGE_DenomPublicKey *denom_pub;
  struct TALER_DenominationSignature *coin_sig;
  struct TALER_PlanchetSecretsP planchet;

  ps->is = is;
  ps->exchange = is->exchange;
  coin_cmd = TALER_TESTING_interpreter_lookup_command
    (is, ps->coin_reference);

  if (NULL == coin_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;  
  }

  if (GNUNET_OK != TALER_TESTING_get_trait_coin_priv
    (coin_cmd, 0, &coin_priv))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return; 
  }

  if (GNUNET_OK != TALER_TESTING_get_trait_blinding_key
    (coin_cmd, 0, &blinding_key))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return; 
  }
  planchet.coin_priv = *coin_priv;
  planchet.blinding_key = *blinding_key;

  if (GNUNET_OK != TALER_TESTING_get_trait_denom_pub
    (coin_cmd, 0, &denom_pub))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return; 
  }

  if (GNUNET_OK != TALER_TESTING_get_trait_denom_sig
     (coin_cmd, 0, &coin_sig))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return; 
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Trying to get '%s..' paid back\n",
              TALER_B2S (&denom_pub->h_key));
  
  ps->ph = TALER_EXCHANGE_payback (ps->exchange,
                                   denom_pub,
                                   coin_sig,
                                   &planchet,
                                   payback_cb,
                                   ps);
  GNUNET_assert (NULL != ps->ph);
}

/**
 * Cleanup the state.
 *
 * @param cls closure, typically a #struct WireState.
 * @param cmd the command which is being cleaned up.
 */
void
revoke_cleanup (void *cls,
                const struct TALER_TESTING_Command *cmd)
{

  struct RevokeState *rs = cls;

  if (NULL != rs->revoke_proc)
  {
    GNUNET_break (0 == GNUNET_OS_process_kill
      (rs->revoke_proc, SIGKILL));
    GNUNET_OS_process_wait (rs->revoke_proc);
    GNUNET_OS_process_destroy (rs->revoke_proc);
    rs->revoke_proc = NULL;
  }

  GNUNET_free (rs->dhks);
  GNUNET_free (rs);
}

/**
 * Cleanup the state.
 *
 * @param cls closure, typically a #struct WireState.
 * @param cmd the command which is being cleaned up.
 */
void
payback_cleanup (void *cls,
                 const struct TALER_TESTING_Command *cmd)
{
  struct PaybackState *ps = cls;
  if (NULL != ps->ph)
  {
    TALER_EXCHANGE_payback_cancel (ps->ph);
    ps->ph = NULL;
  }
  GNUNET_free (ps);
}

/**
 * Extract information from a command that is useful for other
 * commands.
 *
 * @param cls closure
 * @param ret[out] result (could be anything)
 * @param trait name of the trait
 * @param selector more detailed information about which object
 *                 to return in case there were multiple generated
 *                 by the command
 * @return #GNUNET_OK on success
 */
static int
revoke_traits (void *cls,
               void **ret,
               const char *trait,
               unsigned int index)
{

  struct RevokeState *rs = cls;

  struct TALER_TESTING_Trait traits[] = {
    /* Needed by the handler which waits the proc'
     * death and calls the next command */
    TALER_TESTING_make_trait_process (0, &rs->revoke_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}

/**
 * Run the command.
 *
 * @param cls closure, typically a #struct WireState.
 * @param cmd the command to execute, a /wire one.
 * @param is the interpreter state.
 */
void
revoke_run (void *cls,
            const struct TALER_TESTING_Command *cmd,
            struct TALER_TESTING_Interpreter *is)
{
  struct RevokeState *rs = cls;
  const struct TALER_TESTING_Command *coin_cmd;
  const struct TALER_EXCHANGE_DenomPublicKey *denom_pub;

  rs->is = is;
  /* Get denom pub from trait */
  coin_cmd = TALER_TESTING_interpreter_lookup_command
    (is, rs->coin_reference);

  if (NULL == coin_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;  
  }

  GNUNET_assert (GNUNET_OK == TALER_TESTING_get_trait_denom_pub
    (coin_cmd, 0, &denom_pub));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Trying to revoke denom '%s..'\n",
              TALER_B2S (&denom_pub->h_key));

  rs->dhks = GNUNET_STRINGS_data_to_string_alloc
    (&denom_pub->h_key, sizeof (struct GNUNET_HashCode)); 
  
  rs->revoke_proc = GNUNET_OS_start_process
    (GNUNET_NO,
     GNUNET_OS_INHERIT_STD_ALL,
     NULL, NULL, NULL,
     "taler-exchange-keyup",
     "taler-exchange-keyup",
     "-c", rs->config_filename,
     "-r", rs->dhks,
     NULL);


  if (NULL == rs->revoke_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Revoke is ongoing..\n");

  is->reload_keys = GNUNET_OK;
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Make a /payback command.
 *
 * @param label the command label
 * @param expected_response_code expected HTTP status code
 * @param coin_reference reference to any command which
 *        offers a reserve private key
 * @param amount denomination to pay back.
 *
 * @return a /revoke command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_payback (const char *label,
                           unsigned int expected_response_code,
                           const char *coin_reference,
                           const char *amount)
{
  struct PaybackState *ps;
  struct TALER_TESTING_Command cmd;
  
  ps = GNUNET_new (struct PaybackState);
  ps->expected_response_code = expected_response_code;
  ps->coin_reference = coin_reference;
  ps->amount = amount;

  cmd.cls = ps;
  cmd.label = label;
  cmd.run = &payback_run;
  cmd.cleanup = &payback_cleanup;

  return cmd;
}

/**
 * Make a /revoke command.
 *
 * @param label the command label
 * @param expected_response_code expected HTTP status code
 * @param coin_reference reference to any command which offers
 *        a coin trait
 * @param config_filename configuration file name.
 *
 * @return a /revoke command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_revoke (const char *label,
                          unsigned int expected_response_code,
                          const char *coin_reference,
                          const char *config_filename)
{

  struct RevokeState *rs;
  struct TALER_TESTING_Command cmd;

  rs = GNUNET_new (struct RevokeState);
  rs->expected_response_code = expected_response_code;
  rs->coin_reference = coin_reference;
  rs->config_filename = config_filename;

  cmd.cls = rs;
  cmd.label = label;
  cmd.run = &revoke_run;
  cmd.cleanup = &revoke_cleanup;
  cmd.traits = &revoke_traits;

  return cmd;
}
