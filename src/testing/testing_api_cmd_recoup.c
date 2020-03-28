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
 * @file testing/testing_api_cmd_recoup.c
 * @brief Implement the /recoup test command.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"


/**
 * State for a "pay back" CMD.
 */
struct RecoupState
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
   * Handle to the ongoing operation.
   */
  struct TALER_EXCHANGE_RecoupHandle *ph;

  /**
   * NULL if coin was not refreshed, otherwise reference
   * to the melt operation underlying @a coin_reference.
   */
  const char *melt_reference;

  /**
   * If the recoup filled a reserve, this is set to the reserve's public key.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Reserve history entry, set if this recoup actually filled up a reserve.
   * Otherwise `reserve_history.type` will be zero.
   */
  struct TALER_EXCHANGE_ReserveHistory reserve_history;

};


/**
 * Parser reference to a coin.
 *
 * @param coin_reference of format $LABEL['#' $INDEX]?
 * @param[out] cref where we return a copy of $LABEL
 * @param[out] idx where we set $INDEX
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
 * Check the result of the recoup request: checks whether
 * the HTTP response code is good, and that the coin that
 * was paid back belonged to the right reserve.
 *
 * @param cls closure
 * @param http_status HTTP response code.
 * @param ec taler-specific error code.
 * @param reserve_pub public key of the reserve receiving the recoup, NULL if refreshed or on error
 * @param old_coin_pub public key of the dirty coin, NULL if not refreshed or on error
 * @param full_response raw response from the exchange.
 */
static void
recoup_cb (void *cls,
           unsigned int http_status,
           enum TALER_ErrorCode ec,
           const struct TALER_ReservePublicKeyP *reserve_pub,
           const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
           const json_t *full_response)
{
  struct RecoupState *ps = cls;
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

  reserve_cmd = TALER_TESTING_interpreter_lookup_command (is,
                                                          cref);
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
    /* check old_coin_pub or reserve_pub, respectively */
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

      if (NULL == reserve_pub)
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      if (GNUNET_OK !=
          TALER_TESTING_get_trait_reserve_priv (reserve_cmd,
                                                idx,
                                                &reserve_priv))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                          &ps->reserve_pub.eddsa_pub);
      if (0 != GNUNET_memcmp (reserve_pub,
                              &ps->reserve_pub))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      if (GNUNET_OK ==
          TALER_amount_is_valid (&ps->reserve_history.amount))
        ps->reserve_history.type = TALER_EXCHANGE_RTT_RECOUP;
      /* ps->reserve_history.details.recoup_details.coin_pub; // initialized earlier */
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
recoup_run (void *cls,
            const struct TALER_TESTING_Command *cmd,
            struct TALER_TESTING_Interpreter *is)
{
  struct RecoupState *ps = cls;
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

  coin_cmd = TALER_TESTING_interpreter_lookup_command (is,
                                                       cref);
  GNUNET_free (cref);

  if (NULL == coin_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  if (GNUNET_OK !=
      TALER_TESTING_get_trait_coin_priv (coin_cmd,
                                         idx,
                                         &coin_priv))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  if (GNUNET_OK !=
      TALER_TESTING_get_trait_blinding_key (coin_cmd,
                                            idx,
                                            &blinding_key))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  planchet.coin_priv = *coin_priv;
  planchet.blinding_key = *blinding_key;
  GNUNET_CRYPTO_eddsa_key_get_public (
    &coin_priv->eddsa_priv,
    &ps->reserve_history.details.recoup_details.coin_pub.eddsa_pub);

  if (GNUNET_OK !=
      TALER_TESTING_get_trait_denom_pub (coin_cmd,
                                         idx,
                                         &denom_pub))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  if (GNUNET_OK !=
      TALER_TESTING_get_trait_denom_sig (coin_cmd,
                                         idx,
                                         &coin_sig))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Trying to recoup denomination '%s'\n",
              TALER_B2S (&denom_pub->h_key));

  ps->ph = TALER_EXCHANGE_recoup (is->exchange,
                                  denom_pub,
                                  coin_sig,
                                  &planchet,
                                  NULL != ps->melt_reference,
                                  recoup_cb,
                                  ps);
  GNUNET_assert (NULL != ps->ph);
}


/**
 * Cleanup the "recoup" CMD state, and possibly cancel
 * a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
recoup_cleanup (void *cls,
                const struct TALER_TESTING_Command *cmd)
{
  struct RecoupState *ps = cls;
  if (NULL != ps->ph)
  {
    TALER_EXCHANGE_recoup_cancel (ps->ph);
    ps->ph = NULL;
  }
  GNUNET_free (ps);
}


/**
 * Offer internal data from a "recoup" CMD state to other
 * commands.
 *
 * @param cls closure
 * @param[out] ret result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static int
recoup_traits (void *cls,
               const void **ret,
               const char *trait,
               unsigned int index)
{
  struct RecoupState *ps = cls;

  if (ps->reserve_history.type != TALER_EXCHANGE_RTT_RECOUP)
    return GNUNET_SYSERR; /* no traits */
  {
    struct TALER_TESTING_Trait traits[] = {
      TALER_TESTING_make_trait_reserve_pub (0,
                                            &ps->reserve_pub),
      TALER_TESTING_make_trait_reserve_history (0,
                                                &ps->reserve_history),
      TALER_TESTING_trait_end ()
    };

    return TALER_TESTING_get_trait (traits,
                                    ret,
                                    trait,
                                    index);
  }
}


/**
 * Make a "recoup" command.
 *
 * @param label the command label
 * @param expected_response_code expected HTTP status code
 * @param coin_reference reference to any command which
 *        offers a coin & reserve private key.
 * @param melt_reference NULL if coin was not refreshed
 * @param amount how much do we expect to recoup?
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_recoup (const char *label,
                          unsigned int expected_response_code,
                          const char *coin_reference,
                          const char *melt_reference,
                          const char *amount)
{
  struct RecoupState *ps;

  ps = GNUNET_new (struct RecoupState);
  ps->expected_response_code = expected_response_code;
  ps->coin_reference = coin_reference;
  ps->melt_reference = melt_reference;
  if ( (NULL != amount) &&
       (GNUNET_OK !=
        TALER_string_to_amount (amount,
                                &ps->reserve_history.amount)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to parse amount `%s' at %s\n",
                amount,
                label);
    GNUNET_assert (0);
  }
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ps,
      .label = label,
      .run = &recoup_run,
      .cleanup = &recoup_cleanup,
      .traits = &recoup_traits
    };

    return cmd;
  }
}
