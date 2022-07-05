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
   * Reserve private key.
   */
  struct TALER_ReservePrivateKeyP reserve_priv;

  /**
   * Reserve public key.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

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
  ds->reserve_priv = *reserve_priv;
  GNUNET_CRYPTO_eddsa_key_create (&ds->purse_priv.eddsa_priv);
  GNUNET_CRYPTO_eddsa_key_get_public (&ds->purse_priv.eddsa_priv,
                                      &ds->purse_pub.eddsa_pub);
  GNUNET_CRYPTO_eddsa_key_get_public (&ds->reserve_priv.eddsa_priv,
                                      &ds->reserve_pub.eddsa_pub);
  GNUNET_CRYPTO_eddsa_key_create (&ds->merge_priv.eddsa_priv);
  GNUNET_CRYPTO_eddsa_key_get_public (&ds->merge_priv.eddsa_priv,
                                      &ds->merge_pub.eddsa_pub);
  GNUNET_CRYPTO_ecdhe_key_create (&ds->contract_priv.ecdhe_priv);
  ds->purse_expiration = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_relative_to_absolute (ds->expiration_rel));
  GNUNET_assert (0 ==
                 json_object_set_new (
                   ds->contract_terms,
                   "pay_deadline",
                   GNUNET_JSON_from_timestamp (ds->purse_expiration)));
  ds->merge_timestamp = GNUNET_TIME_timestamp_get ();
  ds->dh = TALER_EXCHANGE_purse_create_with_merge (
    is->exchange,
    &ds->reserve_priv,
    &ds->purse_priv,
    &ds->merge_priv,
    &ds->contract_priv,
    ds->contract_terms,
    true /* upload contract */,
    true /* do pay purse fee -- FIXME #7274: make this a choice to test this case; then update testing_api_cmd_purse_deposit flags logic to match! */,
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
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ds->is->ip,
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
    TALER_TESTING_make_trait_timestamp (0,
                                        &ds->merge_timestamp),
    TALER_TESTING_make_trait_contract_terms (ds->contract_terms),
    TALER_TESTING_make_trait_purse_priv (&ds->purse_priv),
    TALER_TESTING_make_trait_purse_pub (&ds->purse_pub),
    TALER_TESTING_make_trait_merge_priv (&ds->merge_priv),
    TALER_TESTING_make_trait_merge_pub (&ds->merge_pub),
    TALER_TESTING_make_trait_contract_priv (&ds->contract_priv),
    TALER_TESTING_make_trait_reserve_priv (&ds->reserve_priv),
    TALER_TESTING_make_trait_reserve_pub (&ds->reserve_pub),
    TALER_TESTING_make_trait_reserve_sig (&ds->reserve_sig),
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
