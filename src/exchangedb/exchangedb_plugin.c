/*
  This file is part of TALER
  Copyright (C) 2015 Taler Systems SA

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
 * @file exchangedb/exchangedb_plugin.c
 * @brief Logic to load database plugin
 * @author Christian Grothoff
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include "taler_exchangedb_lib.h"
#include <ltdl.h>


struct TALER_EXCHANGEDB_Plugin *
TALER_EXCHANGEDB_plugin_load (const struct GNUNET_CONFIGURATION_Handle *cfg,
                              bool skip_preflight)
{
  char *plugin_name;
  char *lib_name;
  struct TALER_EXCHANGEDB_Plugin *plugin;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "db",
                                             &plugin_name))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "db");
    return NULL;
  }
  GNUNET_asprintf (&lib_name,
                   "libtaler_plugin_exchangedb_%s",
                   plugin_name);
  GNUNET_free (plugin_name);
  plugin = GNUNET_PLUGIN_load (TALER_EXCHANGE_project_data (),
                               lib_name,
                               (void *) cfg);
  if (NULL == plugin)
  {
    GNUNET_free (lib_name);
    return NULL;
  }
  plugin->library_name = lib_name;
  if ( (! skip_preflight) &&
       (GNUNET_OK !=
        plugin->preflight (plugin->cls)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Database not ready. Try running taler-exchange-dbinit!\n");
    TALER_EXCHANGEDB_plugin_unload (plugin);
    return NULL;
  }
  return plugin;
}


void
TALER_EXCHANGEDB_plugin_unload (struct TALER_EXCHANGEDB_Plugin *plugin)
{
  char *lib_name;

  if (NULL == plugin)
    return;
  lib_name = plugin->library_name;
  GNUNET_assert (NULL == GNUNET_PLUGIN_unload (lib_name,
                                               plugin));
  GNUNET_free (lib_name);
}


/* end of exchangedb_plugin.c */
