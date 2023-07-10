/*
  This file is part of TALER
  (C) 2023 Taler Systems SA

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
 * @file testing/testing_api_cmd_run_fakebank.c
 * @brief Command to run fakebank in-process
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"

/**
 * State for a "run fakebank" CMD.
 */
struct RunFakebankState
{

  /**
   * Our interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Handle to the fakebank we are running.
   */
  struct TALER_FAKEBANK_Handle *fakebank;

  /**
   * URL of the bank.
   */
  char *bank_url;

  /**
   * Currency to use.
   */
  char *currency;

  /**
   * Data for access control.
   */
  struct TALER_BANK_AuthenticationData ba;

  /**
   * Port to use.
   */
  uint16_t port;
};


/**
 * Run the "get_exchange" command.
 *
 * @param cls closure.
 * @param cmd the command currently being executed.
 * @param is the interpreter state.
 */
static void
run_fakebank_run (void *cls,
                  const struct TALER_TESTING_Command *cmd,
                  struct TALER_TESTING_Interpreter *is)
{
  struct RunFakebankState *rfs = cls;

  (void) cmd;
  rfs->fakebank = TALER_FAKEBANK_start (rfs->port,
                                        rfs->currency);
  if (NULL == rfs->fakebank)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_interpreter_next (is);
}


/**
 * Cleanup the state.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
run_fakebank_cleanup (void *cls,
                      const struct TALER_TESTING_Command *cmd)
{
  struct RunFakebankState *rfs = cls;

  if (NULL != rfs->fakebank)
  {
    TALER_FAKEBANK_stop (rfs->fakebank);
    rfs->fakebank = NULL;
  }
  GNUNET_free (rfs->ba.wire_gateway_url);
  GNUNET_free (rfs->bank_url);
  GNUNET_free (rfs->currency);
  GNUNET_free (rfs);
}


/**
 * Offer internal data to a "run_fakebank" CMD state to other commands.
 *
 * @param cls closure
 * @param[out] ret result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
run_fakebank_traits (void *cls,
                     const void **ret,
                     const char *trait,
                     unsigned int index)
{
  struct RunFakebankState *rfs = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_bank_auth_data (&rfs->ba),
    TALER_TESTING_make_trait_fakebank (rfs->fakebank),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_run_fakebank (
  const char *label,
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  const char *exchange_account_section)
{
  struct RunFakebankState *rfs;
  unsigned long long fakebank_port;
  char *exchange_payto_uri;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
                                             "BANK",
                                             "HTTP_PORT",
                                             &fakebank_port))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "BANK",
                               "HTTP_PORT");
    GNUNET_assert (0);
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             exchange_account_section,
                                             "PAYTO_URI",
                                             &exchange_payto_uri))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               exchange_account_section,
                               "PAYTO_URI");
    GNUNET_assert (0);
  }
  rfs = GNUNET_new (struct RunFakebankState);
  rfs->port = (uint16_t) fakebank_port;
  GNUNET_asprintf (&rfs->bank_url,
                   "http://localhost:%u/",
                   (unsigned int) rfs->port);
  GNUNET_assert (GNUNET_OK ==
                 TALER_config_get_currency (cfg,
                                            &rfs->currency));
  {
    char *exchange_xtalerbank_account;

    exchange_xtalerbank_account
      = TALER_xtalerbank_account_from_payto (exchange_payto_uri);
    GNUNET_assert (NULL != exchange_xtalerbank_account);
    GNUNET_asprintf (&rfs->ba.wire_gateway_url,
                     "http://localhost:%u/%s/",
                     (unsigned int) fakebank_port,
                     exchange_xtalerbank_account);
    GNUNET_free (exchange_xtalerbank_account);
    GNUNET_free (exchange_payto_uri);
  }
  rfs->ba.method = TALER_BANK_AUTH_NONE;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = rfs,
      .label = label,
      .run = &run_fakebank_run,
      .cleanup = &run_fakebank_cleanup,
      .traits = &run_fakebank_traits,
      .name = "fakebank"
    };

    return cmd;
  }
}
