/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

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
 * @file testing/testing_api_cmd_auditor_deposit_confirmation.c
 * @brief command for testing /deposit_confirmation.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_auditor_service.h"
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"

/**
 * How long do we wait AT MOST when retrying?
 */
#define MAX_BACKOFF GNUNET_TIME_relative_multiply ( \
    GNUNET_TIME_UNIT_MILLISECONDS, 100)

/**
 * How often do we retry before giving up?
 */
#define NUM_RETRIES 5


/**
 * State for a "deposit confirmation" CMD.
 */
struct DepositConfirmationState
{

  /**
   * Reference to any command that is able to provide a deposit.
   */
  const char *deposit_reference;

  /**
   * What is the deposited amount without the fee (i.e. the
   * amount we expect in the deposit confirmation)?
   */
  const char *amount_without_fee;

  /**
   * Which coin of the @e deposit_reference should we confirm.
   */
  unsigned int coin_index;

  /**
   * DepositConfirmation handle while operation is running.
   */
  struct TALER_AUDITOR_DepositConfirmationHandle *dc;

  /**
   * Auditor connection.
   */
  struct TALER_AUDITOR_Handle *auditor;

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

};


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
deposit_confirmation_run (void *cls,
                          const struct TALER_TESTING_Command *cmd,
                          struct TALER_TESTING_Interpreter *is);


/**
 * Task scheduled to re-try #deposit_confirmation_run.
 *
 * @param cls a `struct DepositConfirmationState`
 */
static void
do_retry (void *cls)
{
  struct DepositConfirmationState *dcs = cls;

  dcs->retry_task = NULL;
  deposit_confirmation_run (dcs,
                            NULL,
                            dcs->is);
}


/**
 * Callback to analyze the /deposit-confirmation response, just used
 * to check if the response code is acceptable.
 *
 * @param cls closure.
 * @param http_status HTTP response code.
 * @param ec taler-specific error code.
 * @param obj raw response from the auditor.
 */
static void
deposit_confirmation_cb (void *cls,
                         unsigned int http_status,
                         enum TALER_ErrorCode ec,
                         const json_t *obj)
{
  struct DepositConfirmationState *dcs = cls;

  dcs->dc = NULL;
  if (dcs->expected_response_code != http_status)
  {
    if (0 != dcs->do_retry)
    {
      dcs->do_retry--;
      if ( (0 == http_status) ||
           (TALER_EC_DB_COMMIT_FAILED_ON_RETRY == ec) ||
           (MHD_HTTP_INTERNAL_SERVER_ERROR == http_status) )
      {
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Retrying deposit confirmation failed with %u/%d\n",
                    http_status,
                    (int) ec);
        /* on DB conflicts, do not use backoff */
        if (TALER_EC_DB_COMMIT_FAILED_ON_RETRY == ec)
          dcs->backoff = GNUNET_TIME_UNIT_ZERO;
        else
          dcs->backoff = GNUNET_TIME_randomized_backoff (dcs->backoff,
                                                         MAX_BACKOFF);
        dcs->retry_task = GNUNET_SCHEDULER_add_delayed (dcs->backoff,
                                                        &do_retry,
                                                        dcs);
        return;
      }
    }
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u to command %s in %s:%u\n",
                http_status,
                dcs->is->commands[dcs->is->ip].label,
                __FILE__,
                __LINE__);
    json_dumpf (obj, stderr, 0);
    TALER_TESTING_interpreter_fail (dcs->is);
    return;
  }
  TALER_TESTING_interpreter_next (dcs->is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
deposit_confirmation_run (void *cls,
                          const struct TALER_TESTING_Command *cmd,
                          struct TALER_TESTING_Interpreter *is)
{
  struct DepositConfirmationState *dcs = cls;
  const struct TALER_TESTING_Command *deposit_cmd;
  struct GNUNET_HashCode h_wire;
  struct GNUNET_HashCode h_contract_terms;
  struct GNUNET_TIME_Absolute timestamp;
  struct GNUNET_TIME_Absolute refund_deadline;
  struct TALER_Amount amount_without_fee;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  const struct TALER_MerchantPrivateKeyP *merchant_priv;
  struct TALER_MerchantPublicKeyP merchant_pub;
  const struct TALER_ExchangePublicKeyP *exchange_pub;
  const struct TALER_ExchangeSignatureP *exchange_sig;
  const json_t *wire_details;
  const json_t *contract_terms;
  const struct TALER_CoinSpendPrivateKeyP *coin_priv;
  const struct TALER_EXCHANGE_Keys *keys;
  const struct TALER_EXCHANGE_SigningPublicKey *spk;

  dcs->is = is;
  GNUNET_assert (NULL != dcs->deposit_reference);
  deposit_cmd
    = TALER_TESTING_interpreter_lookup_command (is,
                                                dcs->deposit_reference);
  if (NULL == deposit_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_exchange_pub (deposit_cmd,
                                                       dcs->coin_index,
                                                       &exchange_pub));
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_exchange_sig (deposit_cmd,
                                                       dcs->coin_index,
                                                       &exchange_sig));
  keys = TALER_EXCHANGE_get_keys (dcs->is->exchange);
  GNUNET_assert (NULL != keys);
  spk = TALER_EXCHANGE_get_signing_key_info (keys,
                                             exchange_pub);

  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_contract_terms (deposit_cmd,
                                                         dcs->coin_index,
                                                         &contract_terms));
  /* Very unlikely to fail */
  GNUNET_assert (NULL != contract_terms);
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_hash (contract_terms,
                                  &h_contract_terms));
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_wire_details (deposit_cmd,
                                                       dcs->coin_index,
                                                       &wire_details));
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_merchant_wire_signature_hash (wire_details,
                                                          &h_wire));
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_coin_priv (deposit_cmd,
                                                    dcs->coin_index,
                                                    &coin_priv));
  GNUNET_CRYPTO_eddsa_key_get_public (&coin_priv->eddsa_priv,
                                      &coin_pub.eddsa_pub);
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_merchant_priv (deposit_cmd,
                                                        dcs->coin_index,
                                                        &merchant_priv));
  GNUNET_CRYPTO_eddsa_key_get_public (&merchant_priv->eddsa_priv,
                                      &merchant_pub.eddsa_pub);
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (dcs->amount_without_fee,
                                         &amount_without_fee));
  /* timestamp is mandatory */
  {
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_absolute_time ("timestamp", &timestamp),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (contract_terms,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
  }
  /* refund deadline is optional, defaults to zero */
  {
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_absolute_time ("refund_deadline", &refund_deadline),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (contract_terms,
                           spec,
                           NULL, NULL))
    {
      refund_deadline = timestamp;
    }
  }
  dcs->dc = TALER_AUDITOR_deposit_confirmation
              (dcs->auditor,
              &h_wire,
              &h_contract_terms,
              timestamp,
              refund_deadline,
              &amount_without_fee,
              &coin_pub,
              &merchant_pub,
              exchange_pub,
              exchange_sig,
              &keys->master_pub,
              spk->valid_from,
              spk->valid_until,
              spk->valid_legal,
              &spk->master_sig,
              &deposit_confirmation_cb,
              dcs);

  if (NULL == dcs->dc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  return;
}


