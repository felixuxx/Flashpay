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
 * @file testing/testing_api_cmd_purse_merge.c
 * @brief command for testing /purses/$PID/merge
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"


/**
 * State for a "purse create deposit" CMD.
 */
struct PurseMergeState
{

  /**
   * Merge time.
   */
  struct GNUNET_TIME_Timestamp merge_timestamp;

  /**
   * Reserve public key (to be merged into)
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Reserve private key (useful especially if
   * @e reserve_ref is NULL).
   */
  struct TALER_ReservePrivateKeyP reserve_priv;

  /**
   * Handle while operation is running.
   */
  struct TALER_EXCHANGE_AccountMergeHandle *dh;

  /**
   * Reference to the merge capability.
   */
  const char *merge_ref;

  /**
   * Refernece to the reserve, or NULL (!).
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
 * Callback to analyze the /purses/$PID/merge response, just used to check if
 * the response code is acceptable.
 *
 * @param cls closure.
 * @param dr merge response details
 */
static void
merge_cb (void *cls,
          const struct TALER_EXCHANGE_AccountMergeResponse *dr)
{
  struct PurseMergeState *ds = cls;

  ds->dh = NULL;
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
merge_run (void *cls,
           const struct TALER_TESTING_Command *cmd,
           struct TALER_TESTING_Interpreter *is)
{
  struct PurseMergeState *ds = cls;
  const struct TALER_PurseContractPublicKeyP *purse_pub;
  const struct TALER_PurseMergePrivateKeyP *merge_priv;
  const json_t *ct;
  struct TALER_PrivateContractHashP h_contract_terms;
  uint32_t min_age;
  struct TALER_Amount value_after_fees;
  struct GNUNET_TIME_Timestamp purse_expiration;
  const struct TALER_TESTING_Command *ref;

  (void) cmd;
  ds->is = is;
  ref = TALER_TESTING_interpreter_lookup_command (ds->is,
                                                  ds->merge_ref);
  GNUNET_assert (NULL != ref);
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_merge_priv (ref,
                                          &merge_priv))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (ds->is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_purse_pub (ref,
                                         &purse_pub))
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
  if (GNUNET_OK !=
      TALER_JSON_contract_hash (ct,
                                &h_contract_terms))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (ds->is);
    return;
  }
  {
    struct GNUNET_JSON_Specification spec[] = {
      TALER_JSON_spec_amount_any ("amount",
                                  &value_after_fees),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_uint32 ("minimum_age",
                                 &min_age),
        NULL),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (ct,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (ds->is);
      return;
    }
  }

  // FIXME: how to get purse_expiration nicely!?!?
  // See create_with_deposit FIXME: from pay deadline?

  if (NULL == ds->reserve_ref)
  {
    GNUNET_CRYPTO_eddsa_key_create (&ds->reserve_priv.eddsa_priv);
  }
  else
  {
    const struct TALER_ReservePrivateKeyP *rp;

    ref = TALER_TESTING_interpreter_lookup_command (ds->is,
                                                    ds->merge_ref);
    GNUNET_assert (NULL != ref);
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_reserve_priv (ref,
                                              &rp))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (ds->is);
      return;
    }
    ds->reserve_priv = *rp;
  }
  GNUNET_CRYPTO_eddsa_key_get_public (&ds->reserve_priv.eddsa_priv,
                                      &ds->reserve_pub.eddsa_pub);
  ds->merge_timestamp = GNUNET_TIME_timestamp_get ();
  ds->dh = TALER_EXCHANGE_account_merge (
    is->exchange,
    NULL, /* no wad */
    &ds->reserve_priv,
    purse_pub,
    merge_priv,
    &h_contract_terms,
    min_age,
    &value_after_fees,
    purse_expiration,
    ds->merge_timestamp,
    &merge_cb,
    ds);
  if (NULL == ds->dh)
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not merge purse\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "merge" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct PurseMergeState`.
 * @param cmd the command which is being cleaned up.
 */
static void
merge_cleanup (void *cls,
               const struct TALER_TESTING_Command *cmd)
{
  struct PurseMergeState *ds = cls;

  if (NULL != ds->dh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ds->is->ip,
                cmd->label);
    TALER_EXCHANGE_account_merge_cancel (ds->dh);
    ds->dh = NULL;
  }
  GNUNET_free (ds);
}


/**
 * Offer internal data from a "merge" CMD, to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
merge_traits (void *cls,
              const void **ret,
              const char *trait,
              unsigned int index)
{
  struct PurseMergeState *ds = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_timestamp (0,
                                        &ds->merge_timestamp),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_purse_merge (
  const char *label,
  unsigned int expected_http_status,
  const char *merge_ref,
  const char *reserve_ref)
{
  struct PurseMergeState *ds;

  ds = GNUNET_new (struct PurseMergeState);
  ds->merge_ref = merge_ref;
  ds->reserve_ref = reserve_ref;
  ds->expected_response_code = expected_http_status;

  {
    struct TALER_TESTING_Command cmd = {
      .cls = ds,
      .label = label,
      .run = &merge_run,
      .cleanup = &merge_cleanup,
      .traits = &merge_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_purse_merge.c */
