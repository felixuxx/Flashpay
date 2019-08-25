/*
  This file is part of TALER
  (C) 2015, 2016, 2017 GNUnet e.V. and Inria

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file wire/test_wire_plugin.c
 * @brief Tests for wire plugins
 * @author Christian Grothoff
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_wire_lib.h"
#include "taler_wire_plugin.h"
#include <gnunet/gnunet_json_lib.h>


/**
 * Definitions for a test with a plugin.
 */
struct TestBlock
{

  /**
   * Name of the plugin to test.
   */
  const char *plugin_name;

  /**
   * Amount to give to the rounding function.
   */
  const char *round_in;

  /**
   * Expected result from rounding.
   */
  const char *round_out;

  /**
   * Currency to give to the plugin.
   */
  const char *currency;
};


/**
 * List of plugins and (unsigned) JSON account definitions
 * to use for the tests.
 */
static struct TestBlock tests[] = {
  {
    .plugin_name = "ebics",
    .round_in = "EUR:0.123456",
    .round_out = "EUR:0.12",
    .currency = "EUR"
  },
#if HAVE_LIBCURL
  {
    .plugin_name = "taler_bank",
    .round_in = "KUDOS:0.123456",
    .round_out = "KUDOS:0.12",
    .currency = "KUDOS"
  },
#endif
  {
    NULL, NULL, NULL, NULL
  }
};


/**
 * Our configuration.
 */
static struct GNUNET_CONFIGURATION_Handle *cfg;


/**
 * Run the test.
 *
 * @param test details of the test
 * @param plugin plugin to test
 * @return #GNUNET_OK on success
 */
static int
run_test (const struct TestBlock *test,
          struct TALER_WIRE_Plugin *plugin)
{
  struct GNUNET_HashCode salt;
  struct TALER_Amount in;
  struct TALER_Amount expect;

  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                              &salt,
                              sizeof (salt));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (test->round_in,
                                         &in));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (test->round_out,
                                         &expect));
  if (GNUNET_OK !=
      plugin->amount_round (plugin->cls,
                            &in))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (0 != TALER_amount_cmp (&in, &expect))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_NO !=
      plugin->amount_round (plugin->cls,
                            &in))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  memset (&in, 0, sizeof (in));
  GNUNET_log_skip (GNUNET_ERROR_TYPE_ERROR, 1);
  if (GNUNET_SYSERR !=
      plugin->amount_round (plugin->cls,
                            &in))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


int
main (int argc,
      const char *const argv[])
{
  int ret;
  struct TALER_WIRE_Plugin *plugin;
  const struct TestBlock *test;

  GNUNET_log_setup ("test-wire-plugin",
                    "WARNING",
                    NULL);
  cfg = GNUNET_CONFIGURATION_create ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONFIGURATION_load (cfg,
                                            "test_wire_plugin.conf"));
  ret = GNUNET_OK;
  for (unsigned int i = 0; NULL != (test = &tests[i])->plugin_name; i++)
  {
    GNUNET_CONFIGURATION_set_value_string (cfg,
                                           "taler",
                                           "CURRENCY",
                                           test->currency);
    plugin = TALER_WIRE_plugin_load (cfg,
                                     test->plugin_name);
    if (NULL == plugin)
    {
      TALER_LOG_ERROR ("Could not load plugin `%s'\n",
                       test->plugin_name);
      return 77;
    }

    ret = run_test (test, plugin);
    TALER_WIRE_plugin_unload (plugin);
    if (GNUNET_OK != ret)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "%s FAILED\n",
                  test->plugin_name);
      break;
    }
    else
    {
      GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                  "%s PASS\n",
                  test->plugin_name);
    }
  }
  GNUNET_CONFIGURATION_destroy (cfg);
  if (GNUNET_OK != ret)
    return 1;
  return 0;
}
