/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * @file testing/test_bank_api_twisted.c
 * @author Marcello Stanisci
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler_bank_service.h"
#include "taler_fakebank_lib.h"
#include "taler_testing_lib.h"
#include "taler_twister_testing_lib.h"
#include <taler/taler_twister_service.h>

/**
 * Configuration file we use.  One (big) configuration is used
 * for the various components for this test.
 */
#define CONFIG_FILE_FAKEBANK "test_bank_api_fakebank_twisted.conf"

/**
 * Configuration file we use.
 */
static const char *cfgfile;

/**
 * Our credentials.
 */
static struct TALER_TESTING_Credentials cred;

/**
 * Which bank is the test running against?
 * Set up at runtime.
 */
static enum TALER_TESTING_BankSystem bs;

/**
 * (real) Twister URL.  Used at startup time to check if it runs.
 */
static char *twister_url;

/**
 * Twister process.
 */
static struct GNUNET_OS_Process *twisterd;


/**
 * Main function that will tell
 * the interpreter what commands to run.
 *
 * @param cls closure
 */
static void
run (void *cls,
     struct TALER_TESTING_Interpreter *is)
{
  struct TALER_WireTransferIdentifierRawP wtid;
  /* Authentication data to route our commands through twister. */
  struct TALER_BANK_AuthenticationData exchange_auth_twisted;
  const char *systype = NULL;

  (void) cls;
  memset (&wtid,
          0x5a,
          sizeof (wtid));
  GNUNET_memcpy (&exchange_auth_twisted,
                 &cred.ba,
                 sizeof (struct TALER_BANK_AuthenticationData));
  switch (bs)
  {
  case TALER_TESTING_BS_FAKEBANK:
    exchange_auth_twisted.wire_gateway_url
      = (char *) "http://localhost:8888/accounts/2/taler-wire-gateway/";
    systype = "-f";
    break;
  case TALER_TESTING_BS_IBAN:
    exchange_auth_twisted.wire_gateway_url
      = (char *) "http://localhost:8888/accounts/Exchange/taler-wire-gateway/";
    systype = "-b";
    break;
  }
  GNUNET_assert (NULL != systype);

  {
    struct TALER_TESTING_Command commands[] = {
      TALER_TESTING_cmd_system_start ("start-taler",
                                      cfgfile,
                                      systype,
                                      NULL),
      /* Test retrying transfer after failure. */
      TALER_TESTING_cmd_malform_response ("malform-transfer",
                                          cfgfile),
      TALER_TESTING_cmd_transfer_retry (
        TALER_TESTING_cmd_transfer ("debit-1",
                                    "EUR:3.22",
                                    &exchange_auth_twisted,
                                    cred.exchange_payto,
                                    cred.user42_payto,
                                    &wtid,
                                    "http://exchange.example.com/")),
      TALER_TESTING_cmd_end ()
    };

    TALER_TESTING_run (is,
                       commands);
  }
}


/**
 * Kill, wait, and destroy convenience function.
 *
 * @param[in] process process to purge.
 */
static void
purge_process (struct GNUNET_OS_Process *process)
{
  GNUNET_OS_process_kill (process,
                          SIGINT);
  GNUNET_OS_process_wait (process);
  GNUNET_OS_process_destroy (process);
}


int
main (int argc,
      char *const *argv)
{
  int ret;

  (void) argc;
  if (TALER_TESTING_has_in_name (argv[0],
                                 "_with_fakebank"))
  {
    bs = TALER_TESTING_BS_FAKEBANK;
    cfgfile = CONFIG_FILE_FAKEBANK;
  }
  else if (TALER_TESTING_has_in_name (argv[0],
                                      "_with_nexus"))
  {
    GNUNET_assert (0); /* FIXME: test with nexus not yet implemented */
    bs = TALER_TESTING_BS_IBAN;
    /* cfgfile = CONFIG_FILE_NEXUS; */
  }
  else
  {
    /* no bank service was specified.  */
    GNUNET_break (0);
    return 77;
  }

  /* FIXME: introduce commands for twister! */
  twister_url = TALER_TWISTER_prepare_twister (cfgfile);
  if (NULL == twister_url)
    return 77;
  twisterd = TALER_TWISTER_run_twister (cfgfile);
  if (NULL == twisterd)
    return 77;
  ret = TALER_TESTING_main (argv,
                            "INFO",
                            cfgfile,
                            "exchange-account-2",
                            bs,
                            &cred,
                            &run,
                            NULL);
  purge_process (twisterd);
  GNUNET_free (twister_url);
  return ret;
}


/* end of test_bank_api_twisted.c */
