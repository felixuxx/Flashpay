/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file testing/testing_api_cmd_age_withdraw.c
 * @brief implements the age-withdraw command
 * @author Özgür Kesim
 */

#include "platform.h"
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_common.h>
#include <microhttpd.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_extensions.h"
#include "taler_testing_lib.h"

/*
 * The output state of coin
 */
struct CoinOutputState
{

  /**
   * The calculated details during "age-withdraw", for the selected coin.
   */
  struct TALER_EXCHANGE_AgeWithdrawCoinPrivateDetails details;

  /**
   * The (wanted) value of the coin, MUST be the same as input.denom_pub.value;
   */
  struct TALER_Amount amount;

  /**
   * Reserve history entry that corresponds to this coin.
   * Will be of type #TALER_EXCHANGE_RTT_AGEWITHDRAWAL.
   */
  struct TALER_EXCHANGE_ReserveHistoryEntry reserve_history;
};

/**
 * State for a "age withdraw" CMD:
 */

struct AgeWithdrawState
{

  /**
   * Interpreter state (during command)
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * The age-withdraw handle
   */
  struct TALER_EXCHANGE_AgeWithdrawHandle *handle;

  /**
   * Exchange base URL.  Only used as offered trait.
   */
  char *exchange_url;

  /**
   * URI of the reserve we are withdrawing from.
   */
  char *reserve_payto_uri;

  /**
   * Private key of the reserve we are withdrawing from.
   */
  struct TALER_ReservePrivateKeyP reserve_priv;

  /**
   * Public key of the reserve we are withdrawing from.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Which reserve should we withdraw from?
   */
  const char *reserve_reference;

  /**
   * Expected HTTP response code to the request.
   */
  unsigned int expected_response_code;

  /**
   * Age mask
   */
  struct TALER_AgeMask mask;

  /**
   * The maximum age we commit to
   */
  uint8_t max_age;

  /**
   * Number of coins to withdraw
   */
  size_t num_coins;

  /**
   * The @e num_coins input that is provided to the
   * `TALER_EXCHANGE_age_withdraw` API.
   * Each contains kappa secrets, from which we will have
   * to disclose kappa-1 in a subsequent age-withdraw-reveal operation.
   */
  struct TALER_EXCHANGE_AgeWithdrawCoinInput *coin_inputs;

  /**
   * The output state of @e num_coins coins, calculated during the
   * "age-withdraw" operation.
   */
  struct CoinOutputState *coin_outputs;

  /**
   * The index returned by the exchange for the "age-withdraw" operation,
   * of the kappa coin candidates that we do not disclose and keep.
   */
  uint8_t noreveal_index;

  /**
   * The blinded hashes of the non-revealed (to keep) @e num_coins coins.
   */
  const struct TALER_BlindedCoinHashP *blinded_coin_hs;

  /**
   * The hash of the commitment, needed for the reveal step.
   */
  struct TALER_AgeWithdrawCommitmentHashP h_commitment;

  /**
   * Set to the KYC requirement payto hash *if* the exchange replied with a
   * request for KYC.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Set to the KYC requirement row *if* the exchange replied with
   * a request for KYC.
   */
  uint64_t requirement_row;

};

/**
 * Callback for the "age-withdraw" ooperation;  It checks that the response
 * code is expected and store the exchange signature in the state.
 *
 * @param cls Closure of type `struct AgeWithdrawState *`
 * @param response Response details
 */
