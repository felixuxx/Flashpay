/*
  This file is part of TALER
  Copyright (C) 2016,2018 Taler Systems SA

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
 * @file include/taler_wire_lib.h
 * @brief Interface for loading and unloading wire plugins
 * @author Christian Grothoff <christian@grothoff.org>
 */
#ifndef TALER_WIRE_H
#define TALER_WIRE_H

#include <gnunet/gnunet_util_lib.h>
#include "taler_wire_plugin.h"


/**
 * Obtain the payment method from a @a payto_url
 *
 * @param payto_url the URL to parse
 * @return NULL on error (malformed @a payto_url)
 */
char *
TALER_WIRE_payto_get_method (const char *payto_url);


/**
 * Load a WIRE plugin.
 *
 * @param cfg configuration to use
 * @param plugin_name name of the plugin to load
 * @return #GNUNET_OK on success
 */
struct TALER_WIRE_Plugin *
TALER_WIRE_plugin_load (const struct GNUNET_CONFIGURATION_Handle *cfg,
                        const char *plugin_name);


/**
 * Unload a WIRE plugin.
 *
 * @param plugin the plugin to unload
 */
void
TALER_WIRE_plugin_unload (struct TALER_WIRE_Plugin *plugin);


#endif
