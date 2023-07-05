/*
  This file is part of TALER
  Copyright (C) 2020-2023 Taler Systems SA

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
#include <gnunet/gnunet_testing_lib.h>
#include <microhttpd.h>
#include "taler_testing_lib.h"

/**
 * Configuration file we use.  One (big) configuration is used
 * for the various components for this test.
 */
static char *config_file;

/**
 * Our credentials.
 */
static struct TALER_TESTING_Credentials cred;


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
    TALER_TESTING_cmd_system_start ("start-taler",
                                    config_file,
                                    "-u", "exchange-account-2",
                                    "-ae",
                                    NULL),
    TALER_TESTING_cmd_get_exchange ("get-exchange",
                                    cred.cfg,
                                    NULL,
                                    true,
                                    true),
    TALER_TESTING_cmd_get_auditor ("get-auditor",
                                   cred.cfg,
                                   true),
    TALER_TESTING_cmd_auditor_del ("del-auditor-FROM-SETUP",
                                   MHD_HTTP_NO_CONTENT,
                                   false),
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
                                "payto://x-taler-bank/localhost/42?receiver-name=42",
                                MHD_HTTP_NO_CONTENT,
                                false),
    TALER_TESTING_cmd_wire_add ("add-wire-account-idempotent",
                                "payto://x-taler-bank/localhost/42?receiver-name=42",
                                MHD_HTTP_NO_CONTENT,
                                false),
    TALER_TESTING_cmd_wire_add ("add-wire-account-another",
                                "payto://x-taler-bank/localhost/43?receiver-name=43",
                                MHD_HTTP_NO_CONTENT,
                                false),
    TALER_TESTING_cmd_wire_add ("add-wire-account-bad-signature",
                                "payto://x-taler-bank/localhost/44?receiver-name=44",
                                MHD_HTTP_FORBIDDEN,
                                true),
    TALER_TESTING_cmd_wire_del ("del-wire-account-not-found",
                                "payto://x-taler-bank/localhost/44?receiver-name=44",
                                MHD_HTTP_NOT_FOUND,
                                false),
    TALER_TESTING_cmd_wire_del ("del-wire-account-bad-signature",
                                "payto://x-taler-bank/localhost/43?receiver-name=43",
                                MHD_HTTP_FORBIDDEN,
                                true),
    TALER_TESTING_cmd_wire_del ("del-wire-account-ok",
                                "payto://x-taler-bank/localhost/43?receiver-name=43",
                                MHD_HTTP_NO_CONTENT,
                                false),
    TALER_TESTING_cmd_exec_offline_sign_keys ("download-future-keys",
                                              config_file),
    TALER_TESTING_cmd_get_exchange ("get-exchange-1",
                                    cred.cfg,
                                    "get-exchange",
                                    true,
                                    true),
    TALER_TESTING_cmd_get_exchange ("get-exchange-2",
                                    cred.cfg,
                                    NULL,
                                    true,
                                    true),
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
  (void) argc;
  {
    char *cipher;

    cipher = GNUNET_TESTING_get_testname_from_underscore (argv[0]);
    GNUNET_assert (NULL != cipher);
    GNUNET_asprintf (&config_file,
                     "test_exchange_api-%s.conf",
                     cipher);
    GNUNET_free (cipher);
  }
  return TALER_TESTING_main (argv,
                             "INFO",
                             config_file,
                             "exchange-account-2",
                             TALER_TESTING_BS_FAKEBANK,
                             &cred,
                             &run,
                             NULL);
}


/* end of test_exchange_management_api.c */
