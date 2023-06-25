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
 * @file testing/testing_api_cmd_purse_create_deposit.c
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
 * State for a "purse create deposit" CMD.
 */
struct PurseCreateDepositState
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
   * JSON string describing what a proposal is about.
   */
  json_t *contract_terms;

  /**
   * Purse expiration time.
   */
  struct GNUNET_TIME_Timestamp purse_expiration;

  /**
   * Relative purse expiration time.
   */
  struct GNUNET_TIME_Relative rel_expiration;

  /**
   * Set (by the interpreter) to a fresh private key.  This
   * key will be used to create the purse.
   */
  struct TALER_PurseContractPrivateKeyP purse_priv;

  /**
   * Set (by the interpreter) to a fresh private key.  This
   * key will be used to merge the purse.
   */
  struct TALER_PurseMergePrivateKeyP merge_priv;

  /**
   * Set (by the interpreter) to a fresh private key.  This
   * key will be used to decrypt the contract.
   */
  struct TALER_ContractDiffiePrivateP contract_priv;

  /**
   * Signing key used by the exchange to sign the
   * deposit confirmation.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

  /**
   * Signature from the exchange on the
   * deposit confirmation.
   */
  struct TALER_ExchangeSignatureP exchange_sig;

  /**
   * Set (by the interpreter) to a public key corresponding
   * to @e purse_priv.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * PurseCreateDeposit handle while operation is running.
   */
  struct TALER_EXCHANGE_PurseCreateDepositHandle *dh;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Length of the @e coin_references array.
   */
  unsigned int num_coin_references;

  /**
   * Should we upload the contract?
   */
  bool upload_contract;

};


/**
 * Callback to analyze the /purses/$PID/create response, just used to check if
 * the response code is acceptable.
 *
 * @param cls closure.
 * @param dr deposit response details
 */
static void
deposit_cb (void *cls,
            const struct TALER_EXCHANGE_PurseCreateDepositResponse *dr)
{
  struct PurseCreateDepositState *ds = cls;

  ds->dh = NULL;
  if (ds->expected_response_code != dr->hr.http_status)
  {
    TALER_TESTING_unexpected_status (ds->is,
                                     dr->hr.http_status);
    return;
  }
  if (MHD_HTTP_OK == dr->hr.http_status)
  {
    ds->exchange_pub = dr->details.ok.exchange_pub;
    ds->exchange_sig = dr->details.ok.exchange_sig;
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
  struct PurseCreateDepositState *ds = cls;
  struct TALER_EXCHANGE_PurseDeposit deposits[ds->num_coin_references];

  (void) cmd;
  ds->is = is;
  for (unsigned int i = 0; i<ds->num_coin_references; i++)
  {
    const struct Coin *cr = &ds->coin_references[i];
    struct TALER_EXCHANGE_PurseDeposit *pd = &deposits[i];
    const struct TALER_TESTING_Command *coin_cmd;
    const struct TALER_CoinSpendPrivateKeyP *coin_priv;
    const struct TALER_AgeCommitmentProof *age_commitment_proof = NULL;
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
    pd->age_commitment_proof = age_commitment_proof;
    pd->denom_sig = *denom_pub_sig;
    pd->coin_priv = *coin_priv;
    pd->amount = cr->deposit_with_fee;
    pd->h_denom_pub = denom_pub->h_key;
  }

  GNUNET_CRYPTO_eddsa_key_create (&ds->purse_priv.eddsa_priv);
  GNUNET_CRYPTO_eddsa_key_create (&ds->merge_priv.eddsa_priv);
  GNUNET_CRYPTO_ecdhe_key_create (&ds->contract_priv.ecdhe_priv);
  GNUNET_CRYPTO_eddsa_key_get_public (&ds->purse_priv.eddsa_priv,
                                      &ds->purse_pub.eddsa_pub);

  ds->purse_expiration =
    GNUNET_TIME_absolute_to_timestamp (
      GNUNET_TIME_relative_to_absolute (ds->rel_expiration));
  GNUNET_assert (0 ==
                 json_object_set_new (
                   ds->contract_terms,
                   "pay_deadline",
                   GNUNET_JSON_from_timestamp (ds->purse_expiration)));
  ds->dh = TALER_EXCHANGE_purse_create_with_deposit (
    TALER_TESTING_interpreter_get_context (is),
    TALER_TESTING_get_exchange_url (is),
    TALER_TESTING_get_keys (is),
    &ds->purse_priv,
    &ds->merge_priv,
    &ds->contract_priv,
    ds->contract_terms,
    ds->num_coin_references,
    deposits,
    ds->upload_contract,
    &deposit_cb,
    ds);
  if (NULL == ds->dh)
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not create purse with deposit\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "deposit" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct PurseCreateDepositState`.
 * @param cmd the command which is being cleaned up.
 */
static void
deposit_cleanup (void *cls,
                 const struct TALER_TESTING_Command *cmd)
{
  struct PurseCreateDepositState *ds = cls;

  if (NULL != ds->dh)
  {
    TALER_TESTING_command_incomplete (ds->is,
                                      cmd->label);
    TALER_EXCHANGE_purse_create_with_deposit_cancel (ds->dh);
    ds->dh = NULL;
  }
  for (unsigned int i = 0; i<ds->num_coin_references; i++)
    GNUNET_free (ds->coin_references[i].command_ref);
  json_decref (ds->contract_terms);
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
  struct PurseCreateDepositState *ds = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_merge_priv (&ds->merge_priv),
    TALER_TESTING_make_trait_contract_priv (&ds->contract_priv),
    TALER_TESTING_make_trait_purse_priv (&ds->purse_priv),
    TALER_TESTING_make_trait_purse_pub (&ds->purse_pub),
    TALER_TESTING_make_trait_contract_terms (ds->contract_terms),
    TALER_TESTING_make_trait_deposit_amount (0,
                                             &ds->target_amount),
    TALER_TESTING_make_trait_timestamp (index,
                                        &ds->purse_expiration),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_purse_create_with_deposit (
  const char *label,
  unsigned int expected_http_status,
  const char *contract_terms,
  bool upload_contract,
  struct GNUNET_TIME_Relative purse_expiration,
  ...)
{
  struct PurseCreateDepositState *ds;

  ds = GNUNET_new (struct PurseCreateDepositState);
  ds->rel_expiration = purse_expiration;
  ds->upload_contract = upload_contract;
  ds->expected_response_code = expected_http_status;
  ds->contract_terms = json_loads (contract_terms,
                                   JSON_REJECT_DUPLICATES,
                                   NULL);
  if (NULL == ds->contract_terms)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to parse contract terms `%s' for CMD `%s'\n",
                contract_terms,
                label);
    GNUNET_assert (0);
  }
  {
    va_list ap;
    unsigned int i;
    const char *ref;
    const char *val;

    va_start (ap, purse_expiration);
    while (NULL != (va_arg (ap, const char *)))
      ds->num_coin_references++;
    va_end (ap);
    GNUNET_assert (0 == (ds->num_coin_references % 2));
    ds->num_coin_references /= 2;
    ds->coin_references = GNUNET_new_array (ds->num_coin_references,
                                            struct Coin);
    i = 0;
    va_start (ap, purse_expiration);
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


/* end of testing_api_cmd_purse_create_deposit.c */