static void
age_withdraw_cb (
  void *cls,
  const struct TALER_EXCHANGE_AgeWithdrawResponse *response)
{
  struct AgeWithdrawState *aws = cls;
  struct TALER_TESTING_Interpreter *is = aws->is;

  aws->handle = NULL;
  if (aws->expected_response_code != response->hr.http_status)
  {
    TALER_TESTING_unexpected_status_with_body (is,
                                               response->hr.http_status,
                                               aws->expected_response_code,
                                               response->hr.reply);
    return;
  }

  switch (response->hr.http_status)
  {
  case MHD_HTTP_OK:
    aws->noreveal_index = response->details.ok.noreveal_index;
    aws->h_commitment = response->details.ok.h_commitment;

    GNUNET_assert (aws->num_coins == response->details.ok.num_coins);
    for (size_t n = 0; n < aws->num_coins; n++)
    {
      aws->coin_outputs[n].details = response->details.ok.coin_details[n];
      TALER_age_commitment_proof_deep_copy (
        &response->details.ok.coin_details[n].age_commitment_proof,
        &aws->coin_outputs[n].details.age_commitment_proof);
    }
    aws->blinded_coin_hs = response->details.ok.blinded_coin_hs;
    break;
  case MHD_HTTP_FORBIDDEN:
  case MHD_HTTP_NOT_FOUND:
  case MHD_HTTP_GONE:
    /* nothing to check */
    break;
  case MHD_HTTP_CONFLICT:
    /* TODO[oec]: Add this to the response-type and handle it here */
    break;
  case MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS:
  default:
    /* Unsupported status code (by test harness) */
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "test command for age-withdraw not support status code %u, body:\n"
                ">>%s<<\n",
                response->hr.http_status,
                json_dumps (response->hr.reply, JSON_INDENT (2)));
    GNUNET_break (0);
    break;
  }

  /* We are done with this command, pick the next one */
  TALER_TESTING_interpreter_next (is);
}


/**
 * Run the command for age-withdraw.
 */
static void
age_withdraw_run (
  void *cls,
  const struct TALER_TESTING_Command *cmd,
  struct TALER_TESTING_Interpreter *is)
{
  struct AgeWithdrawState *aws = cls;
  struct TALER_EXCHANGE_Keys *keys = TALER_TESTING_get_keys (is);
  const struct TALER_ReservePrivateKeyP *rp;
  const struct TALER_TESTING_Command *create_reserve;
  const struct TALER_EXCHANGE_DenomPublicKey *dpk;

  aws->is = is;

  /* Prepare the reserve related data */
  create_reserve
    = TALER_TESTING_interpreter_lookup_command (
        is,
        aws->reserve_reference);

  if (NULL == create_reserve)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_reserve_priv (create_reserve,
                                            &rp))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (NULL == aws->exchange_url)
    aws->exchange_url
      = GNUNET_strdup (TALER_TESTING_get_exchange_url (is));
  aws->reserve_priv = *rp;
  GNUNET_CRYPTO_eddsa_key_get_public (&aws->reserve_priv.eddsa_priv,
                                      &aws->reserve_pub.eddsa_pub);
  aws->reserve_payto_uri
    = TALER_reserve_make_payto (aws->exchange_url,
                                &aws->reserve_pub);

  aws->coin_inputs = GNUNET_new_array (
    aws->num_coins,
    struct TALER_EXCHANGE_AgeWithdrawCoinInput);

  for (unsigned int i = 0; i<aws->num_coins; i++)
  {
    struct TALER_EXCHANGE_AgeWithdrawCoinInput *input = &aws->coin_inputs[i];
    struct CoinOutputState *cos = &aws->coin_outputs[i];

    /* randomly create the secrets for the kappa coin-candidates */
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                &input->secrets,
                                sizeof(input->secrets));
    /* Find denomination */
    dpk = TALER_TESTING_find_pk (keys,
                                 &cos->amount,
                                 true); /* _always_ use denominations with age-striction */
    if (NULL == dpk)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to determine denomination key for amount at %s\n",
                  (NULL != cmd) ? cmd->label : "<retried command>");
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    /* We copy the denomination key, as re-querying /keys
     * would free the old one. */
    input->denom_pub = TALER_EXCHANGE_copy_denomination_key (dpk);
    cos->reserve_history.type = TALER_EXCHANGE_RTT_AGEWITHDRAWAL;
    GNUNET_assert (0 <=
                   TALER_amount_add (&cos->reserve_history.amount,
                                     &cos->amount,
                                     &input->denom_pub->fees.withdraw));
    cos->reserve_history.details.withdraw.fee = input->denom_pub->fees.withdraw;
  }

  /* Execute the age-withdraw protocol */
  aws->handle =
    TALER_EXCHANGE_age_withdraw (
      TALER_TESTING_interpreter_get_context (is),
      keys,
      TALER_TESTING_get_exchange_url (is),
      rp,
      aws->num_coins,
      aws->coin_inputs,
      aws->max_age,
      &age_withdraw_cb,
      aws);

  if (NULL == aws->handle)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "age withdraw" CMD, and possibly cancel a
 * pending operation thereof
 *
 * @param cls Closure of type `struct AgeWithdrawState`
 * @param cmd The command being freed.
 */
