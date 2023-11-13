/*
  This file is part of TALER
  Copyright (C) 2018-2022 Taler Systems SA

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
 * @file testing/testing_api_cmd_batch_deposit.c
 * @brief command for testing /batch-deposit.
 * @author Marcello Stanisci
 * @author Christian Grothoff
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
 * Information per coin in the batch.
 */
struct Coin
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
   * Our coin signature.
   */
  struct TALER_CoinSpendSignatureP coin_sig;

  /**
   * Reference to any command that is able to provide a coin,
   * possibly using $LABEL#$INDEX notation.
   */
  char *coin_reference;

  /**
   * Denomination public key of the coin.
   */
  const struct TALER_EXCHANGE_DenomPublicKey *denom_pub;

  /**
   * The command being referenced.
   */
  const struct TALER_TESTING_Command *coin_cmd;

  /**
   * Expected entry in the coin history created by this
   * coin.
   */
  struct TALER_EXCHANGE_CoinHistoryEntry che;

  /**
   * Index of the coin at @e coin_cmd.
   */
  unsigned int coin_idx;
};


/**
 * State for a "batch deposit" CMD.
 */
struct BatchDepositState
{

  /**
   * Refund deadline. Zero for no refunds.
   */
  struct GNUNET_TIME_Timestamp refund_deadline;

  /**
   * Wire deadline.
   */
  struct GNUNET_TIME_Timestamp wire_deadline;

  /**
   * Timestamp of the /deposit operation in the wallet (contract signing time).
   */
  struct GNUNET_TIME_Timestamp wallet_timestamp;

  /**
   * How long do we wait until we retry?
   */
  struct GNUNET_TIME_Relative backoff;

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
   * Set (by the interpreter) to a fresh private key.  This
   * key will be used to sign the deposit request.
   */
  struct TALER_MerchantPrivateKeyP merchant_priv;

  /**
   * Deposit handle while operation is running.
   */
  struct TALER_EXCHANGE_BatchDepositHandle *dh;

  /**
   * Array of coins to batch-deposit.
   */
  struct Coin *coins;

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
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Task scheduled to try later.
   */
  struct GNUNET_SCHEDULER_Task *retry_task;

  /**
   * Deposit confirmation signature from the exchange.
   */
  struct TALER_ExchangeSignatureP exchange_sig;

  /**
   * Reference to previous deposit operation.
   * Only present if we're supposed to replay the previous deposit.
   */
  const char *deposit_reference;

  /**
   * If @e coin_reference refers to an operation that generated
   * an array of coins, this value determines which coin to pick.
   */
  unsigned int num_coins;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Set to true if the /deposit succeeded
   * and we now can provide the resulting traits.
   */
  bool deposit_succeeded;

};


/**
 * Callback to analyze the /batch-deposit response, just used to check if the
 * response code is acceptable.
 *
 * @param cls closure.
 * @param dr deposit response details
 */
