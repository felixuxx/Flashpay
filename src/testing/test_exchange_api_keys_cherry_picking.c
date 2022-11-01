/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as pub
lished
  by the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/test_exchange_api_keys_cherry_picking.c
 * @brief testcase to test exchange's /keys cherry picking ability
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_testing_lib.h>
#include <microhttpd.h>
#include "taler_bank_service.h"
#include "taler_fakebank_lib.h"
#include "taler_testing_lib.h"


/**
 * Configuration file we use.  One (big) configuration is used
 * for the various components for this test.
 */
static char *config_file;

/**
 * Exchange configuration data.
 */
static struct TALER_TESTING_ExchangeConfiguration ec;


/**
 * Main function that will tell the interpreter what commands to run.
 *
 * @param cls closure
 * @param is[in,out] interpreter state
 */
static void
run (void *cls,
     struct TALER_TESTING_Interpreter *is)
{
  struct TALER_TESTING_Command commands[] = {
    TALER_TESTING_cmd_auditor_add ("add-auditor-OK",
                                   MHD_HTTP_NO_CONTENT,
                                   false),
    TALER_TESTING_cmd_wire_add ("add-wire-account",
                                "payto://x-taler-bank/localhost/2?receiver-name=2",
                                MHD_HTTP_NO_CONTENT,
                                false),
    TALER_TESTING_cmd_exec_offline_sign_fees ("offline-sign-fees",
                                              config_file,
                                              "EUR:0.01",
                                              "EUR:0.01",
                                              "EUR:0.01"),
    TALER_TESTING_cmd_exec_offline_sign_keys ("offline-sign-future-keys",
                                              config_file),
    TALER_TESTING_cmd_check_keys_pull_all_keys ("initial-/keys",
                                                1),
    TALER_TESTING_cmd_sleep ("sleep",
                             6 /* seconds */),
    TALER_TESTING_cmd_check_keys ("check-keys-1",
                                  2 /* generation */),
    TALER_TESTING_cmd_check_keys_with_last_denom ("check-keys-2",
                                                  3 /* generation */,
                                                  "check-keys-1"),
    TALER_TESTING_cmd_serialize_keys ("serialize-keys"),
    TALER_TESTING_cmd_connect_with_state ("reconnect-with-state",
                                          "serialize-keys"),
    /**
     * Make sure we have the same keys situation as
     * it was before the serialization.
     */
    TALER_TESTING_cmd_check_keys ("check-keys-after-deserialization",
                                  4),
    /**
     * Use one of the deserialized keys.
     */
    TALER_TESTING_cmd_wire ("wire-with-serialized-keys",
                            "x-taler-bank",
                            NULL,
                            MHD_HTTP_OK),
    TALER_TESTING_cmd_end ()
  };

  (void) cls;
  TALER_TESTING_run (is,
                     commands);
}


int
main (int argc,
      char *const *argv)
{
  char *cipher;

  (void) argc;
  /* These environment variables get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup (argv[0],
                    "INFO",
                    NULL);
  cipher = GNUNET_TESTING_get_testname_from_underscore (argv[0]);
  GNUNET_assert (NULL != cipher);
  GNUNET_asprintf (&config_file,
                   "test_exchange_api_keys_cherry_picking-%s.conf",
                   cipher);
  GNUNET_free (cipher);
  TALER_TESTING_cleanup_files (config_file);
  /* @helpers.  Run keyup, create tables, ... Note: it
   * fetches the port number from config in order to see
   * if it's available. */
  switch (TALER_TESTING_prepare_exchange (config_file,
                                          GNUNET_YES,
                                          &ec))
  {
  case GNUNET_SYSERR:
    GNUNET_break (0);
    return 1;
  case GNUNET_NO:
    return 77;
  case GNUNET_OK:
    if (GNUNET_OK !=
        /* Set up event loop and reschedule context, plus
         * start/stop the exchange.  It calls TALER_TESTING_setup
         * which creates the 'is' object.
         */
        TALER_TESTING_setup_with_exchange (&run,
                                           NULL,
                                           config_file))
      return 1;
    break;
  default:
    GNUNET_break (0);
    return 1;
  }
  return 0;
}


/* end of test_exchange_api_keys_cherry_picking.c */
