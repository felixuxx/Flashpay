/*
  This file is part of TALER
  Copyright (C) 2014-2018 Taler Systems SA

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
 * @file testing/testing_api_cmd_revoke.c
 * @brief Implement the revoke test command.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"


/**
 * State for a "revoke" CMD.
 */
struct RevokeState
{
  /**
   * Expected HTTP status code.
   */
  unsigned int expected_response_code;

  /**
   * Command that offers a denomination to revoke.
   */
  const char *coin_reference;

  /**
   * The interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * The revoke process handle.
   */
  struct GNUNET_OS_Process *revoke_proc;

  /**
   * Configuration file name.
   */
  const char *config_filename;

  /**
   * Encoding of the denomination (to revoke) public key hash.
   */
  char *dhks;

};


/**
 * Cleanup the state.
 *
 * @param cls closure, must be a `struct RevokeState`.
 * @param cmd the command which is being cleaned up.
 */
static void
revoke_cleanup (void *cls,
                const struct TALER_TESTING_Command *cmd)
{
  struct RevokeState *rs = cls;

  if (NULL != rs->revoke_proc)
  {
    GNUNET_break (0 == GNUNET_OS_process_kill
                    (rs->revoke_proc, SIGKILL));
    GNUNET_OS_process_wait (rs->revoke_proc);
    GNUNET_OS_process_destroy (rs->revoke_proc);
    rs->revoke_proc = NULL;
  }
  GNUNET_free (rs->dhks);
  GNUNET_free (rs);
}


/**
 * Offer internal data from a "revoke" CMD to other CMDs.
 *
 * @param cls closure
 * @param[out] ret result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static int
revoke_traits (void *cls,
               const void **ret,
               const char *trait,
               unsigned int index)
{
  struct RevokeState *rs = cls;
  struct TALER_TESTING_Trait traits[] = {
    /* Needed by the handler which waits the proc'
     * death and calls the next command */
    TALER_TESTING_make_trait_process (0,
                                      &rs->revoke_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Run the "revoke" command.  The core of the function
 * is to call the "keyup" utility passing it the base32
 * encoding of the denomination to revoke.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
revoke_run (void *cls,
            const struct TALER_TESTING_Command *cmd,
            struct TALER_TESTING_Interpreter *is)
{
  struct RevokeState *rs = cls;
  const struct TALER_TESTING_Command *coin_cmd;
  const struct TALER_EXCHANGE_DenomPublicKey *denom_pub;

  rs->is = is;
  /* Get denom pub from trait */
  coin_cmd = TALER_TESTING_interpreter_lookup_command (is,
                                                       rs->coin_reference);

  if (NULL == coin_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_denom_pub (coin_cmd,
                                                    0,
                                                    &denom_pub));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Trying to revoke denom '%s..'\n",
              TALER_B2S (&denom_pub->h_key));

  rs->dhks = GNUNET_STRINGS_data_to_string_alloc (
    &denom_pub->h_key,
    sizeof (struct GNUNET_HashCode));

  rs->revoke_proc = GNUNET_OS_start_process (GNUNET_NO,
                                             GNUNET_OS_INHERIT_STD_ALL,
                                             NULL, NULL, NULL,
                                             "taler-exchange-keyup",
                                             "taler-exchange-keyup",
                                             "-c", rs->config_filename,
                                             "-r", rs->dhks,
                                             NULL);

  if (NULL == rs->revoke_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Revoke is ongoing..\n");

  is->reload_keys = GNUNET_OK;
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Make a "revoke" command.
 *
 * @param label the command label.
 * @param expected_response_code expected HTTP status code.
 * @param coin_reference reference to a CMD that will offer the
 *        denomination to revoke.
 * @param config_filename configuration file name.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_revoke (const char *label,
                          unsigned int expected_response_code,
                          const char *coin_reference,
                          const char *config_filename)
{

  struct RevokeState *rs;

  rs = GNUNET_new (struct RevokeState);
  rs->expected_response_code = expected_response_code;
  rs->coin_reference = coin_reference;
  rs->config_filename = config_filename;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = rs,
      .label = label,
      .run = &revoke_run,
      .cleanup = &revoke_cleanup,
      .traits = &revoke_traits
    };

    return cmd;
  }
}
