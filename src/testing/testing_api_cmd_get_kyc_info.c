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
 * @file testing/testing_api_cmd_get_kyc_info.c
 * @brief Implement the testing CMDs for the GET /kyc_info operation.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"

/**
 * State for a GET kyc-info CMD.
 */
struct GetKycInfoState
{

  /**
   * Command to get the account access token from.
   */
  const char *kyc_check_reference;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Handle to the GET /kyc-info pending operation.
   */
  struct TALER_EXCHANGE_KycInfoHandle *kwh;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Array of IDs for possible KYC processes we could
   * start according to the response.
   */
  char **ids;

  /**
   * Length of the @e ids array.
   */
  unsigned int num_ids;
};


/**
 * Handle response to the command.
 *
 * @param cls closure.
 * @param kpci GET KYC status response details
 */
static void
kyc_info_cb (
  void *cls,
  const struct TALER_EXCHANGE_KycProcessClientInformation *kpci)
{
  struct GetKycInfoState *kcg = cls;
  struct TALER_TESTING_Interpreter *is = kcg->is;

  kcg->kwh = NULL;
  if (kcg->expected_response_code != kpci->hr.http_status)
  {
    TALER_TESTING_unexpected_status (
      is,
      kpci->hr.http_status,
      kcg->expected_response_code);
    return;
  }
  switch (kpci->hr.http_status)
  {
  case MHD_HTTP_OK:
    kcg->num_ids = kpci->details.ok.requirements_length;
    kcg->ids = GNUNET_new_array (kcg->num_ids,
                                 char *);
    for (unsigned int i = 0; i<kcg->num_ids; i++)
      kcg->ids[i] = GNUNET_strdup (
        kpci->details.ok.requirements[i].id);
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
get_kyc_info_run (void *cls,
                  const struct TALER_TESTING_Command *cmd,
                  struct TALER_TESTING_Interpreter *is)
{
  struct GetKycInfoState *kcg = cls;
  const struct TALER_TESTING_Command *res_cmd;
  const struct TALER_AccountAccessTokenP *token;

  (void) cmd;
  kcg->is = is;
  res_cmd = TALER_TESTING_interpreter_lookup_command (
    kcg->is,
    kcg->kyc_check_reference);
  if (NULL == res_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (kcg->is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_account_access_token (
        res_cmd,
        &token))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (kcg->is);
    return;
  }
  kcg->kwh = TALER_EXCHANGE_kyc_info (
    TALER_TESTING_interpreter_get_context (is),
    TALER_TESTING_get_exchange_url (is),
    token,
    NULL /* etag */,
    GNUNET_TIME_UNIT_ZERO,
    &kyc_info_cb,
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
get_kyc_info_cleanup (
  void *cls,
  const struct TALER_TESTING_Command *cmd)
{
  struct GetKycInfoState *kcg = cls;

  if (NULL != kcg->kwh)
  {
    TALER_TESTING_command_incomplete (kcg->is,
                                      cmd->label);
    TALER_EXCHANGE_kyc_info_cancel (kcg->kwh);
    kcg->kwh = NULL;
  }
  for (unsigned int i = 0; i<kcg->num_ids; i++)
    GNUNET_free (kcg->ids[i]);
  GNUNET_free (kcg->ids);
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
get_kyc_info_traits (void *cls,
                     const void **ret,
                     const char *trait,
                     unsigned int index)
{
  struct GetKycInfoState *kcg = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_kyc_id (index,
                                     kcg->ids[index]),
    TALER_TESTING_trait_end ()
  };

  if (index >= kcg->num_ids)
    return GNUNET_NO;
  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_get_kyc_info (
  const char *label,
  const char *kyc_check_reference,
  unsigned int expected_response_code)
{
  struct GetKycInfoState *kcg;

  kcg = GNUNET_new (struct GetKycInfoState);
  kcg->kyc_check_reference = kyc_check_reference;
  kcg->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = kcg,
      .label = label,
      .run = &get_kyc_info_run,
      .cleanup = &get_kyc_info_cleanup,
      .traits = &get_kyc_info_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_get_kyc_info.c */
