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
 * @file testing/testing_api_cmd_reserve_purse.c
 * @brief command for testing /reserves/$PID/purse
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"


/**
 * State for a "purse create with merge" CMD.
 */
struct ReservePurseState
{

  /**
   * Merge time (local time when the command was
   * executed).
   */
  struct GNUNET_TIME_Timestamp merge_timestamp;

  /**
   * Account (reserve) private key.
   */
  union TALER_AccountPrivateKeyP account_priv;

  /**
   * Account (reserve) public key.
   */
  union TALER_AccountPublicKeyP account_pub;

  /**
   * Reserve signature generated for the request
   * (client-side).
   */
  struct TALER_ReserveSignatureP reserve_sig;

  /**
   * Private key of the purse.
   */
  struct TALER_PurseContractPrivateKeyP purse_priv;

  /**
   * Public key of the purse.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * Private key with the merge capability.
   */
  struct TALER_PurseMergePrivateKeyP merge_priv;

  /**
   * Public key of the merge capability.
   */
  struct TALER_PurseMergePublicKeyP merge_pub;

  /**
   * Private key to decrypt the contract.
   */
  struct TALER_ContractDiffiePrivateP contract_priv;

  /**
   * Handle while operation is running.
   */
  struct TALER_EXCHANGE_PurseCreateMergeHandle *dh;

  /**
   * When will the purse expire?
   */
  struct GNUNET_TIME_Relative expiration_rel;

  /**
   * When will the purse expire?
   */
  struct GNUNET_TIME_Timestamp purse_expiration;

  /**
   * Hash of the payto://-URI for the reserve we are
   * merging into.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Set to the KYC requirement row *if* the exchange replied with
   * a request for KYC.
   */
  uint64_t requirement_row;

  /**
   * Contract terms for the purse.
   */
  json_t *contract_terms;

  /**
   * Reference to the reserve, or NULL (!).
   */
  const char *reserve_ref;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * True to pay the purse fee.
   */
  bool pay_purse_fee;
};


/**
 * Callback to analyze the /reserves/$PID/purse response, just used to check if
 * the response code is acceptable.
 *
 * @param cls closure.
 * @param dr purse response details
 */
