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
 * @file exchange/test_exchange_api_twister.c
 * @brief testcase to test exchange's HTTP API interface
 * @author Marcello Stanisci
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */

#include "platform.h"
#include <taler/taler_util.h>
#include <taler/taler_signatures.h>
#include <taler/taler_exchange_service.h>
#include <taler/taler_json_lib.h>
#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include <taler/taler_bank_service.h>
#include <taler/taler_fakebank_lib.h>
#include <taler/taler_testing_lib.h>
#include <taler/taler_twister_testing_lib.h>
#include <taler/taler_testing_bank_lib.h>
#include <taler/taler_twister_service.h>

/**
 * Configuration file we use.  One (big) configuration is used
 * for the various components for this test.
 */
#define CONFIG_FILE "bank_twisted.conf"

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
 * Bank process.
 */
static struct GNUNET_OS_Process *bankd;

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

  struct TALER_TESTING_Command commands[] = {

    TALER_TESTING_cmd_bank_history ("history-0",
                                    twister_url,
                                    EXCHANGE_ACCOUNT_NUMBER,
                                    TALER_BANK_DIRECTION_BOTH,
                                    NULL,
                                    5),
    /**
     * End the suite.  Fixme: better to have a label for this
     * too, as it shows a "(null)" token on logs.
     */
    TALER_TESTING_cmd_end ()
  };

  TALER_TESTING_run (is, commands);
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
      char * const *argv)
{
  unsigned int ret;
  /* These environment variables get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-bank-api-twisted",
                    "DEBUG", NULL);

  if (NULL == (bank_url = TALER_TESTING_prepare_bank
      (CONFIG_FILE)))
    return 77;

  if (NULL == (bankd = TALER_TESTING_run_bank
      (CONFIG_FILE, bank_url)))
    return 77;

  if (NULL == (twister_url = TALER_TESTING_prepare_twister
      (CONFIG_FILE)))
    return 77;
  
  if (NULL == (twisterd = TALER_TESTING_run_twister (CONFIG_FILE)))
    return 77;

  ret = TALER_TESTING_setup (&run,
                             NULL,
                             CONFIG_FILE,
                             NULL);
  purge_process (twisterd);
  purge_process (bankd);
  GNUNET_free (twister_url);
  GNUNET_free (bank_url);

  if (GNUNET_OK == ret)
    return 0;

  return 1;
}

/* end of test_bank_api_twisted.c */
