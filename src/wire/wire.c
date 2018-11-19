/*
  This file is part of TALER
  (C) 2015, 2016, 2017, 2018 GNUnet e.V.

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
 * @file wire/wire.c
 * @brief Functions for loading wire plugins
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_wire_lib.h"


/**
 * A wire plugin that we have loaded.
 */
struct WirePlugin
{
  /**
   * We keep these in a DLL.
   */
  struct WirePlugin *next;

  /**
   * We keep these in a DLL.
   */
  struct WirePlugin *prev;

  /**
   * Type of this wire plugin.
   */
  char *type;

  /**
   * Wire plugin
   */
  struct TALER_WIRE_Plugin *plugin;

  /**
   * Reference counter for the plugin.
   */
  unsigned int rc;
};


/**
 * Head of the DLL of loaded wire plugins.
 */
static struct WirePlugin *wp_head;

/**
 * Tail of the DLL of loaded wire plugins.
 */
static struct WirePlugin *wp_tail;


/**
 * Load a WIRE plugin.
 *
 * @param cfg configuration to use
 * @param plugin_name name of the plugin to load
 * @return the plugin object pointer, or NULL upon errors.
 */
struct TALER_WIRE_Plugin *
TALER_WIRE_plugin_load (const struct GNUNET_CONFIGURATION_Handle *cfg,
                        const char *plugin_name)
{
  char *lib_name;
  struct TALER_WIRE_Plugin *plugin;
  struct WirePlugin *wp;

  for (wp = wp_head; NULL != wp; wp = wp->next)
    if (0 == strcasecmp (plugin_name,
                         wp->type))
    {
      wp->rc++;
      return wp->plugin;
    }
  (void) GNUNET_asprintf (&lib_name,
                          "libtaler_plugin_wire_%s",
                          plugin_name);
  plugin = GNUNET_PLUGIN_load (lib_name,
                               (void *) cfg);
  if (NULL != plugin)
    plugin->library_name = lib_name;
  else
    GNUNET_free (lib_name);
  if (NULL == plugin)
    return NULL;
  wp = GNUNET_new (struct WirePlugin);
  wp->plugin = plugin;
  wp->type = GNUNET_strdup (plugin_name);
  GNUNET_CONTAINER_DLL_insert (wp_head,
                               wp_tail,
                               wp);
  wp->rc = 1;
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
  struct WirePlugin *wp;
  char *lib_name;

  if (NULL == plugin)
    return;
  for (wp = wp_head; NULL != wp; wp = wp->next)
  {
    if (plugin == wp->plugin)
    {
      wp->rc--;
      if (0 < wp->rc)
        return;
      GNUNET_CONTAINER_DLL_remove (wp_head,
                                   wp_tail,
                                   wp);
      GNUNET_free (wp->type);
      GNUNET_free (wp);
      break;
    }
  }
  lib_name = plugin->library_name;
  GNUNET_assert (NULL == GNUNET_PLUGIN_unload (lib_name,
                                               plugin));
  GNUNET_free (lib_name);
}


/* end of wire.c */
