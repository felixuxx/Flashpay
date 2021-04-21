/*
  This file is part of TALER
  (C) 2021 Taler Systems SA

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
 * @file testing/testing_api_cmd_change_auth.c
 * @brief command(s) to change CURL context authorization header
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"


/**
 * State for a "authchange" CMD.
 */
struct AuthchangeState
{

  /**
   * What is the new authorization token to send?
   */
  const char *auth_token;
};


/**
 * No traits to offer, just provide a stub to be called when
 * some CMDs iterates through the list of all the commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the trait to return.
 * @return #GNUNET_OK on success.
 */
static int
authchange_traits (void *cls,
                   const void **ret,
                   const char *trait,
                   unsigned int index)
{
  (void) cls;
  (void) ret;
  (void) trait;
  (void) index;
  return GNUNET_NO;
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
authchange_run (void *cls,
                const struct TALER_TESTING_Command *cmd,
                struct TALER_TESTING_Interpreter *is)
{
  struct AuthchangeState *ss = cls;

  if (NULL != is->ctx)
  {
    GNUNET_CURL_fini (is->ctx);
    is->ctx = NULL;
  }
  if (NULL != is->rc)
  {
    GNUNET_CURL_gnunet_rc_destroy (is->rc);
    is->rc = NULL;
  }
  is->ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                              &is->rc);
  GNUNET_CURL_enable_async_scope_header (is->ctx,
                                         "Taler-Correlation-Id");
  GNUNET_assert (NULL != is->ctx);
  is->rc = GNUNET_CURL_gnunet_rc_create (is->ctx);
  if (NULL != ss->auth_token)
  {
    char *authorization;

    GNUNET_asprintf (&authorization,
                     "%s: %s",
                     MHD_HTTP_HEADER_AUTHORIZATION,
                     ss->auth_token);
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CURL_append_header (is->ctx,
                                              authorization));
    GNUNET_free (authorization);
  }
  TALER_TESTING_interpreter_next (is);
}


/**
 * Cleanup the state from a "authchange" CMD.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
authchange_cleanup (void *cls,
                    const struct TALER_TESTING_Command *cmd)
{
  struct AuthchangeState *ss = cls;

  (void) cmd;
  GNUNET_free (ss);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_set_authorization (const char *label,
                                     const char *auth_token)
{
  struct AuthchangeState *ss;

  ss = GNUNET_new (struct AuthchangeState);
  ss->auth_token = auth_token;

  {
    struct TALER_TESTING_Command cmd = {
      .cls = ss,
      .label = label,
      .run = &authchange_run,
      .cleanup = &authchange_cleanup,
      .traits = &authchange_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_change_auth.c  */
