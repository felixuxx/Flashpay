/*
  This file is part of TALER
  Copyright (C) 2016-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/test_bank_api.c
 * @brief testcase to test bank's HTTP API
 *        interface against the fakebank
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_bank_service.h"
#include "taler_exchange_service.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include <microhttpd.h>
#include "taler_testing_lib.h"

#define CONFIG_FILE_FAKEBANK "test_bank_api_fakebank.conf"

#define CONFIG_FILE_NEXUS "test_bank_api_nexus.conf"


/**
 * Configuration file.  It changes based on
 * whether Nexus or Fakebank are used.
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
 * Main function that will tell the interpreter what commands to
 * run.
 *
 * @param cls closure
 */
static void
run (void *cls,
     struct TALER_TESTING_Interpreter *is)
{
  struct TALER_WireTransferIdentifierRawP wtid;
  const char *ssoptions;

  (void) cls;
  switch (bs)
  {
  case TALER_TESTING_BS_FAKEBANK:
    ssoptions = "-f";
    break;
  case TALER_TESTING_BS_IBAN:
    ssoptions = "-ns";
    break;
  }
  memset (&wtid,
          42,
          sizeof (wtid));

  {
    struct TALER_TESTING_Command commands[] = {
      TALER_TESTING_cmd_system_start ("start-taler",
                                      cfgfile,
                                      ssoptions,
                                      NULL),
      TALER_TESTING_cmd_bank_credits ("history-0",
                                      &cred.ba,
                                      NULL,
                                      1),
      TALER_TESTING_cmd_admin_add_incoming ("credit-1",
                                            "EUR:5.01",
                                            &cred.ba,
                                            cred.user42_payto),
      /**
       * This CMD doesn't care about the HTTP response code; that's
       * because Fakebank and euFin behaves differently when a reserve
       * pub is duplicate.  Fakebank responds with 409, whereas euFin
       * with 200 but it bounces the payment back to the customer.
       */
      TALER_TESTING_cmd_admin_add_incoming_with_ref ("credit-1-fail",
                                                     "EUR:2.01",
                                                     &cred.ba,
                                                     cred.user42_payto,
                                                     "credit-1",
                                                     -1),
      TALER_TESTING_cmd_sleep ("Waiting 4s for 'credit-1' to settle",
                               4),
      /**
       * Check that the incoming payment with a duplicate
       * reserve public key didn't make it to the exchange.
       */
      TALER_TESTING_cmd_bank_credits ("history-1c",
                                      &cred.ba,
                                      NULL,
                                      5),
      TALER_TESTING_cmd_bank_debits ("history-1d",
                                     &cred.ba,
                                     NULL,
                                     5),
      TALER_TESTING_cmd_admin_add_incoming ("credit-2",
                                            "EUR:3.21",
                                            &cred.ba,
                                            cred.user42_payto),
      TALER_TESTING_cmd_transfer ("debit-1",
                                  "EUR:3.22",
                                  &cred.ba,
                                  cred.exchange_payto,
                                  cred.user42_payto,
                                  &wtid,
                                  "http://exchange.example.com/"),

      TALER_TESTING_cmd_sleep ("Waiting 5s for 'debit-1' to settle",
                               5),
      (bs == TALER_TESTING_BS_IBAN)
      ? TALER_TESTING_cmd_nexus_fetch_transactions (
        "fetch-transactions-at-nexus",
        "exchange", /* from taler-nexus-prepare */
        "x", /* from taler-nexus-prepare */
        "http://localhost:8082",
        "exchange-nexus") /* from taler-nexus-prepare */
      : TALER_TESTING_cmd_sleep ("nop",
                                 0),
      TALER_TESTING_cmd_bank_debits ("history-2b",
                                     &cred.ba,
                                     NULL,
                                     5),
      TALER_TESTING_cmd_end ()
    };

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Bank serves at `%s'\n",
                cred.ba.wire_gateway_url);
    TALER_TESTING_run (is,
                       commands);
  }
}


int
main (int argc,
      char *const *argv)
{
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
    bs = TALER_TESTING_BS_IBAN;
    cfgfile = CONFIG_FILE_NEXUS;
  }
  else
  {
    /* no bank service was specified.  */
    GNUNET_break (0);
    return 77;
  }
  return TALER_TESTING_main (argv,
                             "INFO",
                             cfgfile,
                             "exchange-account-2",
                             bs,
                             &cred,
                             &run,
                             NULL);
}


/* end of test_bank_api.c */
