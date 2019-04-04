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
 * Current time.
 */
struct GNUNET_TIME_Absolute now;

/**
 * Adds to the current time.  XXX, open question: shall  we
 * also _set_ the global current time after the faking?
 *
 * @param relative number of _seconds_ to add to the current time.
 * @return a new absolute time, modified according to @e relative.
 */
#define NOWPLUSSECS(secs) \
  GNUNET_TIME_absolute_add \
    (now, \
     GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_SECONDS, \
                                    secs))
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
    TALER_TESTING_cmd_serialize_keys ("serialize-keys"),
    TALER_TESTING_cmd_connect_with_state ("reconnect-with-state",
                                          "serialize-keys"),
    TALER_TESTING_cmd_wire ("verify-/wire-with-serialized-keys",
                            "x-taler-bank",
                            NULL,
                            MHD_HTTP_OK),
    /**
     * This loads a very big lookahead_sign (3500s).
     */
    TALER_TESTING_cmd_exec_keyup ("keyup-serialization",
                                  CONFIG_FILE_EXTENDED_2),
    TALER_TESTING_cmd_exec_auditor_sign
      ("auditor-sign-serialization",
       CONFIG_FILE_EXTENDED_2),

    TALER_TESTING_cmd_sleep ("sleep-serialization",
                             3),
    TALER_TESTING_cmd_signal ("reload-keys-serialization",
                              is->exchanged,
                              SIGUSR1),
    TALER_TESTING_cmd_sleep ("sleep-serialization",
                             3),
    #if 0

    FIXME: #5672
    
    The test below fails on different systems.  Infact, different
    systems can generate different "anchors" values for their denoms,
    therefore the fixed value required by the test below (45) is
    condemned to fail.

    However, this seems to happen only when very big values are
    used for the "lookahead_sign" value.  Here we use 3500 seconds,
    and the test breaks.

    A reasonable fix is to allow for some slack in the number of
    the expected keys.

    TALER_TESTING_cmd_check_keys ("check-freshest-keys",
                       /* At this point, /keys has been
                        * downloaded roughly 6 times, so by
                        * forcing 10 here we make sure we get
                        * all the new ones.  */
                                  10, 
                       /* We use a very high number here to make
                        * sure the "big" lookahead value got
                        * respected.  */
                                  45),
    #endif
    TALER_TESTING_cmd_wire ("verify-/wire-with-fresh-keys",
                            "x-taler-bank",
                            NULL,
                            MHD_HTTP_OK),

    TALER_TESTING_cmd_end (),

  };

  now = GNUNET_TIME_absolute_get ();
  struct TALER_TESTING_Command ordinary_cherry_pick[] = {

    /* Trigger keys reloading from disk.  */
    TALER_TESTING_cmd_signal ("signal-reaction-1",
                              is->exchanged,
                              SIGUSR1),
    /**
     * 1 DK with 80s withdraw duration.  Lookahead_sign is 60s.
     */
    TALER_TESTING_cmd_check_keys ("check-keys-1",
                                  1, /* generation */
                                  1),
    /**
     * We now set lookahead_sign to 90s, and expect a new DK
     * to be created.  The first one lives (= has withdraw_duration of)
     * only 80s.
     */
    TALER_TESTING_cmd_exec_keyup ("keyup-2",
                                  CONFIG_FILE_EXTENDED),

    TALER_TESTING_cmd_exec_auditor_sign ("sign-keys-1",
                                         CONFIG_FILE_EXTENDED),

    TALER_TESTING_cmd_signal ("trigger-keys-reload-1",
                              is->exchanged,
                              SIGUSR1),
    /**
     * Total 2 DKs.
     */
    TALER_TESTING_cmd_check_keys ("check-keys-2",
                                  2, /* generation */
                                  2),

    /* Nothing should happen now.  */
    TALER_TESTING_cmd_exec_keyup ("keyup-3",
                                  CONFIG_FILE_EXTENDED),
    TALER_TESTING_cmd_exec_auditor_sign ("sign-keys-2",
                                         CONFIG_FILE),
    TALER_TESTING_cmd_signal ("trigger-keys-reload-2",
                              is->exchanged,
                              SIGUSR1),

    /**
     * Make 30s time lapse (by passing the "now" argument to
     * "/keys").  First DK has 50s of remaining life
     * (duration_withdraw).  The second DK has ~60s of remaining
     * life, therefore two keys should be (still) returned.
     */
    TALER_TESTING_cmd_check_keys_with_now ("check-keys-3",
                                           3,
                                           2,
                                           NOWPLUSSECS (30)),
    TALER_TESTING_cmd_end ()
  };
  struct TALER_TESTING_Command commands[] = {

    TALER_TESTING_cmd_batch ("ordinary-cherry-pick",
                             ordinary_cherry_pick),
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
                    "DEBUG",
                    NULL);
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
