/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

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
 * @file testing/testing_api_cmd_post_kyc_start.c
 * @brief Implement the testing CMDs for a POST /kyc-start operation.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"

/**
 * State for a POST /kyc-start CMD.
 */
struct PostKycStartState
{

  /**
   * Command that did a GET on /kyc-info
   */
  const char *kyc_info_reference;

  /**
   * Index of the requirement to start.
   */
  unsigned int requirement_index;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Redirect URL returned by the request on success.
   */
  char *redirect_url;

  /**
   * Handle to the KYC start pending operation.
   */
  struct TALER_EXCHANGE_KycStartHandle *kwh;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;
};


/**
 * Handle response to the command.
 *
 * @param cls closure.
 * @param ks GET KYC status response details
 */
static void
post_kyc_start_cb (
  void *cls,
  const struct TALER_EXCHANGE_KycStartResponse *ks)
{
  struct PostKycStartState *kcg = cls;
  struct TALER_TESTING_Interpreter *is = kcg->is;

  kcg->kwh = NULL;
  if (kcg->expected_response_code != ks->hr.http_status)
  {
    TALER_TESTING_unexpected_status (is,
                                     ks->hr.http_status,
                                     kcg->expected_response_code);
    return;
  }
  switch (ks->hr.http_status)
  {
  case MHD_HTTP_OK:
    kcg->redirect_url
      = GNUNET_strdup (ks->details.ok.redirect_url);
    break;
  case MHD_HTTP_NO_CONTENT:
    break;
  default:
    GNUNET_break (0);
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
post_kyc_start_run (void *cls,
                    const struct TALER_TESTING_Command *cmd,
                    struct TALER_TESTING_Interpreter *is)
{
  struct PostKycStartState *kcg = cls;
  const struct TALER_TESTING_Command *res_cmd;
  const char *id;

  (void) cmd;
  kcg->is = is;
  res_cmd = TALER_TESTING_interpreter_lookup_command (
    kcg->is,
    kcg->kyc_info_reference);
  if (NULL == res_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (kcg->is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_kyc_id (
        res_cmd,
        kcg->requirement_index,
        &id))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (kcg->is);
    return;
  }
  if (NULL == id)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (kcg->is);
    return;
  }
  kcg->kwh = TALER_EXCHANGE_kyc_start (
    TALER_TESTING_interpreter_get_context (is),
    TALER_TESTING_get_exchange_url (is),
    id,
    &post_kyc_start_cb,
    kcg);
  GNUNET_assert (NULL != kcg->kwh);
}


/**
 * Cleanup the state from a "track transaction" CMD, and possibly
 * cancel a operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
post_kyc_start_cleanup (void *cls,
                        const struct TALER_TESTING_Command *cmd)
{
  struct PostKycStartState *kcg = cls;

  if (NULL != kcg->kwh)
  {
    TALER_TESTING_command_incomplete (kcg->is,
                                      cmd->label);
    TALER_EXCHANGE_kyc_start_cancel (kcg->kwh);
    kcg->kwh = NULL;
  }
  GNUNET_free (kcg->redirect_url);
  GNUNET_free (kcg);
}


/**
 * Offer internal data from a "check KYC" CMD.
 *
 * @param cls closure.
 * @param[out] ret result (could be anything).
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
post_kyc_start_traits (void *cls,
                       const void **ret,
                       const char *trait,
                       unsigned int index)
{
  struct PostKycStartState *kcg = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_kyc_url (kcg->redirect_url),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_post_kyc_start (
  const char *label,
  const char *kyc_info_reference,
  unsigned int requirement_index,
  unsigned int expected_response_code)
{
  struct PostKycStartState *kcg;

  kcg = GNUNET_new (struct PostKycStartState);
  kcg->kyc_info_reference = kyc_info_reference;
  kcg->requirement_index = requirement_index;
  kcg->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = kcg,
      .label = label,
      .run = &post_kyc_start_run,
      .cleanup = &post_kyc_start_cleanup,
      .traits = &post_kyc_start_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_post_kyc_start.c */