static void
batch_deposit_cb (void *cls,
                  const struct TALER_EXCHANGE_BatchDepositResult *dr)
{
  struct BatchDepositState *ds = cls;

  ds->dh = NULL;
  if (ds->expected_response_code != dr->hr.http_status)
  {
    TALER_TESTING_unexpected_status (ds->is,
                                     dr->hr.http_status,
                                     ds->expected_response_code);
    return;
  }
  if (MHD_HTTP_OK == dr->hr.http_status)
  {
    ds->deposit_succeeded = GNUNET_YES;
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
batch_deposit_run (void *cls,
                   const struct TALER_TESTING_Command *cmd,
                   struct TALER_TESTING_Interpreter *is)
{
  struct BatchDepositState *ds = cls;
  const struct TALER_DenominationSignature *denom_pub_sig;
  struct TALER_MerchantPublicKeyP merchant_pub;
  struct TALER_PrivateContractHashP h_contract_terms;
  enum TALER_ErrorCode ec;
  struct TALER_WireSaltP wire_salt;
  struct TALER_MerchantWireHashP h_wire;
  const char *payto_uri;
  struct TALER_EXCHANGE_CoinDepositDetail cdds[ds->num_coins];
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("payto_uri",
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
  memset (cdds,
          0,
          sizeof (cdds));
  ds->is = is;
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
  if (GNUNET_OK !=
      TALER_JSON_contract_hash (ds->contract_terms,
                                &h_contract_terms))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_merchant_wire_signature_hash (ds->wire_details,
                                                          &h_wire));
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

  for (unsigned int i = 0; i<ds->num_coins; i++)
  {
    struct Coin *coin = &ds->coins[i];
    struct TALER_EXCHANGE_CoinDepositDetail *cdd = &cdds[i];
    const struct TALER_CoinSpendPrivateKeyP *coin_priv;
    const struct TALER_AgeCommitmentProof *age_commitment_proof = NULL;

    GNUNET_assert (NULL != coin->coin_reference);
    cdd->amount = coin->amount;
    coin->coin_cmd = TALER_TESTING_interpreter_lookup_command (
      is,
      coin->coin_reference);
    if (NULL == coin->coin_cmd)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }

    if ( (GNUNET_OK !=
          TALER_TESTING_get_trait_coin_priv (coin->coin_cmd,
                                             coin->coin_idx,
                                             &coin_priv)) ||
         (GNUNET_OK !=
          TALER_TESTING_get_trait_age_commitment_proof (coin->coin_cmd,
                                                        coin->coin_idx,
                                                        &age_commitment_proof))
         ||
         (GNUNET_OK !=
          TALER_TESTING_get_trait_denom_pub (coin->coin_cmd,
                                             coin->coin_idx,
                                             &coin->denom_pub)) ||
         (GNUNET_OK !=
          TALER_TESTING_get_trait_denom_sig (coin->coin_cmd,
                                             coin->coin_idx,
                                             &denom_pub_sig)) )
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if (NULL != age_commitment_proof)
    {
      TALER_age_commitment_hash (&age_commitment_proof->commitment,
                                 &cdd->h_age_commitment);
    }
    coin->deposit_fee = coin->denom_pub->fees.deposit;
    GNUNET_CRYPTO_eddsa_key_get_public (&coin_priv->eddsa_priv,
                                        &cdd->coin_pub.eddsa_pub);
    cdd->denom_sig = *denom_pub_sig;
    cdd->h_denom_pub = coin->denom_pub->h_key;
    TALER_wallet_deposit_sign (&coin->amount,
                               &coin->denom_pub->fees.deposit,
                               &h_wire,
                               &h_contract_terms,
                               NULL, /* wallet_data_hash */
                               &cdd->h_age_commitment,
                               NULL, /* hash of extensions */
                               &coin->denom_pub->h_key,
                               ds->wallet_timestamp,
                               &merchant_pub,
                               ds->refund_deadline,
                               coin_priv,
                               &cdd->coin_sig);
    coin->coin_sig = cdd->coin_sig;
    coin->che.type = TALER_EXCHANGE_CTT_DEPOSIT;
    coin->che.amount = coin->amount;
    coin->che.details.deposit.h_wire = h_wire;
    coin->che.details.deposit.h_contract_terms = h_contract_terms;
    coin->che.details.deposit.no_h_policy = true;
    coin->che.details.deposit.no_wallet_data_hash = true;
    coin->che.details.deposit.wallet_timestamp = ds->wallet_timestamp;
    coin->che.details.deposit.merchant_pub = merchant_pub;
    coin->che.details.deposit.refund_deadline = ds->refund_deadline;
    coin->che.details.deposit.sig = cdd->coin_sig;
    coin->che.details.deposit.no_hac = GNUNET_is_zero (&cdd->h_age_commitment);
    coin->che.details.deposit.hac = cdd->h_age_commitment;
    coin->che.details.deposit.deposit_fee = coin->denom_pub->fees.deposit;
  }

  GNUNET_assert (NULL == ds->dh);
  {
    struct TALER_EXCHANGE_DepositContractDetail dcd = {
      .wire_deadline = ds->wire_deadline,
      .merchant_payto_uri = payto_uri,
      .wire_salt = wire_salt,
      .h_contract_terms = h_contract_terms,
      .policy_details = NULL /* FIXME #7270-OEC */,
      .wallet_timestamp = ds->wallet_timestamp,
      .merchant_pub = merchant_pub,
      .refund_deadline = ds->refund_deadline
    };

    ds->dh = TALER_EXCHANGE_batch_deposit (
      TALER_TESTING_interpreter_get_context (is),
      exchange_url,
      TALER_TESTING_get_keys (is),
      &dcd,
      ds->num_coins,
      cdds,
      &batch_deposit_cb,
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
 * Free the state of a "batch-deposit" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct BatchDepositState`.
 * @param cmd the command which is being cleaned up.
 */
static void
batch_deposit_cleanup (void *cls,
                       const struct TALER_TESTING_Command *cmd)
{
  struct BatchDepositState *ds = cls;

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
  for (unsigned int i = 0; i<ds->num_coins; i++)
    GNUNET_free (ds->coins[i].coin_reference);
  GNUNET_free (ds->coins);
  json_decref (ds->wire_details);
  json_decref (ds->contract_terms);
  GNUNET_free (ds);
}


/**
 * Offer internal data from a "batch-deposit" CMD, to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
batch_deposit_traits (void *cls,
                      const void **ret,
                      const char *trait,
                      unsigned int index)
{
  struct BatchDepositState *ds = cls;
  const struct Coin *coin = &ds->coins[index];
  /* Will point to coin cmd internals. */
  const struct TALER_CoinSpendPrivateKeyP *coin_spent_priv;
  struct TALER_CoinSpendPublicKeyP coin_spent_pub;
  const struct TALER_AgeCommitmentProof *age_commitment_proof;

  if (index >= ds->num_coins)
  {
    GNUNET_break (0);
    return GNUNET_NO;
  }
  if (NULL == coin->coin_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (ds->is);
    return GNUNET_NO;
  }
  if ( (GNUNET_OK !=
        TALER_TESTING_get_trait_coin_priv (coin->coin_cmd,
                                           coin->coin_idx,
                                           &coin_spent_priv)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_age_commitment_proof (coin->coin_cmd,
                                                      coin->coin_idx,
                                                      &age_commitment_proof)) )
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
         ds->traits is #GNUNET_YES */
      TALER_TESTING_make_trait_exchange_pub (0,
                                             &ds->exchange_pub),
      TALER_TESTING_make_trait_exchange_sig (0,
                                             &ds->exchange_sig),
      /* These traits are always available */
      TALER_TESTING_make_trait_wire_details (ds->wire_details),
      TALER_TESTING_make_trait_contract_terms (ds->contract_terms),
      TALER_TESTING_make_trait_merchant_priv (&ds->merchant_priv),
      TALER_TESTING_make_trait_age_commitment_proof (index,
                                                     age_commitment_proof),
      TALER_TESTING_make_trait_coin_history (index,
                                             &coin->che),
      TALER_TESTING_make_trait_coin_pub (index,
                                         &coin_spent_pub),
      TALER_TESTING_make_trait_denom_pub (index,
                                          coin->denom_pub),
      TALER_TESTING_make_trait_coin_priv (index,
                                          coin_spent_priv),
      TALER_TESTING_make_trait_coin_sig (index,
                                         &coin->coin_sig),
      TALER_TESTING_make_trait_deposit_amount (index,
                                               &coin->amount),
      TALER_TESTING_make_trait_deposit_fee_amount (index,
                                                   &coin->deposit_fee),
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
TALER_TESTING_cmd_batch_deposit (const char *label,
                                 const char *target_account_payto,
                                 const char *contract_terms,
                                 struct GNUNET_TIME_Relative refund_deadline,
                                 unsigned int expected_response_code,
                                 ...)
{
  struct BatchDepositState *ds;
  va_list ap;
  unsigned int num_coins = 0;
  const char *ref;

  va_start (ap,
            expected_response_code);
  while (NULL != (ref = va_arg (ap,
                                const char *)))
  {
    GNUNET_assert (NULL != va_arg (ap,
                                   const char *));
    num_coins++;
  }
  va_end (ap);

  ds = GNUNET_new (struct BatchDepositState);
  ds->num_coins = num_coins;
  ds->coins = GNUNET_new_array (num_coins,
                                struct Coin);
  num_coins = 0;
  va_start (ap,
            expected_response_code);
  while (NULL != (ref = va_arg (ap,
                                const char *)))
  {
    struct Coin *coin = &ds->coins[num_coins++];
    const char *amount = va_arg (ap,
                                 const char *);

    GNUNET_assert (GNUNET_OK ==
                   TALER_TESTING_parse_coin_reference (ref,
                                                       &coin->coin_reference,
                                                       &coin->coin_idx));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (amount,
                                           &coin->amount));
  }
  va_end (ap);

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
  ds->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ds,
      .label = label,
      .run = &batch_deposit_run,
      .cleanup = &batch_deposit_cleanup,
      .traits = &batch_deposit_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_batch_deposit.c */
