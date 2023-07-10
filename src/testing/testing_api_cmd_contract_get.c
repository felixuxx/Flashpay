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
 * @file testing/testing_api_cmd_contract_get.c
 * @brief command for testing GET /contracts/$CPUB
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"


/**
 * State for a "contract get" CMD.
 */
struct ContractGetState
{

  /**
   * JSON string describing the resulting contract.
   */
  json_t *contract_terms;

  /**
   * Private key to decrypt the contract.
   */
  struct TALER_ContractDiffiePrivateP contract_priv;

  /**
   * Set to the returned merge key.
   */
  struct TALER_PurseMergePrivateKeyP merge_priv;

  /**
   * Public key of the purse.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * Reference to the command that uploaded the contract.
   */
  const char *contract_ref;

  /**
   * ContractGet handle while operation is running.
   */
  struct TALER_EXCHANGE_ContractsGetHandle *dh;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * True if this is for a 'merge' operation,
   * 'false' if this is for a 'deposit' operation.
   */
  bool merge;

};


/**
 * Callback to analyze the /contracts/$CPUB response, just used to check if
 * the response code is acceptable.
 *
 * @param cls closure.
 * @param dr get response details
 */
static void
get_cb (void *cls,
        const struct TALER_EXCHANGE_ContractGetResponse *dr)
{
  struct ContractGetState *ds = cls;
  const struct TALER_TESTING_Command *ref;

  ds->dh = NULL;
  if (ds->expected_response_code != dr->hr.http_status)
  {
    TALER_TESTING_unexpected_status (ds->is,
                                     dr->hr.http_status,
                                     ds->expected_response_code);
    return;
  }
  ref = TALER_TESTING_interpreter_lookup_command (ds->is,
                                                  ds->contract_ref);
  GNUNET_assert (NULL != ref);
  if (MHD_HTTP_OK == dr->hr.http_status)
  {
    const struct TALER_PurseMergePrivateKeyP *mp;
    const json_t *ct;

    ds->purse_pub = dr->details.ok.purse_pub;
    if (ds->merge)
    {
      if (GNUNET_OK !=
          TALER_TESTING_get_trait_merge_priv (ref,
                                              &mp))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (ds->is);
        return;
      }
      ds->contract_terms =
        TALER_CRYPTO_contract_decrypt_for_merge (
          &ds->contract_priv,
          &ds->purse_pub,
          dr->details.ok.econtract,
          dr->details.ok.econtract_size,
          &ds->merge_priv);
      if (0 !=
          GNUNET_memcmp (mp,
                         &ds->merge_priv))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (ds->is);
        return;
      }
    }
    else
    {
      ds->contract_terms =
        TALER_CRYPTO_contract_decrypt_for_deposit (
          &ds->contract_priv,
          dr->details.ok.econtract,
          dr->details.ok.econtract_size);
    }
    if (NULL == ds->contract_terms)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (ds->is);
      return;
    }
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_contract_terms (ref,
                                                &ct))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (ds->is);
      return;
    }
    if (1 != /* 1: equal, 0: not equal */
        json_equal (ct,
                    ds->contract_terms))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (ds->is);
      return;
    }
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
get_run (void *cls,
         const struct TALER_TESTING_Command *cmd,
         struct TALER_TESTING_Interpreter *is)
{
  struct ContractGetState *ds = cls;
  const struct TALER_ContractDiffiePrivateP *contract_priv;
  const struct TALER_TESTING_Command *ref;
  const char *exchange_url;

  (void) cmd;
  ds->is = is;
  exchange_url = TALER_TESTING_get_exchange_url (is);
  if (NULL == exchange_url)
  {
    GNUNET_break (0);
    return;
  }
  ref = TALER_TESTING_interpreter_lookup_command (ds->is,
                                                  ds->contract_ref);
  GNUNET_assert (NULL != ref);
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_contract_priv (ref,
                                             &contract_priv))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (ds->is);
    return;
  }
  ds->contract_priv = *contract_priv;
  ds->dh = TALER_EXCHANGE_contract_get (
    TALER_TESTING_interpreter_get_context (is),
    exchange_url,
    contract_priv,
    &get_cb,
    ds);
  if (NULL == ds->dh)
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not GET contract\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "get" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct ContractGetState`.
 * @param cmd the command which is being cleaned up.
 */
static void
get_cleanup (void *cls,
             const struct TALER_TESTING_Command *cmd)
{
  struct ContractGetState *ds = cls;

  if (NULL != ds->dh)
  {
    TALER_TESTING_command_incomplete (ds->is,
                                      cmd->label);
    TALER_EXCHANGE_contract_get_cancel (ds->dh);
    ds->dh = NULL;
  }
  json_decref (ds->contract_terms);
  GNUNET_free (ds);
}


/**
 * Offer internal data from a "get" CMD, to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
get_traits (void *cls,
            const void **ret,
            const char *trait,
            unsigned int index)
{
  struct ContractGetState *ds = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_merge_priv (&ds->merge_priv),
    TALER_TESTING_make_trait_purse_pub (&ds->purse_pub),
    TALER_TESTING_make_trait_contract_terms (ds->contract_terms),
    TALER_TESTING_trait_end ()
  };

  /* skip 'merge_priv' if we are in 'merge' mode */
  return TALER_TESTING_get_trait (&traits[ds->merge ? 0 : 1],
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_contract_get (
  const char *label,
  unsigned int expected_http_status,
  bool for_merge,
  const char *contract_ref)
{
  struct ContractGetState *ds;

  ds = GNUNET_new (struct ContractGetState);
  ds->expected_response_code = expected_http_status;
  ds->contract_ref = contract_ref;
  ds->merge = for_merge;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ds,
      .label = label,
      .run = &get_run,
      .cleanup = &get_cleanup,
      .traits = &get_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_contract_get.c */
