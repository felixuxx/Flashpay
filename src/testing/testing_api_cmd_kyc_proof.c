/*
  This file is part of TALER
  Copyright (C) 2021 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3, or
  (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/

/**
 * @file testing/testing_api_cmd_kyc_proof.c
 * @brief Implement the testing CMDs for the /kyc-proof/ operation.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"

/**
 * State for a "track transaction" CMD.
 */
struct KycProofGetState
{

  /**
   * Command to get a reserve private key from.
   */
  const char *payment_target_reference;

  /**
   * Code to pass.
   */
  const char *code;

  /**
   * State to pass.
   */
  const char *state;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Set to the KYC REDIRECT *if* the exchange replied with
   * success (#MHD_HTTP_OK).
   */
  char *redirect_url;

  /**
   * Handle to the "track transaction" pending operation.
   */
  struct TALER_EXCHANGE_KycProofHandle *kph;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;
};


/**
 * Handle response to the command.
 *
 * @param cls closure.
 * @param kpr KYC proof response details
 */
static void
proof_kyc_cb (void *cls,
              const struct TALER_EXCHANGE_KycProofResponse *kpr)
{
  struct KycProofGetState *kcg = cls;
  struct TALER_TESTING_Interpreter *is = kcg->is;
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];

  kcg->kph = NULL;
  if (kcg->expected_response_code != kpr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u to command %s in %s:%u\n",
                kpr->http_status,
                cmd->label,
                __FILE__,
                __LINE__);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  switch (kpr->http_status)
  {
  case MHD_HTTP_SEE_OTHER:
    kcg->redirect_url = GNUNET_strdup (kpr->details.found.redirect_url);
    break;
  case MHD_HTTP_FORBIDDEN:
    break;
  case MHD_HTTP_BAD_GATEWAY:
    break;
  default:
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u to /kyc-proof\n",
                kpr->http_status);
    break;
  }
  TALER_TESTING_interpreter_next (kcg->is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
proof_kyc_run (void *cls,
               const struct TALER_TESTING_Command *cmd,
               struct TALER_TESTING_Interpreter *is)
{
  struct KycProofGetState *kps = cls;
  const struct TALER_TESTING_Command *res_cmd;
  const uint64_t *payment_target;

  (void) cmd;
  kps->is = is;
  res_cmd = TALER_TESTING_interpreter_lookup_command (kps->is,
                                                      kps->
                                                      payment_target_reference);
  if (NULL == res_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (kps->is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_payment_target_uuid (res_cmd,
                                                   &payment_target))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (kps->is);
    return;
  }
  kps->kph = TALER_EXCHANGE_kyc_proof (is->exchange,
                                       *payment_target,
                                       kps->code,
                                       kps->state,
                                       &proof_kyc_cb,
                                       kps);
  GNUNET_assert (NULL != kps->kph);
}


/**
 * Cleanup the state from a "track transaction" CMD, and possibly
 * cancel a operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
proof_kyc_cleanup (void *cls,
                   const struct TALER_TESTING_Command *cmd)
{
  struct KycProofGetState *kps = cls;

  if (NULL != kps->kph)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                kps->is->ip,
                cmd->label);
    TALER_EXCHANGE_kyc_proof_cancel (kps->kph);
    kps->kph = NULL;
  }
  GNUNET_free (kps->redirect_url);
  GNUNET_free (kps);
}


/**
 * Offer internal data from a "proof KYC" CMD.
 *
 * @param cls closure.
 * @param[out] ret result (could be anything).
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
proof_kyc_traits (void *cls,
                  const void **ret,
                  const char *trait,
                  unsigned int index)
{
  struct KycProofGetState *kps = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_web_url (
      (const char **) &kps->redirect_url),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_proof_kyc (const char *label,
                             const char *payment_target_reference,
                             const char *code,
                             const char *state,
                             unsigned int expected_response_code)
{
  struct KycProofGetState *kps;

  kps = GNUNET_new (struct KycProofGetState);
  kps->code = code;
  kps->state = state;
  kps->payment_target_reference = payment_target_reference;
  kps->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = kps,
      .label = label,
      .run = &proof_kyc_run,
      .cleanup = &proof_kyc_cleanup,
      .traits = &proof_kyc_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_kyc_proof.c */