/**
 * Free the state of a "deposit_confirmation" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, a `struct DepositConfirmationState`
 * @param cmd the command which is being cleaned up.
 */
static void
deposit_confirmation_cleanup (void *cls,
                              const struct TALER_TESTING_Command *cmd)
{
  struct DepositConfirmationState *dcs = cls;

  if (NULL != dcs->dc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                dcs->is->ip,
                cmd->label);
    TALER_AUDITOR_deposit_confirmation_cancel (dcs->dc);
    dcs->dc = NULL;
  }
  if (NULL != dcs->retry_task)
  {
    GNUNET_SCHEDULER_cancel (dcs->retry_task);
    dcs->retry_task = NULL;
  }
  GNUNET_free (dcs);
}


/**
 * Offer internal data to other commands.
 *
 * @param cls closure.
 * @param[out] ret set to the wanted data.
 * @param trait name of the trait.
 * @param index index number of the traits to be returned.
 *
 * @return #GNUNET_OK on success
 */
static int
deposit_confirmation_traits (void *cls,
                             const void **ret,
                             const char *trait,
                             unsigned int index)
{
  /* Must define this function because some callbacks
   * look for certain traits on _all_ the commands. */
  return GNUNET_SYSERR;
}


/**
 * Create a "deposit-confirmation" command.
 *
 * @param label command label.
 * @param auditor auditor connection.
 * @param deposit_reference reference to any operation that can
 *        provide a coin.
 * @param coin_index if @a deposit_reference offers an array of
 *        coins, this parameter selects which one in that array.
 *        This value is currently ignored, as only one-coin
 *        deposits are implemented.
 * @param amount_without_fee deposited amount without the fee
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit_confirmation (const char *label,
                                        struct TALER_AUDITOR_Handle *auditor,
                                        const char *deposit_reference,
                                        unsigned int coin_index,
                                        const char *amount_without_fee,
                                        unsigned int expected_response_code)
{
  struct DepositConfirmationState *dcs;

  dcs = GNUNET_new (struct DepositConfirmationState);
  dcs->auditor = auditor;
  dcs->deposit_reference = deposit_reference;
  dcs->coin_index = coin_index;
  dcs->amount_without_fee = amount_without_fee;
  dcs->expected_response_code = expected_response_code;

  {
    struct TALER_TESTING_Command cmd = {
      .cls = dcs,
      .label = label,
      .run = &deposit_confirmation_run,
      .cleanup = &deposit_confirmation_cleanup,
      .traits = &deposit_confirmation_traits
    };

    return cmd;
  }
}


/**
 * Modify a deposit confirmation command to enable retries when we get
 * transient errors from the auditor.
 *
 * @param cmd a deposit confirmation command
 * @return the command with retries enabled
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit_confirmation_with_retry (struct TALER_TESTING_Command
                                                   cmd)
{
  struct DepositConfirmationState *dcs;

  GNUNET_assert (&deposit_confirmation_run == cmd.run);
  dcs = cmd.cls;
  dcs->do_retry = NUM_RETRIES;
  return cmd;
}


/* end of testing_auditor_api_cmd_deposit_confirmation.c */
