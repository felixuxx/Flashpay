/*
  This file is part of TALER
  Copyright (C) 2018-2024 Taler Systems SA

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
   * Our coin signature.
   */
  struct TALER_CoinSpendSignatureP coin_sig;

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
  union TALER_AccountPrivateKeyP account_priv;

  /**
   * Set (by the interpreter) to the public key
   * corresponding to @e account_priv.
   */
  union TALER_AccountPublicKeyP account_pub;

  /**
   * Deposit handle while operation is running.
   */
  struct TALER_EXCHANGE_BatchDepositHandle *dh;

  /**
   * Denomination public key of the deposited coin.
   */
  const struct TALER_EXCHANGE_DenomPublicKey *denom_pub;

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
   * Set to true if the /deposit succeeded
   * and we now can provide the resulting traits.
   */
  bool deposit_succeeded;

  /**
   * Expected entry in the coin history created by this
   * operation.
   */
  struct TALER_EXCHANGE_CoinHistoryEntry che;

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
  bool command_initialized;

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
  TALER_TESTING_touch_cmd (ds->is);
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
            const struct TALER_EXCHANGE_BatchDepositResult *dr)
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
        TALER_TESTING_inc_tries (ds->is);
        GNUNET_assert (NULL == ds->retry_task);
        ds->retry_task
          = GNUNET_SCHEDULER_add_delayed (ds->backoff,
                                          &do_retry,
                                          ds);
        return;
      }
    }
    TALER_TESTING_unexpected_status_with_body (
      ds->is,
      dr->hr.http_status,
      ds->expected_response_code,
      dr->hr.reply);

    return;
  }
  if (MHD_HTTP_OK == dr->hr.http_status)
  {
    ds->deposit_succeeded = true;
    ds->exchange_timestamp = dr->details.ok.deposit_timestamp;
    ds->exchange_pub = *dr->details.ok.exchange_pub;
    ds->exchange_sig = *dr->details.ok.exchange_sig;
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
  const struct TALER_TESTING_Command *acc_var;
  const struct TALER_CoinSpendPrivateKeyP *coin_priv;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  const struct TALER_AgeCommitmentHash *phac;
  const struct TALER_DenominationSignature *denom_pub_sig;
  struct TALER_PrivateContractHashP h_contract_terms;
  enum TALER_ErrorCode ec;
  struct TALER_WireSaltP wire_salt;
  struct TALER_FullPayto payto_uri;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_full_payto_uri ("payto_uri",
                                    &payto_uri),
    GNUNET_JSON_spec_fixed_auto ("salt",
                                 &wire_salt),
    GNUNET_JSON_spec_end ()
  };
  const char *exchange_url
    = TALER_TESTING_get_exchange_url (is);

  (void) cmd;
  if (NULL == exchange_url)
  {
    GNUNET_break (0);
    return;
  }
  ds->is = is;
  if (! GNUNET_TIME_absolute_is_zero (ds->refund_deadline.abs_time))
  {
    struct GNUNET_TIME_Relative refund_deadline;

    refund_deadline
      = GNUNET_TIME_absolute_get_remaining (ds->refund_deadline.abs_time);
    ds->wire_deadline
      = GNUNET_TIME_relative_to_timestamp (
          GNUNET_TIME_relative_multiply (refund_deadline,
                                         2));
  }
  else
  {
    ds->refund_deadline = ds->wallet_timestamp;
    ds->wire_deadline = GNUNET_TIME_timestamp_get ();
  }
  if (NULL != ds->deposit_reference)
  {
    /* We're copying another deposit operation, initialize here. */
    const struct TALER_TESTING_Command *drcmd;
    struct DepositState *ods;

    drcmd = TALER_TESTING_interpreter_lookup_command (is,
                                                      ds->deposit_reference);
    if (NULL == drcmd)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    ods = drcmd->cls;
    ds->coin_reference = ods->coin_reference;
    ds->coin_index = ods->coin_index;
    ds->wire_details = json_incref (ods->wire_details);
    GNUNET_assert (NULL != ds->wire_details);
    ds->contract_terms = json_incref (ods->contract_terms);
    ds->wallet_timestamp = ods->wallet_timestamp;
    ds->refund_deadline = ods->refund_deadline;
    ds->wire_deadline = ods->wire_deadline;
    ds->amount = ods->amount;
    ds->account_priv = ods->account_priv;
    ds->account_pub = ods->account_pub;
    ds->command_initialized = true;
  }
  else if (NULL != ds->merchant_priv_reference)
  {
    /* We're copying the merchant key from another deposit operation */
    const struct TALER_MerchantPrivateKeyP *merchant_priv;
    const struct TALER_TESTING_Command *mpcmd;

    mpcmd = TALER_TESTING_interpreter_lookup_command (
      is,
      ds->merchant_priv_reference);
    if (NULL == mpcmd)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if ( (GNUNET_OK !=
          TALER_TESTING_get_trait_merchant_priv (mpcmd,
                                                 &merchant_priv)) )
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    ds->account_priv.merchant_priv = *merchant_priv;
    GNUNET_CRYPTO_eddsa_key_get_public (
      &ds->account_priv.merchant_priv.eddsa_priv,
      &ds->account_pub.merchant_pub.eddsa_pub);
  }
  else if (NULL != (acc_var
                      = TALER_TESTING_interpreter_get_command (
                          is,
                          "account-priv")))
  {
    const union TALER_AccountPrivateKeyP *account_priv;

    if ( (GNUNET_OK !=
          TALER_TESTING_get_trait_account_priv (acc_var,
                                                &account_priv)) )
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    ds->account_priv = *account_priv;
    GNUNET_CRYPTO_eddsa_key_get_public (
      &ds->account_priv.merchant_priv.eddsa_priv,
      &ds->account_pub.merchant_pub.eddsa_pub);
  }
  else
  {
    GNUNET_CRYPTO_eddsa_key_create (
      &ds->account_priv.merchant_priv.eddsa_priv);
    GNUNET_CRYPTO_eddsa_key_get_public (
      &ds->account_priv.merchant_priv.eddsa_priv,
      &ds->account_pub.merchant_pub.eddsa_pub);
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
#if DUMP_CONTRACT
  fprintf (stderr,
           "Using contract:\n");
  json_dumpf (ds->contract_terms,
              stderr,
              JSON_INDENT (2));
#endif
  if ( (GNUNET_OK !=
        TALER_TESTING_get_trait_coin_priv (coin_cmd,
                                           ds->coin_index,
                                           &coin_priv)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_h_age_commitment (coin_cmd,
                                                  ds->coin_index,
                                                  &phac)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_denom_pub (coin_cmd,
                                           ds->coin_index,
                                           &ds->denom_pub)) ||
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

  ds->deposit_fee = ds->denom_pub->fees.deposit;
  GNUNET_CRYPTO_eddsa_key_get_public (&coin_priv->eddsa_priv,
                                      &coin_pub.eddsa_pub);

  {
    struct TALER_MerchantWireHashP h_wire;

    GNUNET_assert (GNUNET_OK ==
                   TALER_JSON_merchant_wire_signature_hash (ds->wire_details,
                                                            &h_wire));
    TALER_wallet_deposit_sign (&ds->amount,
                               &ds->denom_pub->fees.deposit,
                               &h_wire,
                               &h_contract_terms,
                               NULL, /* wallet data hash */
                               phac,
                               NULL, /* hash of extensions */
                               &ds->denom_pub->h_key,
                               ds->wallet_timestamp,
                               &ds->account_pub.merchant_pub,
                               ds->refund_deadline,
                               coin_priv,
                               &ds->coin_sig);
    ds->che.type = TALER_EXCHANGE_CTT_DEPOSIT;
    ds->che.amount = ds->amount;
    ds->che.details.deposit.h_wire = h_wire;
    ds->che.details.deposit.h_contract_terms = h_contract_terms;
    ds->che.details.deposit.no_h_policy = true;
    ds->che.details.deposit.no_wallet_data_hash = true;
    ds->che.details.deposit.wallet_timestamp = ds->wallet_timestamp;
    ds->che.details.deposit.merchant_pub = ds->account_pub.merchant_pub;
    ds->che.details.deposit.refund_deadline = ds->refund_deadline;
    ds->che.details.deposit.sig = ds->coin_sig;
    ds->che.details.deposit.no_hac = true;
    ds->che.details.deposit.deposit_fee = ds->denom_pub->fees.deposit;
  }
  GNUNET_assert (NULL == ds->dh);
  {
    struct TALER_EXCHANGE_CoinDepositDetail cdd = {
      .amount = ds->amount,
      .coin_pub = coin_pub,
      .coin_sig = ds->coin_sig,
      .denom_sig = *denom_pub_sig,
      .h_denom_pub = ds->denom_pub->h_key,
      .h_age_commitment = {{{0}}},
    };
    struct TALER_EXCHANGE_DepositContractDetail dcd = {
      .wire_deadline = ds->wire_deadline,
      .merchant_payto_uri = payto_uri,
      .wire_salt = wire_salt,
      .h_contract_terms = h_contract_terms,
      .wallet_timestamp = ds->wallet_timestamp,
      .merchant_pub = ds->account_pub.merchant_pub,
      .refund_deadline = ds->refund_deadline
    };

    if (NULL != phac)
      cdd.h_age_commitment = *phac;

    ds->dh = TALER_EXCHANGE_batch_deposit (
      TALER_TESTING_interpreter_get_context (is),
      exchange_url,
      TALER_TESTING_get_keys (is),
      &dcd,
      1,
      &cdd,
      &deposit_cb,
      ds,
      &ec);
  }
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
    TALER_TESTING_command_incomplete (ds->is,
                                      cmd->label);
    TALER_EXCHANGE_batch_deposit_cancel (ds->dh);
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
  struct TALER_CoinSpendPublicKeyP coin_spent_pub;
  const struct TALER_AgeCommitmentProof *age_commitment_proof;
  const struct TALER_AgeCommitmentHash *h_age_commitment;

  if (! ds->command_initialized)
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
                                                      &age_commitment_proof)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_h_age_commitment (coin_cmd,
                                                  ds->coin_index,
                                                  &h_age_commitment)) )
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (ds->is);
    return GNUNET_NO;
  }

  GNUNET_CRYPTO_eddsa_key_get_public (&coin_spent_priv->eddsa_priv,
                                      &coin_spent_pub.eddsa_pub);

  {
    struct TALER_TESTING_Trait traits[] = {
      /* First two traits are only available if
         ds->traits is true */
      TALER_TESTING_make_trait_exchange_pub (0,
                                             &ds->exchange_pub),
      TALER_TESTING_make_trait_exchange_sig (0,
                                             &ds->exchange_sig),
      /* These traits are always available */
      TALER_TESTING_make_trait_coin_history (0,
                                             &ds->che),
      TALER_TESTING_make_trait_coin_priv (0,
                                          coin_spent_priv),
      TALER_TESTING_make_trait_coin_pub (0,
                                         &coin_spent_pub),
      TALER_TESTING_make_trait_denom_pub (0,
                                          ds->denom_pub),
      TALER_TESTING_make_trait_coin_sig (0,
                                         &ds->coin_sig),
      TALER_TESTING_make_trait_age_commitment_proof (0,
                                                     age_commitment_proof),
      TALER_TESTING_make_trait_h_age_commitment (0,
                                                 h_age_commitment),
      TALER_TESTING_make_trait_wire_details (ds->wire_details),
      TALER_TESTING_make_trait_contract_terms (ds->contract_terms),
      TALER_TESTING_make_trait_merchant_priv (&ds->account_priv.merchant_priv),
      TALER_TESTING_make_trait_merchant_pub (&ds->account_pub.merchant_pub),
      TALER_TESTING_make_trait_account_priv (&ds->account_priv),
      TALER_TESTING_make_trait_account_pub (&ds->account_pub),
      TALER_TESTING_make_trait_deposit_amount (0,
                                               &ds->amount),
      TALER_TESTING_make_trait_deposit_fee_amount (0,
                                                   &ds->deposit_fee),
      TALER_TESTING_make_trait_timestamp (0,
                                          &ds->exchange_timestamp),
      TALER_TESTING_make_trait_wire_deadline (0,
                                              &ds->wire_deadline),
      TALER_TESTING_make_trait_refund_deadline (0,
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
TALER_TESTING_cmd_deposit (
  const char *label,
  const char *coin_reference,
  unsigned int coin_index,
  struct TALER_FullPayto target_account_payto,
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
  ds->command_initialized = true;
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
TALER_TESTING_cmd_deposit_with_ref (
  const char *label,
  const char *coin_reference,
  unsigned int coin_index,
  struct TALER_FullPayto target_account_payto,
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
  GNUNET_assert (0 ==
                 json_object_set_new (ds->contract_terms,
                                      "timestamp",
                                      GNUNET_JSON_from_timestamp (
                                        ds->wallet_timestamp)));
  if (0 != refund_deadline.rel_value_us)
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
  ds->command_initialized = true;
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
TALER_TESTING_cmd_deposit_replay (
  const char *label,
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
