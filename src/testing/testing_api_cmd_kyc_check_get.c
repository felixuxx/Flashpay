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
 * @file testing/testing_api_cmd_kyc_check_get.c
 * @brief Implement the testing CMDs for the /kyc_check/ GET operations.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"

/**
 * State for a "track transaction" CMD.
 */
struct KycCheckGetState
{

  /**
   * Command to get a reserve private key from.
   */
  const char *payment_target_reference;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Set to the KYC URL *if* the exchange replied with
   * a request for KYC (#MHD_HTTP_ACCEPTED).
   */
  char *kyc_url;

  /**
   * Handle to the "track transaction" pending operation.
   */
  struct TALER_EXCHANGE_KycCheckHandle *kwh;

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
check_kyc_cb (void *cls,
              const struct TALER_EXCHANGE_KycStatus *ks)
{
  struct KycCheckGetState *kcg = cls;
  struct TALER_TESTING_Interpreter *is = kcg->is;
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];

  kcg->kwh = NULL;
  if (kcg->expected_response_code != ks->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d to command %s in %s:%u\n",
                ks->http_status,
                (int) ks->ec,
                cmd->label,
                __FILE__,
                __LINE__);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  switch (ks->http_status)
  {
  case MHD_HTTP_OK:
    break;
  case MHD_HTTP_ACCEPTED:
    kcg->kyc_url = GNUNET_strdup (ks->details.kyc_url);
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
check_kyc_run (void *cls,
               const struct TALER_TESTING_Command *cmd,
               struct TALER_TESTING_Interpreter *is)
{
  struct KycCheckGetState *kcg = cls;
  const struct TALER_TESTING_Command *res_cmd;
  const char **payto_uri;
  const uint64_t *payment_target;
  struct TALER_PaytoHashP h_payto;

  (void) cmd;
  kcg->is = is;
  res_cmd = TALER_TESTING_interpreter_lookup_command (kcg->is,
                                                      kcg->
                                                      payment_target_reference);
  if (NULL == res_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (kcg->is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_payto_uri (res_cmd,
                                         &payto_uri))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (kcg->is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_legitimization_uuid (res_cmd,
                                                   &payment_target))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (kcg->is);
    return;
  }
  if ( (NULL == *payto_uri) ||
       (0 == *payment_target) )
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (kcg->is);
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Running KYC check for payto URI: %s\n",
              *payto_uri);
  TALER_payto_hash (*payto_uri,
                    &h_payto);
  kcg->kwh = TALER_EXCHANGE_kyc_check (is->exchange,
                                       *payment_target,
                                       &h_payto,
                                       TALER_KYCLOGIC_KYC_UT_INDIVIDUAL,
                                       GNUNET_TIME_UNIT_SECONDS,
                                       &check_kyc_cb,
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
check_kyc_cleanup (void *cls,
                   const struct TALER_TESTING_Command *cmd)
{
  struct KycCheckGetState *kcg = cls;

  if (NULL != kcg->kwh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                kcg->is->ip,
                cmd->label);
    TALER_EXCHANGE_kyc_check_cancel (kcg->kwh);
    kcg->kwh = NULL;
  }
  GNUNET_free (kcg->kyc_url);
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
check_kyc_traits (void *cls,
                  const void **ret,
                  const char *trait,
                  unsigned int index)
{
  struct KycCheckGetState *kcg = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_kyc_url (
      (const char **) &kcg->kyc_url),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_check_kyc_get (const char *label,
                                 const char *payment_target_reference,
                                 unsigned int expected_response_code)
{
  struct KycCheckGetState *kcg;

  kcg = GNUNET_new (struct KycCheckGetState);
  kcg->payment_target_reference = payment_target_reference;
  kcg->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = kcg,
      .label = label,
      .run = &check_kyc_run,
      .cleanup = &check_kyc_cleanup,
      .traits = &check_kyc_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_kyc_check_get.c */
