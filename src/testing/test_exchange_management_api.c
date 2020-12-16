/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file testing/test_exchange_management_api.c
 * @brief testcase to test exchange's HTTP /management/ API
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_exchange_service.h"
#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler_testing_lib.h"

/**
 * Configuration file we use.  One (big) configuration is used
 * for the various components for this test.
 */
#define CONFIG_FILE "test_exchange_api.conf"


/**
 * Exchange configuration data.
 */
static struct TALER_TESTING_ExchangeConfiguration ec;

/**
 * Bank configuration data.
 */
static struct TALER_TESTING_BankConfiguration bc;


/**
 * Main function that will tell the interpreter what commands to run.
 *
 * @param cls closure
 * @param is interpreter we use to run commands
 */
static void
run (void *cls,
     struct TALER_TESTING_Interpreter *is)
{
  struct TALER_TESTING_Command commands[] = {
#if FIXME_MIGRATION_DONE
    /* this currently fails, because the
       auditor is already added by the test setup logic */
    TALER_TESTING_cmd_auditor_del ("del-auditor-NOT-FOUND",
                                   MHD_HTTP_NOT_FOUND,
                                   false),
#endif
    TALER_TESTING_cmd_auditor_add ("add-auditor-BAD-SIG",
                                   MHD_HTTP_FORBIDDEN,
                                   true),
    TALER_TESTING_cmd_auditor_add ("add-auditor-OK",
                                   MHD_HTTP_NO_CONTENT,
                                   false),
    TALER_TESTING_cmd_auditor_add ("add-auditor-OK-idempotent",
                                   MHD_HTTP_NO_CONTENT,
                                   false),
    TALER_TESTING_cmd_auditor_del ("del-auditor-BAD-SIG",
                                   MHD_HTTP_FORBIDDEN,
                                   true),
    TALER_TESTING_cmd_auditor_del ("del-auditor-OK",
                                   MHD_HTTP_NO_CONTENT,
                                   false),
    TALER_TESTING_cmd_auditor_del ("del-auditor-IDEMPOTENT",
                                   MHD_HTTP_NO_CONTENT,
                                   false),
    TALER_TESTING_cmd_set_wire_fee ("set-fee",
                                    "foo-method",
                                    "EUR:1",
                                    "EUR:5",
                                    MHD_HTTP_NO_CONTENT,
                                    false),
    TALER_TESTING_cmd_set_wire_fee ("set-fee-conflicting",
                                    "foo-method",
                                    "EUR:1",
                                    "EUR:1",
                                    MHD_HTTP_CONFLICT,
                                    false),
    TALER_TESTING_cmd_set_wire_fee ("set-fee-bad-signature",
                                    "bar-method",
                                    "EUR:1",
                                    "EUR:1",
                                    MHD_HTTP_FORBIDDEN,
                                    true),
    TALER_TESTING_cmd_set_wire_fee ("set-fee-other-method",
                                    "bar-method",
                                    "EUR:1",
                                    "EUR:1",
                                    MHD_HTTP_NO_CONTENT,
                                    false),
    TALER_TESTING_cmd_set_wire_fee ("set-fee-idempotent",
                                    "bar-method",
                                    "EUR:1",
                                    "EUR:1",
                                    MHD_HTTP_NO_CONTENT,
                                    false),
    TALER_TESTING_cmd_wire_add ("add-wire-account",
                                "payto://x-taler-bank/localhost/42",
                                MHD_HTTP_NO_CONTENT,
                                false),
    TALER_TESTING_cmd_wire_add ("add-wire-account-idempotent",
                                "payto://x-taler-bank/localhost/42",
                                MHD_HTTP_NO_CONTENT,
                                false),
    TALER_TESTING_cmd_wire_add ("add-wire-account-another",
                                "payto://x-taler-bank/localhost/43",
                                MHD_HTTP_NO_CONTENT,
                                false),
    TALER_TESTING_cmd_wire_add ("add-wire-account-bad-signature",
                                "payto://x-taler-bank/localhost/44",
                                MHD_HTTP_FORBIDDEN,
                                true),
    TALER_TESTING_cmd_wire_del ("del-wire-account-not-found",
                                "payto://x-taler-bank/localhost/44",
                                MHD_HTTP_NOT_FOUND,
                                false),
    TALER_TESTING_cmd_wire_del ("del-wire-account-bad-signature",
                                "payto://x-taler-bank/localhost/43",
                                MHD_HTTP_FORBIDDEN,
                                true),
    TALER_TESTING_cmd_wire_del ("del-wire-account-ok",
                                "payto://x-taler-bank/localhost/43",
                                MHD_HTTP_NO_CONTENT,
                                false),
    TALER_TESTING_cmd_exec_offline_sign_keys ("download-future-keys",
                                              CONFIG_FILE),
    TALER_TESTING_cmd_check_keys_pull_all_keys ("refetch /keys",
                                                1),
    TALER_TESTING_cmd_end ()
  };

  TALER_TESTING_run_with_fakebank (is,
                                   commands,
                                   bc.exchange_auth.wire_gateway_url);
}


int
main (int argc,
      char *const *argv)
{
  /* These environment variables get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-exchange-management-api",
                    "INFO",
                    NULL);
  /* Check fakebank port is available and get config */
  if (GNUNET_OK !=
      TALER_TESTING_prepare_fakebank (CONFIG_FILE,
                                      "exchange-account-2",
                                      &bc))
    return 77;
  TALER_TESTING_cleanup_files (CONFIG_FILE);
  /* @helpers.  Create tables, ... Note: it
   * fetches the port number from config in order to see
   * if it's available. */
  switch (TALER_TESTING_prepare_exchange (CONFIG_FILE,
                                          GNUNET_YES, /* reset DB? */
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
                                           CONFIG_FILE))
      return 1;
    break;
  default:
    GNUNET_break (0);
    return 1;
  }
  return 0;
}


/* end of test_exchange_management_api.c */
