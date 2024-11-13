/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

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
 * @file testing/testing_api_cmd_bank_account_token.c
 * @brief implementation of a bank /account/$ACC/token command
 * @author Christian Grothoff
 */
#include "platform.h"
#include "backoff.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_bank_service.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"

/**
 * State for a "bank transfer" CMD.
 */
struct AccountTokenState
{

  /**
   * Name of the account.
   */
  const char *account_name;

  /**
   * Scope for the requested token.
   */
  enum TALER_BANK_TokenScope scope;

  /**
   * Is the token refreshable?
   */
  bool refreshable;

  /**
   * How long should the token be valid.
   */
  struct GNUNET_TIME_Relative duration;

  /**
   * The access token, set on success.
   */
  char *access_token;

  /**
   * Data to use for authentication of the request.
   */
  struct TALER_BANK_AuthenticationData auth;

  /**
   * Handle to the pending request at the bank.
   */
  struct TALER_BANK_AccountTokenHandle *ath;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Expected HTTP status code.
   */
  unsigned int expected_http_status;
};


/**
 * This callback will process the bank response to the wire
 * transfer.  It just checks whether the HTTP response code is
 * acceptable.
 *
 * @param cls closure with the interpreter state
 * @param atr response details
 */
static void
token_result_cb (void *cls,
                 const struct TALER_BANK_AccountTokenResponse *atr)
{
  struct AccountTokenState *fts = cls;
  struct TALER_TESTING_Interpreter *is = fts->is;

  fts->ath = NULL;
  if (atr->http_status != fts->expected_http_status)
  {
    TALER_TESTING_unexpected_status (is,
                                     atr->http_status,
                                     fts->expected_http_status);
    return;
  }
  switch (atr->http_status)
  {
  case MHD_HTTP_OK:
    fts->access_token
      = GNUNET_strdup (atr->details.ok.access_token);
    break;
  default:
    break;
  }
  TALER_TESTING_interpreter_next (is);
}


static void
account_token_run (
  void *cls,
  const struct TALER_TESTING_Command *cmd,
  struct TALER_TESTING_Interpreter *is)
{
  struct AccountTokenState *fts = cls;

  (void) cmd;
  fts->is = is;
  fts->ath
    = TALER_BANK_account_token (
        TALER_TESTING_interpreter_get_context (is),
        &fts->auth,
        fts->account_name,
        fts->scope,
        fts->refreshable,
        NULL /* description */,
        fts->duration,
        &token_result_cb,
        fts);
  if (NULL == fts->ath)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "/admin/add-incoming" CMD, and possibly
 * cancel a pending operation thereof.
 *
 * @param cls closure
 * @param cmd current CMD being cleaned up.
 */
static void
account_token_cleanup (
  void *cls,
  const struct TALER_TESTING_Command *cmd)
{
  struct AccountTokenState *fts = cls;

  if (NULL != fts->ath)
  {
    TALER_TESTING_command_incomplete (fts->is,
                                      cmd->label);
    TALER_BANK_account_token_cancel (fts->ath);
    fts->ath = NULL;
  }
  GNUNET_free (fts->access_token);
  GNUNET_free (fts);
}


/**
 * Offer internal data from a "/admin/add-incoming" CMD to other
 * commands.
 *
 * @param cls closure.
 * @param[out] ret result
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
account_token_traits (void *cls,
                      const void **ret,
                      const char *trait,
                      unsigned int index)
{
  struct AccountTokenState *fts = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_access_token (fts->access_token),
    TALER_TESTING_trait_end ()
  };

  if (MHD_HTTP_OK !=
      fts->expected_http_status)
    return GNUNET_NO; /* requests that failed generate no history */

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_account_token (
  const char *label,
  const struct TALER_BANK_AuthenticationData *auth,
  const char *account_name,
  enum TALER_BANK_TokenScope scope,
  bool refreshable,
  struct GNUNET_TIME_Relative duration,
  unsigned int expected_http_status)
{
  struct AccountTokenState *fts;

  fts = GNUNET_new (struct AccountTokenState);
  fts->account_name = account_name;
  fts->scope = scope;
  fts->refreshable = refreshable;
  fts->duration = duration;
  fts->auth = *auth;
  fts->expected_http_status = expected_http_status;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = fts,
      .label = label,
      .run = &account_token_run,
      .cleanup = &account_token_cleanup,
      .traits = &account_token_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_bank_account_token.c */