static void
age_withdraw_cleanup (
  void *cls,
  const struct TALER_TESTING_Command *cmd)
{
  struct AgeWithdrawState *aws = cls;

  if (NULL != aws->handle)
  {
    TALER_TESTING_command_incomplete (aws->is,
                                      cmd->label);
    TALER_EXCHANGE_age_withdraw_cancel (aws->handle);
    aws->handle = NULL;
  }

  if (NULL != aws->coin_inputs)
  {
    for (size_t n = 0; n < aws->num_coins; n++)
    {
      struct TALER_EXCHANGE_AgeWithdrawCoinInput *in = &aws->coin_inputs[n];
      struct CoinOutputState *out = &aws->coin_outputs[n];

      if (NULL != in && NULL != in->denom_pub)
      {
        TALER_EXCHANGE_destroy_denomination_key (in->denom_pub);
        in->denom_pub = NULL;
      }
      if (NULL != out)
        TALER_age_commitment_proof_free (&out->details.age_commitment_proof);
    }
    GNUNET_free (aws->coin_inputs);
  }
  GNUNET_free (aws->coin_outputs);
  GNUNET_free (aws->exchange_url);
  GNUNET_free (aws->reserve_payto_uri);
  GNUNET_free (aws);
}


/**
 * Offer internal data of a "age withdraw" CMD state to other commands.
 *
 * @param cls Closure of type `struct AgeWithdrawState`
 * @param[out] ret result (could be anything)
 * @param trait name of the trait
 * @param idx index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
age_withdraw_traits (
  void *cls,
  const void **ret,
  const char *trait,
  unsigned int idx)
{
  struct AgeWithdrawState *aws = cls;
  uint8_t k = aws->noreveal_index;
  struct TALER_EXCHANGE_AgeWithdrawCoinInput *in = &aws->coin_inputs[idx];
  struct CoinOutputState *out = &aws->coin_outputs[idx];
  struct TALER_EXCHANGE_AgeWithdrawCoinPrivateDetails *details =
    &aws->coin_outputs[idx].details;
  struct TALER_TESTING_Trait traits[] = {
    /* history entry MUST be first due to response code logic below! */
    TALER_TESTING_make_trait_reserve_history (idx,
                                              &out->reserve_history),
    TALER_TESTING_make_trait_denom_pub (idx,
                                        in->denom_pub),
    TALER_TESTING_make_trait_reserve_priv (&aws->reserve_priv),
    TALER_TESTING_make_trait_reserve_pub (&aws->reserve_pub),
    TALER_TESTING_make_trait_amounts (idx,
                                      &out->amount),
    /* TODO[oec]: add legal requirement to response and handle it here, as well
    TALER_TESTING_make_trait_legi_requirement_row (&aws->requirement_row),
    TALER_TESTING_make_trait_h_payto (&aws->h_payto),
    */
    TALER_TESTING_make_trait_h_blinded_coin (idx,
                                             &aws->blinded_coin_hs[idx]),
    TALER_TESTING_make_trait_payto_uri (aws->reserve_payto_uri),
    TALER_TESTING_make_trait_exchange_url (aws->exchange_url),
    TALER_TESTING_make_trait_coin_priv (idx,
                                        &details->coin_priv),
    TALER_TESTING_make_trait_planchet_secrets (idx,
                                               &in->secrets[k]),
    TALER_TESTING_make_trait_blinding_key (idx,
                                           &details->blinding_key),
    TALER_TESTING_make_trait_exchange_wd_value (idx,
                                                &details->alg_values),
    TALER_TESTING_make_trait_age_commitment_proof (
      idx,
      &details->age_commitment_proof),
    TALER_TESTING_make_trait_h_age_commitment (
      idx,
      &details->h_age_commitment),
    TALER_TESTING_trait_end ()
  };

  if (idx >= aws->num_coins)
    return GNUNET_NO;

  return TALER_TESTING_get_trait ((aws->expected_response_code == MHD_HTTP_OK)
                                  ? &traits[0] /* we have reserve history */
                                  : &traits[1], /* skip reserve history */
                                  ret,
                                  trait,
                                  idx);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_age_withdraw (const char *label,
                                const char *reserve_reference,
                                uint8_t max_age,
                                unsigned int expected_response_code,
                                const char *amount,
                                ...)
{
  struct AgeWithdrawState *aws;
  unsigned int cnt;
  va_list ap;

  aws = GNUNET_new (struct AgeWithdrawState);
  aws->reserve_reference = reserve_reference;
  aws->expected_response_code = expected_response_code;
  aws->mask = TALER_extensions_get_age_restriction_mask ();
  aws->max_age = TALER_get_lowest_age (&aws->mask, max_age);

  cnt = 1;
  va_start (ap, amount);
  while (NULL != (va_arg (ap, const char *)))
    cnt++;
  aws->num_coins = cnt;
  aws->coin_outputs = GNUNET_new_array (cnt,
                                        struct CoinOutputState);
  va_end (ap);
  va_start (ap, amount);

  for (unsigned int i = 0; i<aws->num_coins; i++)
  {
    struct CoinOutputState *out = &aws->coin_outputs[i];
    if (GNUNET_OK !=
        TALER_string_to_amount (amount,
                                &out->amount))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to parse amount `%s' at %s\n",
                  amount,
                  label);
      GNUNET_assert (0);
    }
    /* move on to next vararg! */
    amount = va_arg (ap, const char *);
  }

  GNUNET_assert (NULL == amount);
  va_end (ap);

  {
    struct TALER_TESTING_Command cmd = {
      .cls = aws,
      .label = label,
      .run = &age_withdraw_run,
      .cleanup = &age_withdraw_cleanup,
      .traits = &age_withdraw_traits,
    };

    return cmd;
  }
}


/**
 * The state for the age-withdraw-reveal operation
 */
struct AgeWithdrawRevealState
{
  /**
   * The reference to the CMD resembling the previous call to age-withdraw
   */
  const char *age_withdraw_reference;

  /**
   * The state to the previous age-withdraw command
   */
  const struct AgeWithdrawState *aws;

  /**
   * The expected response code from the call to the
   * age-withdraw-reveal operation
   */
  unsigned int expected_response_code;

  /**
   * Interpreter state (during command)
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * The handle to the reveal-operation
   */
  struct TALER_EXCHANGE_AgeWithdrawRevealHandle *handle;


  /**
   * Number of coins, extracted form the age withdraw command
   */
  size_t num_coins;

  /**
   * The signatures of the @e num_coins coins returned
   */
  struct TALER_DenominationSignature *denom_sigs;

};

/*
 * Callback for the reveal response
 *
 * @param cls Closure of type `struct AgeWithdrawRevealState`
 * @param awr The response
 */
static void
age_withdraw_reveal_cb (
  void *cls,
  const struct TALER_EXCHANGE_AgeWithdrawRevealResponse *response)
{
  struct AgeWithdrawRevealState *awrs = cls;
  struct TALER_TESTING_Interpreter *is = awrs->is;

  awrs->handle = NULL;
  if (awrs->expected_response_code != response->hr.http_status)
  {
    TALER_TESTING_unexpected_status_with_body (is,
                                               response->hr.http_status,
                                               awrs->expected_response_code,
                                               response->hr.reply);
    return;
  }
  switch (response->hr.http_status)
  {
  case MHD_HTTP_OK:
    {
      const struct AgeWithdrawState *aws = awrs->aws;
      GNUNET_assert (awrs->num_coins == response->details.ok.num_sigs);
      awrs->denom_sigs = GNUNET_new_array (awrs->num_coins,
                                           struct TALER_DenominationSignature);
      for (size_t n = 0; n < awrs->num_coins; n++)
      {
        GNUNET_assert (GNUNET_OK ==
                       TALER_denom_sig_unblind (
                         &awrs->denom_sigs[n],
                         &response->details.ok.blinded_denom_sigs[n],
                         &aws->coin_outputs[n].details.blinding_key,
                         &aws->coin_outputs[n].details.h_coin_pub,
                         &aws->coin_outputs[n].details.alg_values,
                         &aws->coin_inputs[n].denom_pub->key));
        TALER_denom_sig_free (&awrs->denom_sigs[n]);
      }

      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "age-withdraw reveal success!\n");
      GNUNET_free (awrs->denom_sigs);
    }
    break;
  case MHD_HTTP_NOT_FOUND:
  case MHD_HTTP_FORBIDDEN:
    /* nothing to check */
    break;
  /* TODO[oec]: handle more cases !? */
  default:
    /* Unsupported status code (by test harness) */
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Age withdraw reveal test command does not support status code %u\n",
                response->hr.http_status);
    GNUNET_break (0);
    break;
  }

  /* We are done with this command, pick the next one */
  TALER_TESTING_interpreter_next (is);
}


/**
 * Run the command for age-withdraw-reveal
 */
static void
age_withdraw_reveal_run (
  void *cls,
  const struct TALER_TESTING_Command *cmd,
  struct TALER_TESTING_Interpreter *is)
{
  struct AgeWithdrawRevealState *awrs = cls;
  const struct TALER_TESTING_Command *age_withdraw_cmd;
  const struct AgeWithdrawState *aws;

  (void) cmd;
  awrs->is = is;

  /*
   * Get the command and state for the previous call to "age witdraw"
   */
  age_withdraw_cmd  =
    TALER_TESTING_interpreter_lookup_command (is,
                                              awrs->age_withdraw_reference);
  if (NULL == age_withdraw_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_assert (age_withdraw_cmd->run == age_withdraw_run);
  aws = age_withdraw_cmd->cls;
  awrs->aws = aws;
  awrs->num_coins = aws->num_coins;

  awrs->handle =
    TALER_EXCHANGE_age_withdraw_reveal (
      TALER_TESTING_interpreter_get_context (is),
      TALER_TESTING_get_exchange_url (is),
      aws->num_coins,
      aws->coin_inputs,
      aws->noreveal_index,
      &aws->h_commitment,
      &aws->reserve_pub,
      age_withdraw_reveal_cb,
      awrs);
}


/**
 * Free the state of a "age-withdraw-reveal" CMD, and possibly
 * cancel a pending operation thereof
 *
 * @param cls Closure of type `struct AgeWithdrawRevealState`
 * @param cmd The command being freed.
 */
static void
age_withdraw_reveal_cleanup (
  void *cls,
  const struct TALER_TESTING_Command *cmd)
{
  struct AgeWithdrawRevealState *awrs = cls;

  if (NULL != awrs->handle)
  {
    TALER_TESTING_command_incomplete (awrs->is,
                                      cmd->label);
    TALER_EXCHANGE_age_withdraw_reveal_cancel (awrs->handle);
    awrs->handle = NULL;
  }
  GNUNET_free (awrs->denom_sigs);
  awrs->denom_sigs = NULL;
  GNUNET_free (awrs);
}


/**
 * Offer internal data of a "age withdraw reveal" CMD state to other commands.
 *
 * @param cls Closure of they `struct AgeWithdrawRevealState`
 * @param[out] ret result (could be anything)
 * @param trait name of the trait
 * @param idx index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
age_withdraw_reveal_traits (
  void *cls,
  const void **ret,
  const char *trait,
  unsigned int idx)
{
  struct AgeWithdrawRevealState *awrs = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_denom_sig (idx,
                                        &awrs->denom_sigs[idx]),
    /* FIXME: shall we provide the traits from the previous
     * call to "age withdraw" as well? */
    TALER_TESTING_trait_end ()
  };

  if (idx >= awrs->num_coins)
    return GNUNET_NO;

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  idx);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_age_withdraw_reveal (
  const char *label,
  const char *age_withdraw_reference,
  unsigned int expected_response_code)
{
  struct AgeWithdrawRevealState *awrs =
    GNUNET_new (struct AgeWithdrawRevealState);

  awrs->age_withdraw_reference = age_withdraw_reference;
  awrs->expected_response_code = expected_response_code;

  struct TALER_TESTING_Command cmd = {
    .cls = awrs,
    .label = label,
    .run = age_withdraw_reveal_run,
    .cleanup = age_withdraw_reveal_cleanup,
    .traits = age_withdraw_reveal_traits,
  };

  return cmd;
}


/* end of testing_api_cmd_age_withdraw.c */
