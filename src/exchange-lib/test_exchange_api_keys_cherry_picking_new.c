/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published
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
 * @file exchange-lib/test_exchange_api_keys_cherry_picking_new.c
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
#include <microhttpd.h>
#include "taler_bank_service.h"
#include "taler_fakebank_lib.h"
#include "taler_testing_lib.h"

/**
 * Configuration file we use.  One (big) configuration is used
 * for the various components for this test.
 */
#define CONFIG_FILE "test_exchange_api_keys_cherry_picking.conf"

/**
 * Used to increase the number of denomination keys.
 */
#define CONFIG_FILE_EXTENDED \
  "test_exchange_api_keys_cherry_picking_extended.conf"

/**
 * Used to increase the number of denomination keys.
 */
#define CONFIG_FILE_EXTENDED_2 \
  "test_exchange_api_keys_cherry_picking_extended_2.conf"

/**
 * Exchange base URL; mainly purpose is to make the compiler happy.
 */
static char *exchange_url;

/**
 * Auditor base URL; mainly purpose is to make the compiler happy.
 */
static char *auditor_url;


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

  struct TALER_TESTING_Command keys_serialization[] = {

    /**
     * Serialize keys, and disconnect from the exchange.
     */
    TALER_TESTING_cmd_serialize_keys ("serialize-keys"),

    /**
     * Reconnect to the exchange using the serialized keys.
     */
    TALER_TESTING_cmd_connect_with_state ("reconnect-with-state",
                                          "serialize-keys"),

    TALER_TESTING_cmd_wire ("verify-/wire-with-serialized-keys",
                            "x-taler-bank",
                            NULL,
                            MHD_HTTP_OK),

    TALER_TESTING_cmd_exec_keyup ("keyup-serialization",
                                  CONFIG_FILE_EXTENDED_2),

    TALER_TESTING_cmd_exec_auditor_sign ("auditor-sign-serialization",
                                         CONFIG_FILE_EXTENDED_2),
    TALER_TESTING_cmd_end ()
  };

  struct TALER_TESTING_Command commands[] = {
    /* Trigger keys reloading from disk.  */
    TALER_TESTING_cmd_signal ("signal-reaction-1",
                              is->exchanged,
                              SIGUSR1),

    TALER_TESTING_cmd_check_keys ("check-keys-1",
                                  1,
                                  4),
    /* sleep a bit */
    TALER_TESTING_cmd_sleep ("sleep",
                             10),

    /* 1st keyup happens at start-up */
    TALER_TESTING_cmd_exec_keyup ("keyup-2",
                                  CONFIG_FILE_EXTENDED),

    TALER_TESTING_cmd_exec_auditor_sign ("sign-keys-1",
                                         CONFIG_FILE_EXTENDED),

    /* Cause exchange to reload (new) keys */
    TALER_TESTING_cmd_signal ("trigger-keys-reload-1",
                              is->exchanged,
                              SIGUSR1),

    TALER_TESTING_cmd_check_keys ("check-keys-2",
                                  2,
                                  6),
    /* sleep a bit */
    TALER_TESTING_cmd_sleep ("sleep",
                             20),

    /* Do 2nd keyup */
    TALER_TESTING_cmd_exec_keyup ("keyup-3",
                                  CONFIG_FILE_EXTENDED),

    TALER_TESTING_cmd_exec_auditor_sign ("sign-keys-2",
                                         CONFIG_FILE),

    TALER_TESTING_cmd_signal ("trigger-keys-reload-2",
                              is->exchanged,
                              SIGUSR1),

    TALER_TESTING_cmd_check_keys ("check-keys-3",
                                  3,
                                  8),

    TALER_TESTING_cmd_batch ("keys-serialization",
                             keys_serialization),
    TALER_TESTING_cmd_end ()
  };

  TALER_TESTING_run (is,
		     commands);
}


int
main (int argc,
      char * const *argv)
{
  /* These environment variables get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-exchange-api-cherry-picking-new",
                    "DEBUG", NULL);
  TALER_TESTING_cleanup_files (CONFIG_FILE);
  /* @helpers.  Run keyup, create tables, ... Note: it
   * fetches the port number from config in order to see
   * if it's available. */
  switch (TALER_TESTING_prepare_exchange (CONFIG_FILE,
                                          &auditor_url,
					  &exchange_url))
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

/* end of test_exchange_api_keys_cherry_picking_new.c */
