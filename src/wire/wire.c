/*
  This file is part of TALER
  (C) 2015, 2016, 2017 GNUnet e.V.

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


/**
 * Closure of #check_for_wire.
 */
struct FindEnabledWireContext
{
  /**
   * Configuration we are usign.
   */
  const struct GNUNET_CONFIGURATION_Handle *cfg;

  /**
   * Callback to invoke.
   */
  TALER_WIRE_EnabledCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;
};


/**
 * Check if @a section begins with "exchange-wire-", and if
 * so if the "ENABLE" option is set to "YES".  If both are
 * true, call the callback from the context with the
 * rest of the section name.
 *
 * @param cls our `struct FindEnabledWireContext`
 * @param section name of a section in the configuration
 */
static void
check_for_wire (void *cls,
                const char *section)
{
  struct FindEnabledWireContext *ctx = cls;
  const char *name;

  if (0 != strncasecmp (section,
                        "exchange-wire-",
                        strlen ("exchange-wire-")))
    return;
  if (GNUNET_YES !=
      GNUNET_CONFIGURATION_get_value_yesno (ctx->cfg,
                                            section,
                                            "ENABLE"))
    return;
  name = &section[strlen ("exchange-wire-")];
  ctx->cb (ctx->cb_cls,
           name);
}


/**
 * Check which wire plugins are enabled in @a cfg and call @a cb for each one.
 *
 * @param cfg configuration to use
 * @param cb callback to invoke
 * @param cb_cls closure for @a cb
 */
void
TALER_WIRE_find_enabled (const struct GNUNET_CONFIGURATION_Handle *cfg,
                         TALER_WIRE_EnabledCallback cb,
                         void *cb_cls)
{
  struct FindEnabledWireContext ctx;

  ctx.cfg = cfg;
  ctx.cb = cb;
  ctx.cb_cls = cb_cls;
  GNUNET_CONFIGURATION_iterate_sections (cfg,
                                         &check_for_wire,
                                         &ctx);
}


/* end of wire.c */
