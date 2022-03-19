/*
  This file is part of TALER
  Copyright (C) 2018-2021 Taler Systems SA

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
 * @file testing/testing_api_cmd_deposit.c
 * @brief command for testing /deposit.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"


/**
 * How often do we retry before giving up?
 */
#define NUM_RETRIES 5

/**
 * How long do we wait AT MOST when retrying?
 */
#define MAX_BACKOFF GNUNET_TIME_relative_multiply ( \
    GNUNET_TIME_UNIT_MILLISECONDS, 100)


/**
 * State for a "deposit" CMD.
 */
struct DepositState
{

  /**
   * Amount to deposit.
   */
  struct TALER_Amount amount;

  /**
   * Deposit fee.
   */
  struct TALER_Amount deposit_fee;

  /**
   * Reference to any command that is able to provide a coin.
   */
  const char *coin_reference;

  /**
   * If @e coin_reference refers to an operation that generated
   * an array of coins, this value determines which coin to pick.
   */
  unsigned int coin_index;

  /**
   * Wire details of who is depositing -- this would be merchant
   * wire details in a normal scenario.
   */
  json_t *wire_details;

  /**
   * JSON string describing what a proposal is about.
   */
  json_t *contract_terms;

  /**
   * Refund deadline. Zero for no refunds.
   */
  struct GNUNET_TIME_Timestamp refund_deadline;

  /**
   * Wire deadline.
   */
  struct GNUNET_TIME_Timestamp wire_deadline;

  /**
   * Set (by the interpreter) to a fresh private key.  This
   * key will be used to sign the deposit request.
   */
  struct TALER_MerchantPrivateKeyP merchant_priv;

  /**
   * Deposit handle while operation is running.
   */
  struct TALER_EXCHANGE_DepositHandle *dh;

  /**
   * Timestamp of the /deposit operation in the wallet (contract signing time).
   */
  struct GNUNET_TIME_Timestamp wallet_timestamp;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Task scheduled to try later.
   */
  struct GNUNET_SCHEDULER_Task *retry_task;

  /**
   * How long do we wait until we retry?
   */
  struct GNUNET_TIME_Relative backoff;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * How often should we retry on (transient) failures?
   */
  unsigned int do_retry;

  /**
   * Set to #GNUNET_YES if the /deposit succeeded
   * and we now can provide the resulting traits.
   */
  int deposit_succeeded;

  /**
   * When did the exchange receive the deposit?
   */
  struct GNUNET_TIME_Timestamp exchange_timestamp;

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
   * Reference to previous deposit operation.
   * Only present if we're supposed to replay the previous deposit.
   */
  const char *deposit_reference;

  /**
   * Did we set the parameters for this deposit command?
   *
   * When we're referencing another deposit operation,
   * this will only be set after the command has been started.
   */
  int command_initialized;

  /**
   * Reference to fetch the merchant private key from.
   * If NULL, we generate our own, fresh merchant key.
   */
  const char *merchant_priv_reference;
};


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
             struct TALER_TESTING_Interpreter *is);


/**
 * Task scheduled to re-try #deposit_run.
 *
 * @param cls a `struct DepositState`
 */
static void
do_retry (void *cls)
{
  struct DepositState *ds = cls;

  ds->retry_task = NULL;
  ds->is->commands[ds->is->ip].last_req_time
    = GNUNET_TIME_absolute_get ();
  deposit_run (ds,
               NULL,
               ds->is);
}


/**
 * Callback to analyze the /deposit response, just used to
 * check if the response code is acceptable.
 *
 * @param cls closure.
 * @param dr deposit response details
 */
