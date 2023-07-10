/*
  This file is part of TALER
  Copyright (C) 2018-2023 Taler Systems SA

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
  TALER_TESTING_touch_cmd (dcs->is);
  deposit_confirmation_run (dcs,
                            NULL,
                            dcs->is);
}


/**
 * Callback to analyze the /deposit-confirmation response, just used
 * to check if the response code is acceptable.
 *
 * @param cls closure.
 * @param dcr response details
 */
static void
deposit_confirmation_cb (
  void *cls,
  const struct TALER_AUDITOR_DepositConfirmationResponse *dcr)
{
  struct DepositConfirmationState *dcs = cls;
  const struct TALER_AUDITOR_HttpResponse *hr = &dcr->hr;

  dcs->dc = NULL;
  if (dcs->expected_response_code != hr->http_status)
  {
    if (0 != dcs->do_retry)
    {
      dcs->do_retry--;
      if ( (0 == hr->http_status) ||
           (TALER_EC_GENERIC_DB_SOFT_FAILURE == hr->ec) ||
           (MHD_HTTP_INTERNAL_SERVER_ERROR == hr->http_status) )
      {
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Retrying deposit confirmation failed with %u/%d\n",
                    hr->http_status,
                    (int) hr->ec);
        /* on DB conflicts, do not use backoff */
        if (TALER_EC_GENERIC_DB_SOFT_FAILURE == hr->ec)
          dcs->backoff = GNUNET_TIME_UNIT_ZERO;
        else
          dcs->backoff = GNUNET_TIME_randomized_backoff (dcs->backoff,
                                                         MAX_BACKOFF);
        TALER_TESTING_inc_tries (dcs->is);
        dcs->retry_task = GNUNET_SCHEDULER_add_delayed (dcs->backoff,
                                                        &do_retry,
                                                        dcs);
        return;
      }
    }
    TALER_TESTING_unexpected_status (dcs->is,
                                     hr->http_status,
                                     dcs->expected_response_code);
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
  static struct TALER_ExtensionPolicyHashP no_h_policy;
  struct DepositConfirmationState *dcs = cls;
  const struct TALER_TESTING_Command *deposit_cmd;
  struct TALER_MerchantWireHashP h_wire;
  struct TALER_PrivateContractHashP h_contract_terms;
  const struct GNUNET_TIME_Timestamp *exchange_timestamp = NULL;
  struct GNUNET_TIME_Timestamp timestamp;
  const struct GNUNET_TIME_Timestamp *wire_deadline;
  struct GNUNET_TIME_Timestamp refund_deadline
    = GNUNET_TIME_UNIT_ZERO_TS;
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
  const char *auditor_url;

  (void) cmd;
  dcs->is = is;
  GNUNET_assert (NULL != dcs->deposit_reference);
  {
    const struct TALER_TESTING_Command *auditor_cmd;

    auditor_cmd
      = TALER_TESTING_interpreter_get_command (is,
                                               "auditor");
    if (NULL == auditor_cmd)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_auditor_url (auditor_cmd,
                                             &auditor_url))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
  }
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
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_timestamp (deposit_cmd,
                                                    dcs->coin_index,
                                                    &exchange_timestamp));
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_wire_deadline (deposit_cmd,
                                                        dcs->coin_index,
                                                        &wire_deadline));
  GNUNET_assert (NULL != exchange_timestamp);
  keys = TALER_TESTING_get_keys (is);
  GNUNET_assert (NULL != keys);
  spk = TALER_EXCHANGE_get_signing_key_info (keys,
                                             exchange_pub);

  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_contract_terms (deposit_cmd,
                                                         &contract_terms));
  /* Very unlikely to fail */
  GNUNET_assert (NULL != contract_terms);
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_hash (contract_terms,
                                           &h_contract_terms));
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_wire_details (deposit_cmd,
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
                                                        &merchant_priv));
  GNUNET_CRYPTO_eddsa_key_get_public (&merchant_priv->eddsa_priv,
                                      &merchant_pub.eddsa_pub);
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (dcs->amount_without_fee,
                                         &amount_without_fee));
  {
    struct GNUNET_JSON_Specification spec[] = {
      /* timestamp is mandatory */
      GNUNET_JSON_spec_timestamp ("timestamp",
                                  &timestamp),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_timestamp ("refund_deadline",
                                    &refund_deadline),
        NULL),
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
    if (GNUNET_TIME_absolute_is_zero (refund_deadline.abs_time))
      refund_deadline = timestamp;
  }
  dcs->dc = TALER_AUDITOR_deposit_confirmation (
    TALER_TESTING_interpreter_get_context (is),
    auditor_url,
    &h_wire,
    &no_h_policy,
    &h_contract_terms,
    *exchange_timestamp,
    *wire_deadline,
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
    TALER_TESTING_command_incomplete (dcs->is,
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


struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit_confirmation (const char *label,
                                        const char *deposit_reference,
                                        unsigned int coin_index,
                                        const char *amount_without_fee,
                                        unsigned int expected_response_code)
{
  struct DepositConfirmationState *dcs;

  dcs = GNUNET_new (struct DepositConfirmationState);
  dcs->deposit_reference = deposit_reference;
  dcs->coin_index = coin_index;
  dcs->amount_without_fee = amount_without_fee;
  dcs->expected_response_code = expected_response_code;

  {
    struct TALER_TESTING_Command cmd = {
      .cls = dcs,
      .label = label,
      .run = &deposit_confirmation_run,
      .cleanup = &deposit_confirmation_cleanup
    };

    return cmd;
  }
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit_confirmation_with_retry (
  struct TALER_TESTING_Command cmd)
{
  struct DepositConfirmationState *dcs;

  GNUNET_assert (&deposit_confirmation_run == cmd.run);
  dcs = cmd.cls;
  dcs->do_retry = NUM_RETRIES;
  return cmd;
}


/* end of testing_auditor_api_cmd_deposit_confirmation.c */
