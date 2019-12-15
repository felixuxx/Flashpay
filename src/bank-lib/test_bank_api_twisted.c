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
 * @file exchange/test_bank_api_with_fakebank_twisted.c
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
#include <taler/taler_twister_testing_lib.h>
#include "taler_testing_bank_lib.h"
#include <taler/taler_twister_service.h>

/**
 * Configuration file we use.  One (big) configuration is used
 * for the various components for this test.
 */
#define CONFIG_FILE "bank_twisted.conf"

/**
 * True when the test runs against Fakebank.
 */
static int WITH_FAKEBANK;

/**
 * (real) Twister URL.  Used at startup time to check if it runs.
 */
static char *twister_url;

/**
 * URL of the twister where all the connections to the
 * bank that have to be proxied should be addressed to.
 */
#define TWISTED_BANK_URL twister_url

/**
 * URL of the bank.
 */
static char *bank_url;

/**
 * Twister process.
 */
static struct GNUNET_OS_Process *twisterd;

/**
 * Python bank process handle.
 */
static struct GNUNET_OS_Process *bankd;


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
  struct TALER_TESTING_Command commands[] = {
    /**
     * Can't use the "wait service" CMD here because the
     * fakebank runs inside the same process of the test.
     */
    TALER_TESTING_cmd_wait_service ("wait-service",
                                    TWISTED_BANK_URL),
    TALER_TESTING_cmd_bank_history ("history-0",
                                    TWISTED_BANK_URL,
                                    EXCHANGE_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_BOTH,
                                    GNUNET_NO,
                                    NULL,
                                    5),
    TALER_TESTING_cmd_end ()
  };

  if (GNUNET_YES == WITH_FAKEBANK)
    TALER_TESTING_run_with_fakebank (is,
                                     commands,
                                     bank_url);
  else
    TALER_TESTING_run (is,
                       commands);
}


/**
 * Kill, wait, and destroy convenience function.
 *
 * @param process process to purge.
 */
static void
purge_process (struct GNUNET_OS_Process *process)
{
  GNUNET_OS_process_kill (process, SIGINT);
  GNUNET_OS_process_wait (process);
  GNUNET_OS_process_destroy (process);
}


int
main (int argc,
      char *const *argv)
{
  unsigned int ret;

  /* These environment variables get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-bank-api-with-(fake)bank-twisted",
                    "DEBUG",
                    NULL);
  if (NULL == (twister_url = TALER_TESTING_prepare_twister
                               (CONFIG_FILE)))
  {
    GNUNET_break (0);
    return 77;
  }
  if (NULL == (twisterd = TALER_TESTING_run_twister (CONFIG_FILE)))
  {
    GNUNET_break (0);
    GNUNET_free (twister_url);
    return 77;
  }

  WITH_FAKEBANK = TALER_TESTING_has_in_name (argv[0],
                                             "_with_fakebank");

  if (GNUNET_YES == WITH_FAKEBANK)
  {
    TALER_LOG_DEBUG ("Running against the Fakebank.\n");
    if (NULL == (bank_url = TALER_TESTING_prepare_fakebank
                              (CONFIG_FILE,
                              "account-1")))
    {
      GNUNET_break (0);
      GNUNET_free (twister_url);
      return 77;
    }
  }
  else
  {
    TALER_LOG_DEBUG ("Running against the Pybank.\n");
    if (NULL == (bank_url = TALER_TESTING_prepare_bank
                              (CONFIG_FILE)))
    {
      GNUNET_break (0);
      GNUNET_free (twister_url);
      return 77;
    }

    if (NULL == (bankd = TALER_TESTING_run_bank (CONFIG_FILE,
                                                 bank_url)))
    {
      GNUNET_break (0);
      GNUNET_free (twister_url);
      GNUNET_free (bank_url);
      return 77;
    }
  }

  ret = TALER_TESTING_setup (&run,
                             NULL,
                             CONFIG_FILE,
                             NULL,
                             GNUNET_NO);
  purge_process (twisterd);

  if (GNUNET_NO == WITH_FAKEBANK)
  {
    GNUNET_OS_process_kill (bankd,
                            SIGKILL);
    GNUNET_OS_process_wait (bankd);
    GNUNET_OS_process_destroy (bankd);
  }

  GNUNET_free (twister_url);
  GNUNET_free (bank_url);

  if (GNUNET_OK == ret)
    return 0;

  return 1;
}


/* end of test_bank_api_twisted.c */