static void
deposit_cb (void *cls,
            const struct TALER_EXCHANGE_DepositResult *dr)
{
  struct DepositState *ds = cls;

  ds->dh = NULL;
  if (ds->expected_response_code != dr->hr.http_status)
  {
    if (0 != ds->do_retry)
    {
      ds->do_retry--;
      if ( (0 == dr->hr.http_status) ||
           (TALER_EC_GENERIC_DB_SOFT_FAILURE == dr->hr.ec) ||
           (MHD_HTTP_INTERNAL_SERVER_ERROR == dr->hr.http_status) )
      {
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Retrying deposit failed with %u/%d\n",
                    dr->hr.http_status,
                    (int) dr->hr.ec);
        /* on DB conflicts, do not use backoff */
        if (TALER_EC_GENERIC_DB_SOFT_FAILURE == dr->hr.ec)
          ds->backoff = GNUNET_TIME_UNIT_ZERO;
        else
          ds->backoff = GNUNET_TIME_randomized_backoff (ds->backoff,
                                                        MAX_BACKOFF);
        ds->is->commands[ds->is->ip].num_tries++;
        GNUNET_assert (NULL == ds->retry_task);
        ds->retry_task
          = GNUNET_SCHEDULER_add_delayed (ds->backoff,
                                          &do_retry,
                                          ds);
        return;
      }
    }
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
    ds->deposit_succeeded = GNUNET_YES;
    ds->exchange_timestamp = dr->details.success.deposit_timestamp;
    ds->exchange_pub = *dr->details.success.exchange_pub;
    ds->exchange_sig = *dr->details.success.exchange_sig;
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
  struct DepositState *ds = cls;
  const struct TALER_TESTING_Command *coin_cmd;
  const struct TALER_CoinSpendPrivateKeyP *coin_priv;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  const struct TALER_AgeCommitmentProof *age_commitment_proof = NULL;
  struct TALER_AgeCommitmentHash h_age_commitment = {0};
  const struct TALER_EXCHANGE_DenomPublicKey *denom_pub;
  const struct TALER_DenominationSignature *denom_pub_sig;
  struct TALER_CoinSpendSignatureP coin_sig;
  struct TALER_MerchantPublicKeyP merchant_pub;
  struct TALER_PrivateContractHashP h_contract_terms;
  enum TALER_ErrorCode ec;
  struct TALER_WireSaltP wire_salt;
  const char *payto_uri;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("payto_uri",
                             &payto_uri),
    GNUNET_JSON_spec_fixed_auto ("salt",
                                 &wire_salt),
    GNUNET_JSON_spec_end ()
  };

  (void) cmd;
  ds->is = is;
  if (NULL != ds->deposit_reference)
  {
    /* We're copying another deposit operation, initialize here. */
    const struct TALER_TESTING_Command *cmd;
    struct DepositState *ods;

    cmd = TALER_TESTING_interpreter_lookup_command (is,
                                                    ds->deposit_reference);
    if (NULL == cmd)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    ods = cmd->cls;
    ds->coin_reference = ods->coin_reference;
    ds->coin_index = ods->coin_index;
    ds->wire_details = json_incref (ods->wire_details);
    GNUNET_assert (NULL != ds->wire_details);
    ds->contract_terms = json_incref (ods->contract_terms);
    ds->wallet_timestamp = ods->wallet_timestamp;
    ds->refund_deadline = ods->refund_deadline;
    ds->amount = ods->amount;
    ds->merchant_priv = ods->merchant_priv;
    ds->command_initialized = GNUNET_YES;
  }
  else if (NULL != ds->merchant_priv_reference)
  {
    /* We're copying the merchant key from another deposit operation */
    const struct TALER_MerchantPrivateKeyP *merchant_priv;
    const struct TALER_TESTING_Command *cmd;

    cmd = TALER_TESTING_interpreter_lookup_command (is,
                                                    ds->merchant_priv_reference);
    if (NULL == cmd)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if ( (GNUNET_OK !=
          TALER_TESTING_get_trait_merchant_priv (cmd,
                                                 &merchant_priv)) )
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    ds->merchant_priv = *merchant_priv;
  }
  GNUNET_assert (NULL != ds->wire_details);
  if (GNUNET_OK !=
      GNUNET_JSON_parse (ds->wire_details,
                         spec,
                         NULL, NULL))
  {
    json_dumpf (ds->wire_details,
                stderr,
                JSON_INDENT (2));
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_assert (ds->coin_reference);
  coin_cmd = TALER_TESTING_interpreter_lookup_command (is,
                                                       ds->coin_reference);
  if (NULL == coin_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  if ( (GNUNET_OK !=
        TALER_TESTING_get_trait_coin_priv (coin_cmd,
                                           ds->coin_index,
                                           &coin_priv)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_age_commitment_proof (coin_cmd,
                                                      ds->coin_index,
                                                      &age_commitment_proof)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_denom_pub (coin_cmd,
                                           ds->coin_index,
                                           &denom_pub)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_denom_sig (coin_cmd,
                                           ds->coin_index,
                                           &denom_pub_sig)) ||
       (GNUNET_OK !=
        TALER_JSON_contract_hash (ds->contract_terms,
                                  &h_contract_terms)) )
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
  ds->deposit_fee = denom_pub->fees.deposit;
  GNUNET_CRYPTO_eddsa_key_get_public (&coin_priv->eddsa_priv,
                                      &coin_pub.eddsa_pub);

  if (! GNUNET_TIME_absolute_is_zero (ds->refund_deadline.abs_time))
  {
    struct GNUNET_TIME_Relative refund_deadline;

    refund_deadline
      = GNUNET_TIME_absolute_get_remaining (ds->refund_deadline.abs_time);
    ds->wire_deadline
      =
        GNUNET_TIME_relative_to_timestamp (
          GNUNET_TIME_relative_multiply (refund_deadline,
                                         2));
  }
  else
  {
    ds->refund_deadline = ds->wallet_timestamp;
    ds->wire_deadline = GNUNET_TIME_timestamp_get ();
  }
  GNUNET_CRYPTO_eddsa_key_get_public (&ds->merchant_priv.eddsa_priv,
                                      &merchant_pub.eddsa_pub);
  {
    struct TALER_MerchantWireHashP h_wire;

    GNUNET_assert (GNUNET_OK ==
                   TALER_JSON_merchant_wire_signature_hash (ds->wire_details,
                                                            &h_wire));
    TALER_wallet_deposit_sign (&ds->amount,
                               &denom_pub->fees.deposit,
                               &h_wire,
                               &h_contract_terms,
                               &h_age_commitment,
                               NULL, /* FIXME: add hash of extensions */
                               &denom_pub->h_key,
                               ds->wallet_timestamp,
                               &merchant_pub,
                               ds->refund_deadline,
                               coin_priv,
                               &coin_sig);
  }
  GNUNET_assert (NULL == ds->dh);
  ds->dh = TALER_EXCHANGE_deposit (is->exchange,
                                   &ds->amount,
                                   ds->wire_deadline,
                                   payto_uri,
                                   &wire_salt,
                                   &h_contract_terms,
                                   &h_age_commitment,
                                   NULL, /* FIXME: add hash of extensions */
                                   &coin_pub,
                                   denom_pub_sig,
                                   &denom_pub->key,
                                   ds->wallet_timestamp,
                                   &merchant_pub,
                                   ds->refund_deadline,
                                   &coin_sig,
                                   &deposit_cb,
                                   ds,
                                   &ec);
  if (NULL == ds->dh)
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not create deposit with EC %d\n",
                (int) ec);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "deposit" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct DepositState`.
 * @param cmd the command which is being cleaned up.
 */
static void
deposit_cleanup (void *cls,
                 const struct TALER_TESTING_Command *cmd)
{
  struct DepositState *ds = cls;

  if (NULL != ds->dh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ds->is->ip,
                cmd->label);
    TALER_EXCHANGE_deposit_cancel (ds->dh);
    ds->dh = NULL;
  }
  if (NULL != ds->retry_task)
  {
    GNUNET_SCHEDULER_cancel (ds->retry_task);
    ds->retry_task = NULL;
  }
  json_decref (ds->wire_details);
  json_decref (ds->contract_terms);
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
  struct DepositState *ds = cls;
  const struct TALER_TESTING_Command *coin_cmd;
  /* Will point to coin cmd internals. */
  const struct TALER_CoinSpendPrivateKeyP *coin_spent_priv;
  const struct TALER_AgeCommitmentProof *age_commitment_proof;

  if (GNUNET_YES != ds->command_initialized)
  {
    /* No access to traits yet. */
    GNUNET_break (0);
    return GNUNET_NO;
  }

  coin_cmd
    = TALER_TESTING_interpreter_lookup_command (ds->is,
                                                ds->coin_reference);
  if (NULL == coin_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (ds->is);
    return GNUNET_NO;
  }
  if ( (GNUNET_OK !=
        TALER_TESTING_get_trait_coin_priv (coin_cmd,
                                           ds->coin_index,
                                           &coin_spent_priv)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_age_commitment_proof (coin_cmd,
                                                      ds->coin_index,
                                                      &age_commitment_proof)) )
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (ds->is);
    return GNUNET_NO;
  }
  {
    struct TALER_TESTING_Trait traits[] = {
      /* First two traits are only available if
         ds->traits is #GNUNET_YES */
      TALER_TESTING_make_trait_exchange_pub (index, &ds->exchange_pub),
      TALER_TESTING_make_trait_exchange_sig (index, &ds->exchange_sig),
      /* These traits are always available */
      TALER_TESTING_make_trait_coin_priv (index,
                                          coin_spent_priv),
      TALER_TESTING_make_trait_age_commitment_proof (index,
                                                     age_commitment_proof),
      TALER_TESTING_make_trait_wire_details (ds->wire_details),
      TALER_TESTING_make_trait_contract_terms (ds->contract_terms),
      TALER_TESTING_make_trait_merchant_priv (&ds->merchant_priv),
      TALER_TESTING_make_trait_deposit_amount (&ds->amount),
      TALER_TESTING_make_trait_deposit_fee_amount (&ds->deposit_fee),
      TALER_TESTING_make_trait_timestamp (index,
                                          &ds->exchange_timestamp),
      TALER_TESTING_make_trait_wire_deadline (index,
                                              &ds->wire_deadline),
      TALER_TESTING_make_trait_refund_deadline (index,
                                                &ds->refund_deadline),
      TALER_TESTING_trait_end ()
    };

    return TALER_TESTING_get_trait ((ds->deposit_succeeded)
                                    ? traits
                                    : &traits[2],
                                    ret,
                                    trait,
                                    index);
  }
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit (const char *label,
                           const char *coin_reference,
                           unsigned int coin_index,
                           const char *target_account_payto,
                           const char *contract_terms,
                           struct GNUNET_TIME_Relative refund_deadline,
                           const char *amount,
                           unsigned int expected_response_code)
{
  struct DepositState *ds;

  ds = GNUNET_new (struct DepositState);
  ds->coin_reference = coin_reference;
  ds->coin_index = coin_index;
  ds->wire_details = TALER_TESTING_make_wire_details (target_account_payto);
  GNUNET_assert (NULL != ds->wire_details);
  ds->contract_terms = json_loads (contract_terms,
                                   JSON_REJECT_DUPLICATES,
                                   NULL);
  GNUNET_CRYPTO_eddsa_key_create (&ds->merchant_priv.eddsa_priv);
  if (NULL == ds->contract_terms)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to parse contract terms `%s' for CMD `%s'\n",
                contract_terms,
                label);
    GNUNET_assert (0);
  }
  ds->wallet_timestamp = GNUNET_TIME_timestamp_get ();
  GNUNET_assert (0 ==
                 json_object_set_new (ds->contract_terms,
                                      "timestamp",
                                      GNUNET_JSON_from_timestamp (
                                        ds->wallet_timestamp)));
  if (! GNUNET_TIME_relative_is_zero (refund_deadline))
  {
    ds->refund_deadline = GNUNET_TIME_relative_to_timestamp (refund_deadline);
    GNUNET_assert (0 ==
                   json_object_set_new (ds->contract_terms,
                                        "refund_deadline",
                                        GNUNET_JSON_from_timestamp (
                                          ds->refund_deadline)));
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (amount,
                                         &ds->amount));
  ds->expected_response_code = expected_response_code;
  ds->command_initialized = GNUNET_YES;
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


struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit_with_ref (const char *label,
                                    const char *coin_reference,
                                    unsigned int coin_index,
                                    const char *target_account_payto,
                                    const char *contract_terms,
                                    struct GNUNET_TIME_Relative refund_deadline,
                                    const char *amount,
                                    unsigned int expected_response_code,
                                    const char *merchant_priv_reference)
{
  struct DepositState *ds;

  ds = GNUNET_new (struct DepositState);
  ds->merchant_priv_reference = merchant_priv_reference;
  ds->coin_reference = coin_reference;
  ds->coin_index = coin_index;
  ds->wire_details = TALER_TESTING_make_wire_details (target_account_payto);
  GNUNET_assert (NULL != ds->wire_details);
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
  ds->wallet_timestamp = GNUNET_TIME_timestamp_get ();
  json_object_set_new (ds->contract_terms,
                       "timestamp",
                       GNUNET_JSON_from_timestamp (ds->wallet_timestamp));
  if (0 != refund_deadline.rel_value_us)
  {
    ds->refund_deadline = GNUNET_TIME_relative_to_timestamp (refund_deadline);
    json_object_set_new (ds->contract_terms,
                         "refund_deadline",
                         GNUNET_JSON_from_timestamp (ds->refund_deadline));
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (amount,
                                         &ds->amount));
  ds->expected_response_code = expected_response_code;
  ds->command_initialized = GNUNET_YES;
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


struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit_replay (const char *label,
                                  const char *deposit_reference,
                                  unsigned int expected_response_code)
{
  struct DepositState *ds;

  ds = GNUNET_new (struct DepositState);
  ds->deposit_reference = deposit_reference;
  ds->expected_response_code = expected_response_code;
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


struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit_with_retry (struct TALER_TESTING_Command cmd)
{
  struct DepositState *ds;

  GNUNET_assert (&deposit_run == cmd.run);
  ds = cmd.cls;
  ds->do_retry = NUM_RETRIES;
  return cmd;
}


/* end of testing_api_cmd_deposit.c */
