/*
  This file is part of TALER
  Copyright (C) 2015, 2016 GNUnet e.V.

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
 * @file auditordb/auditordb_plugin.c
 * @brief Logic to load database plugin
 * @author Christian Grothoff
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include "taler_auditordb_plugin.h"
#include <ltdl.h>


/**
 * Initialize the plugin.
 *
 * @param cfg configuration to use
 * @return #GNUNET_OK on success
 */
struct TALER_AUDITORDB_Plugin *
TALER_AUDITORDB_plugin_load (const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  char *plugin_name;
  char *lib_name;
  struct GNUNET_CONFIGURATION_Handle *cfg_dup;
  struct TALER_AUDITORDB_Plugin *plugin;

  if (GNUNET_SYSERR ==
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "auditor",
                                             "db",
                                             &plugin_name))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "auditor",
                               "db");
    return NULL;
  }
  (void) GNUNET_asprintf (&lib_name,
                          "libtaler_plugin_auditordb_%s",
                          plugin_name);
  GNUNET_free (plugin_name);
  cfg_dup = GNUNET_CONFIGURATION_dup (cfg);
  plugin = GNUNET_PLUGIN_load (lib_name,
                               cfg_dup);
  if (NULL != plugin)
    plugin->library_name = lib_name;
  else
    GNUNET_free (lib_name);
  GNUNET_CONFIGURATION_destroy (cfg_dup);
  return plugin;
}


/**
 * Shutdown the plugin.
 *
 * @param plugin the plugin to unload
 */
void
TALER_AUDITORDB_plugin_unload (struct TALER_AUDITORDB_Plugin *plugin)
{
  char *lib_name;

  if (NULL == plugin)
    return;
  lib_name = plugin->library_name;
  GNUNET_assert (NULL == GNUNET_PLUGIN_unload (lib_name,
                                               plugin));
  GNUNET_free (lib_name);
}



/* end of auditordb_plugin.c */
