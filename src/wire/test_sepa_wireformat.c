/*
  This file is part of TALER
  (C) 2015, 2016 GNUnet e.V.

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
 * @file wire/test_sepa_wireformat.c
 * @brief Tests for JSON SEPA format validation
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */

#include "platform.h"
#include "taler_util.h"
#include "taler_wire_plugin.h"


/* Valid SEPA data */
static const char * const valid_wire_str =
    "{ \"type\":\"SEPA\", \
\"IBAN\":\"DE67830654080004822650\",                 \
\"name\":\"GNUnet e.V.\",                               \
\"bic\":\"GENODEF1SLR\",                                 \
\"r\":123456789,                                     \
\"address\": \"foobar\"}";

/* IBAN has wrong country code */
static const char * const invalid_wire_str =
    "{ \"type\":\"SEPA\", \
\"IBAN\":\"XX67830654080004822650\",                 \
\"name\":\"GNUnet e.V.\",                               \
\"bic\":\"GENODEF1SLR\",                                 \
\"r\":123456789,                                     \
\"address\": \"foobar\"}";

/* IBAN has wrong checksum */
static const char * const invalid_wire_str2 =
    "{ \"type\":\"SEPA\", \
\"IBAN\":\"DE67830654080004822651\",                 \
\"name\":\"GNUnet e.V.\",                               \
\"bic\":\"GENODEF1SLR\",                                 \
\"r\":123456789,                                     \
\"address\": \"foobar\"}";

/* Unsupported wireformat type */
static const char * const unsupported_wire_str =
    "{ \"type\":\"unsupported\", \
\"IBAN\":\"DE67830654080004822650\",                 \
\"name\":\"GNUnet e.V.\",                               \
\"bic\":\"GENODEF1SLR\",                                 \
\"r\":123456789,                                     \
\"address\": \"foobar\"}";


/**
 * Initialize the plugin.
 *
 * @param cfg configuration to use
 * @return #GNUNET_OK on success
 */
static struct TALER_WIRE_Plugin *
wire_plugin_load (const struct GNUNET_CONFIGURATION_Handle *cfg,
                  const char *plugin_name)
{
  char *lib_name;
  struct TALER_WIRE_Plugin *plugin;

  (void) GNUNET_asprintf (&lib_name,
                          "libtaler_plugin_wire_%s",
                          plugin_name);
  plugin = GNUNET_PLUGIN_load (lib_name,
                               (void *) cfg);
  if (NULL != plugin)
    plugin->library_name = lib_name;
  else
    GNUNET_free (lib_name);
  return plugin;
}


/**
 * Shutdown the plugin.
 *
 * @param plugin the plugin to unload
 */
static void
wire_plugin_unload (struct TALER_WIRE_Plugin *plugin)
{
  char *lib_name;

  if (NULL == plugin)
    return;
  lib_name = plugin->library_name;
  GNUNET_assert (NULL == GNUNET_PLUGIN_unload (lib_name,
                                               plugin));
  GNUNET_free (lib_name);
}


int
main(int argc,
     const char *const argv[])
{
  json_t *wire;
  json_error_t error;
  int ret;
  struct GNUNET_CONFIGURATION_Handle *cfg;
  struct TALER_WIRE_Plugin *plugin;

  GNUNET_log_setup ("test-sepa-wireformats",
                    "WARNING",
                    NULL);
  cfg = GNUNET_CONFIGURATION_create ();
  GNUNET_CONFIGURATION_set_value_string (cfg,
                                         "mint",
                                         "currency",
                                         "EUR");
  plugin = wire_plugin_load (cfg,
                             "sepa");
  GNUNET_assert (NULL != plugin);
  (void) memset(&error, 0, sizeof(error));
  GNUNET_assert (NULL != (wire = json_loads (unsupported_wire_str, 0, NULL)));
  GNUNET_assert (GNUNET_YES != plugin->wire_validate (wire));
  json_decref (wire);
  GNUNET_assert (NULL != (wire = json_loads (invalid_wire_str, 0, NULL)));
  GNUNET_assert (GNUNET_NO == plugin->wire_validate (wire));
  json_decref (wire);
  GNUNET_assert (NULL != (wire = json_loads (invalid_wire_str2, 0, NULL)));
  GNUNET_assert (GNUNET_NO == plugin->wire_validate (wire));
  json_decref (wire);
  GNUNET_assert (NULL != (wire = json_loads (valid_wire_str, 0, &error)));
  ret = plugin->wire_validate (wire);
  json_decref (wire);
  wire_plugin_unload (plugin);
  GNUNET_CONFIGURATION_destroy (cfg);
  if (GNUNET_NO == ret)
    return 1;
  return 0;
}