static void
purse_cb (void *cls,
          const struct TALER_EXCHANGE_PurseCreateMergeResponse *dr)
{
  struct ReservePurseState *ds = cls;

  ds->dh = NULL;
  ds->reserve_sig = *dr->reserve_sig;
  if (ds->expected_response_code != dr->hr.http_status)
  {
    TALER_TESTING_unexpected_status (ds->is,
                                     dr->hr.http_status,
                                     ds->expected_response_code);
    return;
  }
  switch (dr->hr.http_status)
  {
  case MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS:
    /* KYC required */
    ds->requirement_row =
      dr->details.unavailable_for_legal_reasons.requirement_row;
    break;
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
purse_run (void *cls,
           const struct TALER_TESTING_Command *cmd,
           struct TALER_TESTING_Interpreter *is)
{
  struct ReservePurseState *ds = cls;
  const struct TALER_ReservePrivateKeyP *reserve_priv;
  const struct TALER_TESTING_Command *ref;

  (void) cmd;
  ds->is = is;
  ref = TALER_TESTING_interpreter_lookup_command (ds->is,
                                                  ds->reserve_ref);
  GNUNET_assert (NULL != ref);
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_reserve_priv (ref,
                                            &reserve_priv))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (ds->is);
    return;
  }
  ds->account_priv.reserve_priv = *reserve_priv;
  GNUNET_CRYPTO_eddsa_key_create (
    &ds->purse_priv.eddsa_priv);
  GNUNET_CRYPTO_eddsa_key_get_public (
    &ds->purse_priv.eddsa_priv,
    &ds->purse_pub.eddsa_pub);
  GNUNET_CRYPTO_eddsa_key_get_public (
    &ds->account_priv.reserve_priv.eddsa_priv,
    &ds->account_pub.reserve_pub.eddsa_pub);
  GNUNET_CRYPTO_eddsa_key_create (
    &ds->merge_priv.eddsa_priv);
  GNUNET_CRYPTO_eddsa_key_get_public (
    &ds->merge_priv.eddsa_priv,
    &ds->merge_pub.eddsa_pub);
  GNUNET_CRYPTO_ecdhe_key_create (
    &ds->contract_priv.ecdhe_priv);
  ds->purse_expiration
    = GNUNET_TIME_absolute_to_timestamp (
        GNUNET_TIME_relative_to_absolute (
          ds->expiration_rel));

  {
    char *payto_uri;
    const char *exchange_url;
    const struct TALER_TESTING_Command *exchange_cmd;

    exchange_cmd = TALER_TESTING_interpreter_get_command (is,
                                                          "exchange");
    if (NULL == exchange_cmd)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    GNUNET_assert (
      GNUNET_OK ==
      TALER_TESTING_get_trait_exchange_url (
        exchange_cmd,
        &exchange_url));
    payto_uri
      = TALER_reserve_make_payto (
          exchange_url,
          &ds->account_pub.reserve_pub);
    TALER_payto_hash (payto_uri,
                      &ds->h_payto);
    GNUNET_free (payto_uri);
  }

  GNUNET_assert (0 ==
                 json_object_set_new (
                   ds->contract_terms,
                   "pay_deadline",
                   GNUNET_JSON_from_timestamp (ds->purse_expiration)));
  ds->merge_timestamp = GNUNET_TIME_timestamp_get ();
  ds->dh = TALER_EXCHANGE_purse_create_with_merge (
    TALER_TESTING_interpreter_get_context (is),
    TALER_TESTING_get_exchange_url (is),
    TALER_TESTING_get_keys (is),
    &ds->account_priv.reserve_priv,
    &ds->purse_priv,
    &ds->merge_priv,
    &ds->contract_priv,
    ds->contract_terms,
    true /* upload contract */,
    ds->pay_purse_fee,
    ds->merge_timestamp,
    &purse_cb,
    ds);
  if (NULL == ds->dh)
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not purse reserve\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "purse" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct ReservePurseState`.
 * @param cmd the command which is being cleaned up.
 */
static void
purse_cleanup (void *cls,
               const struct TALER_TESTING_Command *cmd)
{
  struct ReservePurseState *ds = cls;

  if (NULL != ds->dh)
  {
    TALER_TESTING_command_incomplete (ds->is,
                                      cmd->label);
    TALER_EXCHANGE_purse_create_with_merge_cancel (ds->dh);
    ds->dh = NULL;
  }
  json_decref (ds->contract_terms);
  GNUNET_free (ds);
}


/**
 * Offer internal data from a "purse" CMD, to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
purse_traits (void *cls,
              const void **ret,
              const char *trait,
              unsigned int index)
{
  struct ReservePurseState *ds = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_timestamp (
      0,
      &ds->merge_timestamp),
    TALER_TESTING_make_trait_contract_terms (
      ds->contract_terms),
    TALER_TESTING_make_trait_purse_priv (
      &ds->purse_priv),
    TALER_TESTING_make_trait_purse_pub (
      &ds->purse_pub),
    TALER_TESTING_make_trait_merge_priv (
      &ds->merge_priv),
    TALER_TESTING_make_trait_merge_pub (
      &ds->merge_pub),
    TALER_TESTING_make_trait_contract_priv (
      &ds->contract_priv),
    TALER_TESTING_make_trait_account_priv (
      &ds->account_priv),
    TALER_TESTING_make_trait_account_pub (
      &ds->account_pub),
    TALER_TESTING_make_trait_reserve_priv (
      &ds->account_priv.reserve_priv),
    TALER_TESTING_make_trait_reserve_pub (
      &ds->account_pub.reserve_pub),
    TALER_TESTING_make_trait_reserve_sig (
      &ds->reserve_sig),
    TALER_TESTING_make_trait_legi_requirement_row (
      &ds->requirement_row),
    TALER_TESTING_make_trait_h_payto (
      &ds->h_payto),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_purse_create_with_reserve (
  const char *label,
  unsigned int expected_http_status,
  const char *contract_terms,
  bool upload_contract,
  bool pay_purse_fee,
  struct GNUNET_TIME_Relative expiration,
  const char *reserve_ref)
{
  struct ReservePurseState *ds;
  json_error_t err;

  ds = GNUNET_new (struct ReservePurseState);
  ds->expiration_rel = expiration;
  ds->contract_terms = json_loads (contract_terms,
                                   0 /* flags */,
                                   &err);
  GNUNET_assert (NULL != ds->contract_terms);
  ds->pay_purse_fee = pay_purse_fee;
  ds->reserve_ref = reserve_ref;
  ds->expected_response_code = expected_http_status;

  {
    struct TALER_TESTING_Command cmd = {
      .cls = ds,
      .label = label,
      .run = &purse_run,
      .cleanup = &purse_cleanup,
      .traits = &purse_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_reserve_purse.c */
