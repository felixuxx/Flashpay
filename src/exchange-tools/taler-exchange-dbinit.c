/*
  This file is part of TALER
  Copyright (C) 2014, 2015 GNUnet e.V.

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
 * @file exchange-tools/taler-exchange-dbinit.c
 * @brief Create tables for the exchange database.
 * @author Florian Dold
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <libpq-fe.h>
#include "taler_exchangedb_plugin.h"

/**
 * Exchange directory with the keys.
 */
static char *exchange_base_dir;

/**
 * Our configuration.
 */
static struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our DB plugin.
 */
static struct TALER_EXCHANGEDB_Plugin *plugin;


/**
 * The main function of the database initialization tool.
 * Used to initialize the Taler Exchange's database.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  static const struct GNUNET_GETOPT_CommandLineOption options[] = {
    {'d', "exchange-dir", "DIR",
     "exchange directory", 1,
     &GNUNET_GETOPT_set_filename, &exchange_base_dir},
    GNUNET_GETOPT_OPTION_HELP ("Initialize Taler Exchange database"),
    GNUNET_GETOPT_OPTION_VERSION (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };

  if (GNUNET_GETOPT_run ("taler-exchange-dbinit",
                         options,
                         argc, argv) < 0)
    return 1;

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-exchange-dbinit",
                                   "INFO",
                                   NULL));
  if (NULL == exchange_base_dir)
  {
    fprintf (stderr,
             "Exchange base directory not given.\n");
    return 1;
  }
  cfg = TALER_config_load (exchange_base_dir);
  if (NULL == cfg)
  {
    fprintf (stderr,
             "Failed to load exchange configuration.\n");
    return 1;
  }
  if (NULL ==
      (plugin = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize database plugin.\n");
    return 1;
  }
  if (GNUNET_OK !=
      plugin->create_tables (plugin->cls,
                             GNUNET_NO))
  {
    fprintf (stderr,
             "Failed to initialize database.\n");
    TALER_EXCHANGEDB_plugin_unload (plugin);
    return 1;
  }
  TALER_EXCHANGEDB_plugin_unload (plugin);
  return 0;
}

/* end of taler-exchange-dbinit.c */
