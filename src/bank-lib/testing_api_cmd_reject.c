/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

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
 * @file bank-lib/testing_api_cmd_reject.c
 * @brief command to check the /reject API from the bank.
 * @author Marcello Stanisci
 */

#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_testing_lib.h"
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_fakebank_lib.h"


/**
 * State for a "reject" CMD.
 */
struct RejectState
{

  /**
   * Handle of a ongoing "reject" operation.
   */
  struct TALER_BANK_RejectHandle *rh;

  /**
   * Reference to any command that can offer a wire
   * transfer "row id" and its credit account so as
   * to give input data to the "reject" operation.
   */
  const char *deposit_reference;

  /**
   * Base URL of the bank implementing the "reject"
   * operation.
   */
  const char *bank_url;
};

/**
 * Check that the response code from the "reject" opetation
 * is acceptable, namely it equals "204 No Content".
 *
 * @param cls closure.
 * @param http_status HTTP response code.
 * @param ec taler-specific error code.
 */
static void
reject_cb (void *cls,
           unsigned int http_status,
           enum TALER_ErrorCode ec)
{
  struct TALER_TESTING_Interpreter *is = cls;
  struct RejectState *rs = is->commands[is->ip].cls;

  rs->rh = NULL;
  if (MHD_HTTP_NO_CONTENT != http_status)
  {
    GNUNET_break (0);
    fprintf (stderr,
             "Unexpected response code %u:\n",
             http_status);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_interpreter_next (is);
}

/**
 * Cleanup the state of a "reject" CMD, and possibly
 * cancel a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command.
 */
static void
reject_cleanup
  (void *cls,
   const struct TALER_TESTING_Command *cmd)
{
  struct RejectState *rs = cls;

  if (NULL != rs->rh)
  {
    TALER_LOG_WARNING ("/reject did not complete\n");
    TALER_BANK_reject_cancel (rs->rh);
  }

  GNUNET_free (rs);
}

/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
reject_run (void *cls,
             const struct TALER_TESTING_Command *cmd,
             struct TALER_TESTING_Interpreter *is)
{
  struct RejectState *rs = cls;
  const struct TALER_TESTING_Command *deposit_cmd;
  const uint64_t *credit_account;
  const uint64_t *row_id;
  extern struct TALER_BANK_AuthenticationData AUTHS[];

  deposit_cmd = TALER_TESTING_interpreter_lookup_command
    (is, rs->deposit_reference);

  if (NULL == deposit_cmd)
    TALER_TESTING_FAIL (is);

  GNUNET_assert
    (GNUNET_OK == TALER_TESTING_GET_TRAIT_CREDIT_ACCOUNT
      (deposit_cmd, &credit_account));

  GNUNET_assert
    (GNUNET_OK == TALER_TESTING_GET_TRAIT_ROW_ID
      (deposit_cmd, &row_id));
  TALER_LOG_INFO ("Account %llu rejects deposit\n",
                  (unsigned long long) *credit_account);
  rs->rh = TALER_BANK_reject (is->ctx,
                              rs->bank_url,
                              &AUTHS[*credit_account -1],
                              *credit_account,
                              *row_id,
                              &reject_cb,
                              is);
  GNUNET_assert (NULL != rs->rh);
}


/**
 * Offer internal data from a "reject" CMD to other commands.
 *
 * @param cls closure.
 * @param ret[out] result.
 * @param trait name of the trait.
 * @param index index number of the trait to return.
 *
 * @return #GNUNET_OK on success.
 */
static int
reject_traits (void *cls,
               const void **ret,
               const char *trait,
               unsigned int index)
{
  struct RejectState *rs = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_rejected (0, rs->deposit_reference),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}

/**
 * Create a "reject" CMD.
 *
 * @param label command label.
 * @param bank_url base URL of the bank implementing the
 *        "reject" operation.
 * @param deposit_reference reference to a command that will
 *        provide a "row id" and credit (bank) account to craft
 *        the "reject" request.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_reject (const char *label,
                               const char *bank_url,
                               const char *deposit_reference)
{
  struct RejectState *rs;

  rs = GNUNET_new (struct RejectState);
  rs->bank_url = bank_url;
  rs->deposit_reference = deposit_reference;

  struct TALER_TESTING_Command cmd = {
    .cls = rs,
    .run = &reject_run,
    .cleanup = &reject_cleanup,
    .label = label,
    .traits = &reject_traits
  };

  return cmd;

}


/* end of testing_api_cmd_reject.c */
