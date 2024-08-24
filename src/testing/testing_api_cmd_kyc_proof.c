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
   * Logic section name to pass to `/kyc-proof/` handler.
   */
  const char *logic;

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

  kcg->kph = NULL;
  if (kcg->expected_response_code != kpr->hr.http_status)
  {
    TALER_TESTING_unexpected_status (is,
                                     kpr->hr.http_status,
                                     kcg->expected_response_code);
    return;
  }
  switch (kpr->hr.http_status)
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
                kpr->hr.http_status);
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
  const struct TALER_PaytoHashP *h_payto;
  char *uargs;
  const char *exchange_url;

  (void) cmd;
  kps->is = is;
  exchange_url = TALER_TESTING_get_exchange_url (is);
  if (NULL == exchange_url)
  {
    GNUNET_break (0);
    return;
  }
  res_cmd = TALER_TESTING_interpreter_lookup_command (
    kps->is,
    kps->payment_target_reference);
  if (NULL == res_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (kps->is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_h_payto (res_cmd,
                                       &h_payto))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (kps->is);
    return;
  }
  if (NULL == kps->code)
    uargs = NULL;
  else
    GNUNET_asprintf (&uargs,
                     "&code=%s",
                     kps->code);
  kps->kph = TALER_EXCHANGE_kyc_proof (
    TALER_TESTING_interpreter_get_context (is),
    exchange_url,
    h_payto,
    kps->logic,
    uargs,
    &proof_kyc_cb,
    kps);
  GNUNET_free (uargs);
  GNUNET_assert (NULL != kps->kph);
}


/**
 * Cleanup the state from a "kyc proof" CMD, and possibly
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
    TALER_TESTING_command_incomplete (kps->is,
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
    TALER_TESTING_make_trait_web_url (kps->redirect_url),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_proof_kyc_oauth2 (
  const char *label,
  const char *payment_target_reference,
  const char *logic_section,
  const char *code,
  unsigned int expected_response_code)
{
  struct KycProofGetState *kps;

  kps = GNUNET_new (struct KycProofGetState);
  kps->code = code;
  kps->logic = logic_section;
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
