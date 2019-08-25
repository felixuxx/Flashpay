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


/**
 * State for a "revoke" CMD.
 */
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
   * Configuration file name.
   */
  const char *config_filename;

  /**
   * Encoding of the denomination (to revoke) public key hash.
   */
  char *dhks;

};


/**
 * State for a "pay back" CMD.
 */
struct PaybackState
{
  /**
   * Expected HTTP status code.
   */
  unsigned int expected_response_code;

  /**
   * Command that offers a reserve private key,
   * plus a coin to be paid back.
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
   * Handle to the ongoing operation.
   */
  struct TALER_EXCHANGE_PaybackHandle *ph;

  /**
   * NULL if coin was not refreshed, otherwise reference
   * to the melt operation underlying @a coin_reference.
   */
  const char *melt_reference;

};


/**
 * Parser reference to a coin.
 *
 * @param coin_reference of format $LABEL['#' $INDEX]?
 * @param cref[out] where we return a copy of $LABEL
 * @param idx[out] where we set $INDEX
 * @return #GNUNET_SYSERR if $INDEX is present but not numeric
 */
static int
parse_coin_reference (const char *coin_reference,
                      char **cref,
                      unsigned int *idx)
{
  const char *index;

  /* We allow command references of the form "$LABEL#$INDEX" or
     just "$LABEL", which implies the index is 0. Figure out
     which one it is. */
  index = strchr (coin_reference, '#');
  if (NULL == index)
  {
    *idx = 0;
    *cref = GNUNET_strdup (coin_reference);
    return GNUNET_OK;
  }
  *cref = GNUNET_strndup (coin_reference,
                          index - coin_reference);
  if (1 != sscanf (index + 1,
                   "%u",
                   idx))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Numeric index (not `%s') required after `#' in command reference of command in %s:%u\n",
                index,
                __FILE__,
                __LINE__);
    GNUNET_free (*cref);
    *cref = NULL;
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Check the result of the payback request: checks whether
 * the HTTP response code is good, and that the coin that
 * was paid back belonged to the right reserve.
 *
 * @param cls closure
 * @param http_status HTTP response code.
 * @param ec taler-specific error code.
 * @param amount amount the exchange will wire back for this coin.
 * @param timestamp what time did the exchange receive the
 *        /payback request
 * @param reserve_pub public key of the reserve receiving the payback, NULL if refreshed or on error
 * @param old_coin_pub public key of the dirty coin, NULL if not refreshed or on error
 * @param full_response raw response from the exchange.
 */
static void
payback_cb (void *cls,
            unsigned int http_status,
            enum TALER_ErrorCode ec,
            const struct TALER_Amount *amount,
            struct GNUNET_TIME_Absolute timestamp,
            const struct TALER_ReservePublicKeyP *reserve_pub,
            const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
            const json_t *full_response)
{
  struct PaybackState *ps = cls;
  struct TALER_TESTING_Interpreter *is = ps->is;
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];
  const struct TALER_TESTING_Command *reserve_cmd;
  char *cref;
  unsigned int idx;

  ps->ph = NULL;
  if (ps->expected_response_code != http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u to command %s in %s:%u\n",
                http_status,
                cmd->label,
                __FILE__,
                __LINE__);
    json_dumpf (full_response, stderr, 0);
    fprintf (stderr, "\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  if (GNUNET_OK !=
      parse_coin_reference (ps->coin_reference,
                            &cref,
                            &idx))
  {
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  reserve_cmd = TALER_TESTING_interpreter_lookup_command
                  (is, cref);
  GNUNET_free (cref);

  if (NULL == reserve_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  switch (http_status)
  {
  case MHD_HTTP_OK:
    /* first, check amount */
    {
      struct TALER_Amount expected_amount;

      if (GNUNET_OK !=
          TALER_string_to_amount (ps->amount, &expected_amount))
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
    }
    /* now, check old_coin_pub or reserve_pub, respectively */
    if (NULL != ps->melt_reference)
    {
      const struct TALER_TESTING_Command *melt_cmd;
      const struct TALER_CoinSpendPrivateKeyP *dirty_priv;
      struct TALER_CoinSpendPublicKeyP oc;

      melt_cmd = TALER_TESTING_interpreter_lookup_command (is,
                                                           ps->melt_reference);
      if (NULL == melt_cmd)
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      if (GNUNET_OK !=
          TALER_TESTING_get_trait_coin_priv (melt_cmd,
                                             0,
                                             &dirty_priv))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      GNUNET_CRYPTO_eddsa_key_get_public (&dirty_priv->eddsa_priv,
                                          &oc.eddsa_pub);
      if (0 != GNUNET_memcmp (&oc,
                              old_coin_pub))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
    }
    else
    {
      const struct TALER_ReservePrivateKeyP *reserve_priv;
      struct TALER_ReservePublicKeyP rp;

      if (NULL == reserve_pub)
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      if (GNUNET_OK != TALER_TESTING_get_trait_reserve_priv
            (reserve_cmd, idx, &reserve_priv))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                          &rp.eddsa_pub);
      if (0 != GNUNET_memcmp (reserve_pub, &rp))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
    }
    break;
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Unmanaged HTTP status code %u.\n",
                http_status);
    break;
  }
  TALER_TESTING_interpreter_next (is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
payback_run (void *cls,
             const struct TALER_TESTING_Command *cmd,
             struct TALER_TESTING_Interpreter *is)
{
  struct PaybackState *ps = cls;
  const struct TALER_TESTING_Command *coin_cmd;
  const struct TALER_CoinSpendPrivateKeyP *coin_priv;
  const struct TALER_DenominationBlindingKeyP *blinding_key;
  const struct TALER_EXCHANGE_DenomPublicKey *denom_pub;
  const struct TALER_DenominationSignature *coin_sig;
  struct TALER_PlanchetSecretsP planchet;
  char *cref;
  unsigned int idx;

  ps->is = is;
  if (GNUNET_OK !=
      parse_coin_reference (ps->coin_reference,
                            &cref,
                            &idx))
  {
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  coin_cmd = TALER_TESTING_interpreter_lookup_command
               (is, cref);
  GNUNET_free (cref);

  if (NULL == coin_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  if (GNUNET_OK != TALER_TESTING_get_trait_coin_priv
        (coin_cmd, idx, &coin_priv))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  if (GNUNET_OK != TALER_TESTING_get_trait_blinding_key
        (coin_cmd, idx, &blinding_key))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  planchet.coin_priv = *coin_priv;
  planchet.blinding_key = *blinding_key;

  if (GNUNET_OK != TALER_TESTING_get_trait_denom_pub
        (coin_cmd, idx, &denom_pub))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  if (GNUNET_OK != TALER_TESTING_get_trait_denom_sig
        (coin_cmd, idx, &coin_sig))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Trying to get '%s..' paid back\n",
              TALER_B2S (&denom_pub->h_key));

  ps->ph = TALER_EXCHANGE_payback (is->exchange,
                                   denom_pub,
                                   coin_sig,
                                   &planchet,
                                   NULL != ps->melt_reference,
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
static void
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

  GNUNET_free_non_null (rs->dhks);
  GNUNET_free (rs);
}


/**
 * Cleanup the "payback" CMD state, and possibly cancel
 * a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
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
 * Offer internal data from a "revoke" CMD to other CMDs.
 *
 * @param cls closure
 * @param ret[out] result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static int
revoke_traits (void *cls,
               const void **ret,
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
 * Run the "revoke" command.  The core of the function
 * is to call the "keyup" utility passing it the base32
 * encoding of the denomination to revoke.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
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
 * Make a "payback" command.
 *
 * @param label the command label
 * @param expected_response_code expected HTTP status code
 * @param coin_reference reference to any command which
 *        offers a coin & reserve private key.
 * @param amount denomination to pay back.
 * @param melt_reference NULL if coin was not refreshed
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_payback (const char *label,
                           unsigned int expected_response_code,
                           const char *coin_reference,
                           const char *amount,
                           const char *melt_reference)
{
  struct PaybackState *ps;

  ps = GNUNET_new (struct PaybackState);
  ps->expected_response_code = expected_response_code;
  ps->coin_reference = coin_reference;
  ps->amount = amount;
  ps->melt_reference = melt_reference;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ps,
      .label = label,
      .run = &payback_run,
      .cleanup = &payback_cleanup
    };

    return cmd;
  }
}


/**
 * Make a "revoke" command.
 *
 * @param label the command label.
 * @param expected_response_code expected HTTP status code.
 * @param coin_reference reference to a CMD that will offer the
 *        denomination to revoke.
 * @param config_filename configuration file name.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_revoke (const char *label,
                          unsigned int expected_response_code,
                          const char *coin_reference,
                          const char *config_filename)
{

  struct RevokeState *rs;

  rs = GNUNET_new (struct RevokeState);
  rs->expected_response_code = expected_response_code;
  rs->coin_reference = coin_reference;
  rs->config_filename = config_filename;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = rs,
      .label = label,
      .run = &revoke_run,
      .cleanup = &revoke_cleanup,
      .traits = &revoke_traits
    };

    return cmd;
  }
}
