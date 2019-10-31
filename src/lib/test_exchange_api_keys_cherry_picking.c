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
 * @file exchange-lib/test_exchange_api_keys_cherry_picking.c
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


#define NDKS_RIGHT_BEFORE_SERIALIZATION 46

/**
 * Add seconds.
 *
 * @param base absolute time to add seconds to.
 * @param relative number of seconds to add.
 * @return a new absolute time, modified according to @e relative.
 */
#define ADDSECS(base, secs) \
  GNUNET_TIME_absolute_add \
    (base, \
    GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_SECONDS, \
                                   secs))

/**
 * Subtract seconds.
 *
 * @param base absolute time to subtract seconds to.
 * @param secs relative number of _seconds_ to subtract.
 * @return a new absolute time, modified according to @e relative.
 */
#define SUBSECS(base, secs) \
  GNUNET_TIME_absolute_subtract \
    (base, \
    GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_SECONDS, \
                                   secs))
#define JAN1971 "1971-01-01"
#define JAN2030 "2030-01-01"

/**
 * Exchange base URL; mainly purpose is to make the compiler happy.
 */
static char *exchange_url;

/**
 * Auditor base URL; mainly purpose is to make the compiler happy.
 */
static char *auditor_url;


/**
 * Wrapper around the time parser.
 *
 * @param str human-readable time string.
 * @return the parsed time from @a str.
 */
static struct GNUNET_TIME_Absolute
TTH_parse_time (const char *str)
{
  struct GNUNET_TIME_Absolute ret;

  GNUNET_assert
    (GNUNET_OK == GNUNET_STRINGS_fancy_time_to_absolute (str,
                                                         &ret));
  return ret;
}


/**
 * Main function that will tell the interpreter what commands to
 * run.
 *
 * @param cls closure
 * @param is[in,out] interpreter state
 */
static void
run (void *cls,
     struct TALER_TESTING_Interpreter *is)
{
  struct TALER_TESTING_Command keys_serialization[] = {
    TALER_TESTING_cmd_serialize_keys
      ("serialize-keys"),
    TALER_TESTING_cmd_connect_with_state
      ("reconnect-with-state",
      "serialize-keys"),
    /**
     * Make sure we have the same keys situation as
     * it was before the serialization.
     */
    TALER_TESTING_cmd_check_keys_with_now
      ("check-keys-after-deserialization",
      4,
      NDKS_RIGHT_BEFORE_SERIALIZATION,
      /**
       * Pretend 5 seconds passed.
       */
      ADDSECS (TTH_parse_time (JAN2030),
               5)),
    /**
     * Use one of the deserialized keys.
     */
    TALER_TESTING_cmd_wire
      ("verify-/wire-with-serialized-keys",
      "x-taler-bank",
      NULL,
      MHD_HTTP_OK),
    TALER_TESTING_cmd_end (),
  };

  struct TALER_TESTING_Command ordinary_cherry_pick[] = {
    /**
     * 1 DK with 80s withdraw duration, lookahead_sign is 60s
     * => expect 1 DK.
     */
    TALER_TESTING_cmd_check_keys ("check-keys-1",
                                  1, /* generation */
                                  1),
    /**
     * The far-future now will cause "keyup" to start a fresh
     * key set.  The new KS will have only one key, because the
     * current lookahead_sign == 60 seconds and the key's withdraw
     * duration is 80 seconds.
     */TALER_TESTING_cmd_exec_keyup_with_now
      ("keyup-1",
      CONFIG_FILE,
      TTH_parse_time (JAN2030)),
    /**
    * Should return 1 new key, + the original one.  NOTE: the
    * original DK will never be 'cancelled' as for the current
    * libtalerexchange logic, so it must always be counted.
    */TALER_TESTING_cmd_check_keys_with_now
      ("check-keys-2",
      2,  /* generation */
      2,
      TTH_parse_time (JAN2030)),
    TALER_TESTING_cmd_exec_keyup_with_now
      ("keyup-3",
      CONFIG_FILE_EXTENDED_2,
      /* Taking care of not using a 'now' that equals the
       * last DK timestamp, otherwise it would get silently
       * overridden.  */
      ADDSECS (TTH_parse_time (JAN2030),
               10)),

    /**
     * Expected number of DK:
     *
     * 3500 (the lookahead_sign time frame, in seconds)
     * - 69 (how many seconds are covered by the latest DK)
     * ----
     * 3431
     * / 79 (how many seconds each DK will cover)
     * ----
     *   44 (rounded up)
     *  + 2 (old DKs already stored locally: 1 from the
     *       very initial setup, and 1 from the 'keyup-1' CMD)
     * ----
     *   46
     */TALER_TESTING_cmd_check_keys_with_now
      ("check-keys-3",
      3,
      NDKS_RIGHT_BEFORE_SERIALIZATION,
      TTH_parse_time (JAN2030)),

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
      char *const *argv)
{
  /* These environment variables get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-exchange-api-cherry-picking",
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


/* end of test_exchange_api_keys_cherry_picking.c */
