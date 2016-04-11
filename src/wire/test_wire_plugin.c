/*
  This file is part of TALER
  (C) 2015, 2016 GNUnet e.V. and Inria

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
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


/**
 * Definitions for a test with a plugin.
 */
struct TestBlock {

  /**
   * Name of the plugin to test.
   */
  const char *plugin_name;

  /**
   * JSON template expected by the plugin for an account definition.
   */
  const char *json_proto;

};


/**
 * List of plugins and (unsigned) JSON account definitions
 * to use for the tests.
 */
static struct TestBlock tests[] = {
  { "sepa", "{ \"iban\":3 }" },
  { "test", "{ \"bank_uri\":3 }" },
  { NULL, NULL }
};


int
main (int argc,
      const char *const argv[])
{
  json_t *wire;
  json_error_t error;
  int ret;
  struct GNUNET_CONFIGURATION_Handle *cfg;
  struct TALER_WIRE_Plugin *plugin;
  const struct TestBlock *test;
  unsigned int i;

  GNUNET_log_setup ("test-wire-plugin",
                    "WARNING",
                    NULL);
  cfg = GNUNET_CONFIGURATION_create ();
  GNUNET_CONFIGURATION_set_value_string (cfg,
                                         "exchange",
                                         "currency",
                                         "EUR");
  ret = GNUNET_OK;
  for (i=0;NULL != (test = &tests[i])->plugin_name;i++)
  {
    plugin = TALER_WIRE_plugin_load (cfg,
                                     test->plugin_name);
    GNUNET_assert (NULL != plugin);
    wire = json_loads (test->json_proto, 0, NULL);
    GNUNET_assert (NULL != wire);
    // FIXME: do test...
    json_decref (wire);
    TALER_WIRE_plugin_unload (plugin);
    if (GNUNET_OK != ret)
    {
      fprintf (stdout,
               "%s FAILED\n",
               test->plugin_name);
      break;
    }
    else
    {
      fprintf (stdout,
               "%s PASS\n",
               test->plugin_name);
    }
  }
  GNUNET_CONFIGURATION_destroy (cfg);
  if (GNUNET_NO == ret)
    return 1;
  return 0;
}
