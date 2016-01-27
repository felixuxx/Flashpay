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
 * @file wire/wire.c
 * @brief Functions for loading wire plugins
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_wire_lib.h"

/**
 * Load a WIRE plugin.
 *
 * @param cfg configuration to use
 * @param plugin_name name of the plugin to load
 * @return #GNUNET_OK on success
 */
struct TALER_WIRE_Plugin *
TALER_WIRE_plugin_load (const struct GNUNET_CONFIGURATION_Handle *cfg,
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
 * Unload a WIRE plugin.
 *
 * @param plugin the plugin to unload
 */
void
TALER_WIRE_plugin_unload (struct TALER_WIRE_Plugin *plugin)
{
  char *lib_name;

  if (NULL == plugin)
    return;
  lib_name = plugin->library_name;
  GNUNET_assert (NULL == GNUNET_PLUGIN_unload (lib_name,
                                               plugin));
  GNUNET_free (lib_name);
}


/* end of wire.c */
