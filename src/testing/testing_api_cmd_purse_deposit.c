/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

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
 * @file testing/testing_api_cmd_purse_deposit.c
 * @brief command for testing /purses/$PID/create
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"

/**
 * Information we keep per deposited coin.
 */
struct Coin
{
  /**
   * Reference to the respective command.
   */
  char *command_ref;

  /**
   * index of the specific coin in the traits of @e command_ref.
   */
  unsigned int coin_index;

  /**
   * Amount to deposit (with fee).
   */
  struct TALER_Amount deposit_with_fee;

};


/**
 * State for a "purse deposit" CMD.
 */
struct PurseDepositState
{

  /**
   * Total purse target amount without fees.
   */
  struct TALER_Amount target_amount;

  /**
   * Reference to any command that is able to provide a coin.
   */
  struct Coin *coin_references;

  /**
   * The purse's public key.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * PurseDeposit handle while operation is running.
   */
  struct TALER_EXCHANGE_PurseDepositHandle *dh;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Reference to the command that established the purse.
   */
  const char *purse_ref;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Length of the @e coin_references array.
   */
  unsigned int num_coin_references;

  /**
   * Minimum age to apply to all deposits.
   */
  uint8_t min_age;
};


/**
 * Callback to analyze the /purses/$PID/deposit response, just used to check if
 * the response code is acceptable.
 *
 * @param cls closure.
 * @param dr deposit response details
 */
static void
deposit_cb (void *cls,
            const struct TALER_EXCHANGE_PurseDepositResponse *dr)
{
  struct PurseDepositState *ds = cls;

  ds->dh = NULL;
  if (ds->expected_response_code != dr->hr.http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u to command %s in %s:%u\n",
                dr->hr.http_status,
                ds->is->commands[ds->is->ip].label,
                __FILE__,
                __LINE__);
    json_dumpf (dr->hr.reply,
                stderr,
                0);
    TALER_TESTING_interpreter_fail (ds->is);
    return;
  }
  if (MHD_HTTP_OK == dr->hr.http_status)
  {
    // FIXME: any data to keep from reply?
  }
  TALER_TESTING_interpreter_next (ds->is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
deposit_run (void *cls,
             const struct TALER_TESTING_Command *cmd,
             struct TALER_TESTING_Interpreter *is)
{
  struct PurseDepositState *ds = cls;
  struct TALER_EXCHANGE_PurseDeposit deposits[ds->num_coin_references];
  const struct TALER_PurseContractPublicKeyP *purse_pub;
  const struct TALER_TESTING_Command *purse_cmd;

  (void) cmd;
  ds->is = is;

  purse_cmd = TALER_TESTING_interpreter_lookup_command (is,
                                                        ds->purse_ref);
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_purse_pub (purse_cmd,
                                         &purse_pub))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  ds->purse_pub = *purse_pub;
  for (unsigned int i = 0; i<ds->num_coin_references; i++)
  {
    const struct Coin *cr = &ds->coin_references[i];
    struct TALER_EXCHANGE_PurseDeposit *pd = &deposits[i];
    const struct TALER_TESTING_Command *coin_cmd;
    const struct TALER_CoinSpendPrivateKeyP *coin_priv;
    const struct TALER_AgeCommitmentProof *age_commitment_proof = NULL;
    struct TALER_AgeCommitmentHash h_age_commitment = {0};
    const struct TALER_EXCHANGE_DenomPublicKey *denom_pub;
    const struct TALER_DenominationSignature *denom_pub_sig;

    coin_cmd = TALER_TESTING_interpreter_lookup_command (is,
                                                         cr->command_ref);
    if (NULL == coin_cmd)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }

    if ( (GNUNET_OK !=
          TALER_TESTING_get_trait_coin_priv (coin_cmd,
                                             cr->coin_index,
                                             &coin_priv)) ||
         (GNUNET_OK !=
          TALER_TESTING_get_trait_age_commitment_proof (coin_cmd,
                                                        cr->coin_index,
                                                        &age_commitment_proof))
         ||
         (GNUNET_OK !=
          TALER_TESTING_get_trait_denom_pub (coin_cmd,
                                             cr->coin_index,
                                             &denom_pub)) ||
         (GNUNET_OK !=
          TALER_TESTING_get_trait_denom_sig (coin_cmd,
                                             cr->coin_index,
                                             &denom_pub_sig)) )
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if (NULL != age_commitment_proof)
    {
      TALER_age_commitment_hash (&age_commitment_proof->commitment,
                                 &h_age_commitment);
    }
#if FIXME_OEC
    pd->age_commitment = *h_age_commitment;
#endif
    pd->denom_sig = *denom_pub_sig;
    pd->coin_priv = *coin_priv;
    pd->amount = cr->deposit_with_fee;
    pd->h_denom_pub = denom_pub->h_key;
  }

  ds->dh = TALER_EXCHANGE_purse_deposit (
    is->exchange,
    NULL, /* FIXME: WADs support: purse exchange URL */
    &ds->purse_pub,
    ds->min_age,
    ds->num_coin_references,
    deposits,
    &deposit_cb,
    ds);
  if (NULL == ds->dh)
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not deposit into purse\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "deposit" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct PurseDepositState`.
 * @param cmd the command which is being cleaned up.
 */
static void
deposit_cleanup (void *cls,
                 const struct TALER_TESTING_Command *cmd)
{
  struct PurseDepositState *ds = cls;

  if (NULL != ds->dh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ds->is->ip,
                cmd->label);
    TALER_EXCHANGE_purse_deposit_cancel (ds->dh);
    ds->dh = NULL;
  }
  for (unsigned int i = 0; i<ds->num_coin_references; i++)
    GNUNET_free (ds->coin_references[i].command_ref);
  GNUNET_free (ds->coin_references);
  GNUNET_free (ds);
}


/**
 * Offer internal data from a "deposit" CMD, to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
deposit_traits (void *cls,
                const void **ret,
                const char *trait,
                unsigned int index)
{
  struct PurseDepositState *ds = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_purse_pub (&ds->purse_pub),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_purse_deposit_coins (
  const char *label,
  unsigned int expected_http_status,
  uint8_t min_age,
  const char *purse_ref,
  ...)
{
  struct PurseDepositState *ds;

  ds = GNUNET_new (struct PurseDepositState);
  ds->expected_response_code = expected_http_status;
  ds->min_age = min_age;
  ds->purse_ref = purse_ref;
  {
    va_list ap;
    unsigned int i;
    const char *ref;
    const char *val;

    va_start (ap, purse_ref);
    while (NULL != (va_arg (ap, const char *)))
      ds->num_coin_references++;
    va_end (ap);
    GNUNET_assert (0 == (ds->num_coin_references % 2));
    ds->num_coin_references /= 2;
    ds->coin_references = GNUNET_new_array (ds->num_coin_references,
                                            struct Coin);
    i = 0;
    va_start (ap, purse_ref);
    while (NULL != (ref = va_arg (ap, const char *)))
    {
      struct Coin *c = &ds->coin_references[i++];

      GNUNET_assert (NULL != (val = va_arg (ap, const char *)));
      GNUNET_assert (GNUNET_OK ==
                     TALER_TESTING_parse_coin_reference (
                       ref,
                       &c->command_ref,
                       &c->coin_index));
      GNUNET_assert (GNUNET_OK ==
                     TALER_string_to_amount (val,
                                             &c->deposit_with_fee));
    }
    va_end (ap);
  }
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ds,
      .label = label,
      .run = &deposit_run,
      .cleanup = &deposit_cleanup,
      .traits = &deposit_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_purse_deposit.c */
